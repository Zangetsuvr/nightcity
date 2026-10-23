// Makes the player's mods exactly match the server's modpack, and puts their
// own setup back afterwards.
//
// While playing on the server, the game folder holds only modpack files: any
// other mod is moved into <game>/_mp_set_aside/, and any modpack file that
// replaced a different version of the player's own file has the original moved
// there too. After the game closes, restore() undoes everything, so the
// player's single-player setup comes back exactly as it was.
//
// What's been changed is written to a state file before each step, so if the
// launcher or PC crashes mid-way, the next start can still restore.
//
// FINGERPRINT RULE - must match Modpack.cs on the server exactly:
//   1. Paths use "/" and are compared in lower case.
//   2. Take every mod file (under a mod root, or one of the single mod files)
//      that isn't ignored.
//   3. Sort by lower-cased path (plain code-unit order).
//   4. For each, append  lowercase(path) + "\n" + sha256hex + "\n".
//   5. The fingerprint is the SHA-256 (lower-case hex) of that UTF-8 text.

import { createHash } from 'crypto'
import { createReadStream, promises as fs } from 'fs'
import path from 'path'

export const SET_ASIDE_DIR = '_mp_set_aside'

// ------------------------------------------------------------------ shared rules

export function normalize (p) {
  return p.replace(/\\/g, '/').replace(/^\/+|\/+$/g, '')
}

export function globToRegex (glob) {
  const g = normalize(glob).toLowerCase()
  let out = '^'
  for (let i = 0; i < g.length; i++) {
    const c = g[i]
    if (c === '*' && g[i + 1] === '*') {
      if (g[i + 2] === '/') {
        out += '(?:.*/)?'
        i += 2
      } else {
        out += '.*'
        i += 1
      }
    } else if (c === '*') {
      out += '[^/]*'
    } else if (c === '?') {
      out += '[^/]'
    } else {
      out += c.replace(/[.*+?^${}()|[\]\\/\- ]/g, '\\$&')
    }
  }
  return new RegExp(out + '$')
}

export function makeRules (manifest) {
  const roots = manifest.Roots.map(r => normalize(r).toLowerCase())
  const files = new Set(manifest.Files.map(f => normalize(f).toLowerCase()))
  const ignore = manifest.Ignore.map(globToRegex)
  return {
    isModPath (rel) {
      const p = normalize(rel).toLowerCase()
      return roots.some(r => p.startsWith(r + '/')) || files.has(p)
    },
    isIgnored (rel) {
      const p = normalize(rel).toLowerCase()
      return ignore.some(r => r.test(p))
    }
  }
}

export function computeFingerprint (files) {
  const sorted = files
    .map(f => ({ path: normalize(f.path).toLowerCase(), hash: f.sha256.toLowerCase() }))
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
  let text = ''
  for (const f of sorted) text += f.path + '\n' + f.hash + '\n'
  return createHash('sha256').update(text, 'utf8').digest('hex')
}

export function sha256File (file) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256')
    createReadStream(file)
      .on('data', d => hash.update(d))
      .on('end', () => resolve(hash.digest('hex')))
      .on('error', reject)
  })
}

// ------------------------------------------------------------------ scanning

async function walk (dir, base, out) {
  let entries
  try {
    entries = await fs.readdir(dir, { withFileTypes: true })
  } catch (e) {
    if (e.code === 'ENOENT') return
    throw e
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) await walk(full, base, out)
    else if (entry.isFile() || entry.isSymbolicLink()) out.push(normalize(path.relative(base, full)))
  }
}

/** Every mod file currently in the game folder that the rules care about (not ignored). */
export async function scanModFiles (gameRoot, manifest) {
  const rules = makeRules(manifest)
  const found = []
  for (const root of manifest.Roots) await walk(path.join(gameRoot, root), gameRoot, found)
  for (const file of manifest.Files) {
    try {
      const st = await fs.lstat(path.join(gameRoot, file))
      if (st.isFile() || st.isSymbolicLink()) found.push(normalize(file))
    } catch (e) {
      if (e.code !== 'ENOENT') throw e
    }
  }
  return [...new Set(found)].filter(rel => rules.isModPath(rel) && !rules.isIgnored(rel))
}

/** The fingerprint of the mods actually in the game folder right now. */
export async function localFingerprint (gameRoot, manifest) {
  const files = await scanModFiles(gameRoot, manifest)
  const hashed = []
  for (const rel of files) hashed.push({ path: rel, sha256: await sha256File(path.join(gameRoot, rel)) })
  return computeFingerprint(hashed)
}

// ------------------------------------------------------------------ state file

async function readState (stateFile) {
  try {
    return JSON.parse(await fs.readFile(stateFile, 'utf8'))
  } catch (e) {
    if (e.code === 'ENOENT') return null
    throw e
  }
}

async function writeState (stateFile, state) {
  await fs.mkdir(path.dirname(stateFile), { recursive: true })
  const tmp = stateFile + '.tmp'
  await fs.writeFile(tmp, JSON.stringify(state, null, 2))
  await fs.rename(tmp, stateFile)
}

async function moveFile (from, to) {
  await fs.mkdir(path.dirname(to), { recursive: true })
  try {
    await fs.rename(from, to)
  } catch (e) {
    if (e.code !== 'EXDEV') throw e
    await fs.copyFile(from, to)
    await fs.unlink(from)
  }
}

async function removeIfExists (file) {
  try {
    await fs.unlink(file)
  } catch (e) {
    if (e.code !== 'ENOENT') throw e
  }
}

// ------------------------------------------------------------------ apply / restore

// Files mods rewrite while the game runs, outside the mod folders: redscript
// compiles all scripts into final.redscripts (keeping the original as .bk).
// They're copied before playing and put back afterwards, so single player
// isn't left with the multiplayer scripts once the modpack is removed.
const SNAPSHOT_FILES = ['r6/cache/final.redscripts', 'r6/cache/final.redscripts.bk']
const SNAPSHOT_DIR = '__snapshot__'

async function exists (file) {
  try {
    await fs.access(file)
    return true
  } catch {
    return false
  }
}

/**
 * Makes the game folder match the modpack.
 *
 * options.cacheDir      where downloaded modpack files are kept (by hash), so
 *                       they don't need downloading again next time
 * options.stateFile     where the record of changes is kept
 * options.download      async (relPath, destFile) => void, downloads one modpack file
 * options.onProgress    ({ step, done, total, file }) => void
 *
 * Returns the fingerprint of the game folder afterwards. Throws if it still
 * doesn't match (the caller should then restore).
 */
export async function applyModpack (gameRoot, manifest, options) {
  const { cacheDir, stateFile, download, onProgress = () => {} } = options

  // A previous session that never got restored (crash, power cut) comes first.
  await restore(gameRoot, stateFile)

  const state = { gameRoot, setAside: [], added: [], replaced: [], snapshots: [], absent: [] }
  await writeState(stateFile, state)

  const setAsideDir = path.join(gameRoot, SET_ASIDE_DIR)
  for (const rel of SNAPSHOT_FILES) {
    const file = path.join(gameRoot, rel)
    if (await exists(file)) {
      const copy = path.join(setAsideDir, SNAPSHOT_DIR, rel)
      await fs.mkdir(path.dirname(copy), { recursive: true })
      await fs.copyFile(file, copy)
      state.snapshots.push(rel)
    } else {
      state.absent.push(rel)
    }
    await writeState(stateFile, state)
  }

  const wanted = new Map(manifest.Entries.map(e => [normalize(e.Path).toLowerCase(), e]))
  const present = await scanModFiles(gameRoot, manifest)
  const setAsideRoot = path.join(gameRoot, SET_ASIDE_DIR)

  // 1. Move every mod that isn't in the modpack out of the way.
  const extras = present.filter(rel => !wanted.has(rel.toLowerCase()))
  let done = 0
  for (const rel of extras) {
    onProgress({ step: 'setting-aside', done: done++, total: extras.length, file: rel })
    await moveFile(path.join(gameRoot, rel), path.join(setAsideRoot, rel))
    state.setAside.push(rel)
    await writeState(stateFile, state)
  }

  // 2. Put every modpack file in place, downloading only what's not cached.
  const presentByLower = new Map(present.map(rel => [rel.toLowerCase(), rel]))
  const entries = manifest.Entries
  done = 0
  for (const entry of entries) {
    onProgress({ step: 'installing', done: done++, total: entries.length, file: entry.Path })

    const key = normalize(entry.Path).toLowerCase()
    const existingRel = presentByLower.get(key)
    const target = path.join(gameRoot, existingRel ?? normalize(entry.Path))

    if (existingRel) {
      const st = await fs.stat(target)
      if (st.size === entry.Size && (await sha256File(target)) === entry.Sha256) continue // already right
    }

    const cached = path.join(cacheDir, entry.Sha256)
    if (!(await isCachedCorrectly(cached, entry))) {
      await fs.mkdir(cacheDir, { recursive: true })
      const partial = cached + '.part'
      await download(entry.Path, partial)
      const got = await sha256File(partial)
      if (got !== entry.Sha256) {
        await removeIfExists(partial)
        throw new Error(`Download of ${entry.Path} was corrupted. Please try again.`)
      }
      await fs.rename(partial, cached)
    }

    if (existingRel) {
      // The player has their own, different version: keep it safe to restore later.
      await moveFile(target, path.join(setAsideRoot, existingRel))
      state.setAside.push(existingRel)
      state.replaced.push(existingRel)
    } else {
      state.added.push(normalize(entry.Path))
    }
    await writeState(stateFile, state)

    await fs.mkdir(path.dirname(target), { recursive: true })
    await fs.copyFile(cached, target)
  }

  onProgress({ step: 'checking', done: 0, total: 1 })
  const fingerprint = await localFingerprint(gameRoot, manifest)
  if (fingerprint !== manifest.Fingerprint) {
    throw new Error('Your mods still don\'t match the server after updating. Close any program using the game folder and try again.')
  }
  onProgress({ step: 'ready', done: 1, total: 1 })
  return fingerprint
}

async function isCachedCorrectly (file, entry) {
  try {
    const st = await fs.stat(file)
    return st.size === entry.Size && (await sha256File(file)) === entry.Sha256
  } catch (e) {
    if (e.code === 'ENOENT') return false
    throw e
  }
}

/**
 * Puts the player's own mods back and removes modpack files that weren't
 * there before. Safe to call any time; does nothing if nothing is pending.
 */
export async function restore (gameRoot, stateFile) {
  const state = await readState(stateFile)
  if (!state) return false

  const root = state.gameRoot || gameRoot
  const setAsideRoot = path.join(root, SET_ASIDE_DIR)

  for (const rel of [...state.added, ...state.replaced]) await removeIfExists(path.join(root, rel))

  for (const rel of state.setAside) {
    const from = path.join(setAsideRoot, rel)
    try {
      await fs.access(from)
    } catch {
      continue // already moved back
    }
    const to = path.join(root, rel)
    await removeIfExists(to)
    await moveFile(from, to)
  }

  for (const rel of state.snapshots || []) {
    const copy = path.join(setAsideRoot, SNAPSHOT_DIR, rel)
    if (await exists(copy)) await fs.copyFile(copy, path.join(root, rel))
  }
  for (const rel of state.absent || []) await removeIfExists(path.join(root, rel))

  await fs.rm(setAsideRoot, { recursive: true, force: true })
  await fs.unlink(stateFile)
  return true
}
