// End-to-end test of the launcher's modpack sync against a fake server that
// serves a modpack folder the way AccountSystem does.
import http from 'http'
import { promises as fs } from 'fs'
import path from 'path'
import os from 'os'
import assert from 'assert'
import { createHash } from 'crypto'
import { applyModpack, restore, localFingerprint, computeFingerprint, globToRegex, makeRules } from '../modpack.js'
import { ServerApi } from '../server-api.js'

const T = await fs.mkdtemp(path.join(os.tmpdir(), 'mp-modpack-test-'))
const sha = b => createHash('sha256').update(b).digest('hex')
async function put (root, rel, content) {
  const f = path.join(root, rel); await fs.mkdir(path.dirname(f), { recursive: true }); await fs.writeFile(f, content)
}
async function tree (root) {
  const out = {}
  async function w (d) {
    for (const e of await fs.readdir(d, { withFileTypes: true }).catch(() => [])) {
      const f = path.join(d, e.name)
      if (e.isDirectory()) await w(f); else out[path.relative(root, f).replace(/\\/g, '/')] = await fs.readFile(f, 'utf8')
    }
  }
  await w(root); return out
}

// Same defaults as AccountSystem/Config.cs
const config = {
  Roots: ['archive/pc/mod', 'bin/x64/plugins', 'red4ext', 'r6/scripts', 'r6/tweaks', 'mods'],
  Files: ['bin/x64/version.dll', 'bin/x64/winmm.dll', 'bin/x64/d3d11.dll', 'bin/x64/dxgi.dll', 'bin/x64/dinput8.dll', 'bin/x64/global.ini'],
  Ignore: ['**/*.log', '**/logs/**', '**/*.sqlite3', 'bin/x64/plugins/cyber_engine_tweaks/**/*.json', 'bin/x64/plugins/cyber_engine_tweaks/*.ini', 'red4ext/plugins/CyberpunkMP/session.json', 'red4ext/plugins/CyberpunkMP/Rpc/**']
}

// ---- glob rules
const g = s => globToRegex(s)
assert(g('**/*.log').test('red4ext/logs/x.log') && g('**/*.log').test('a.log'))
assert(g('**/logs/**').test('red4ext/logs/a/b.txt') && g('**/logs/**').test('logs/a'))
assert(g('bin/x64/plugins/cyber_engine_tweaks/*.ini').test('bin/x64/plugins/cyber_engine_tweaks/layout.ini'))
assert(!g('bin/x64/plugins/cyber_engine_tweaks/*.ini').test('bin/x64/plugins/cyber_engine_tweaks/mods/x/a.ini'))
assert(g('red4ext/plugins/CyberpunkMP/session.json').test('red4ext/plugins/cyberpunkmp/session.json'))
const rules = makeRules(config)
assert(rules.isModPath('archive/pc/mod/a.archive') && !rules.isModPath('archive/pc/content/a.archive'))
assert(rules.isModPath('BIN/X64/version.dll') && !rules.isModPath('bin/x64/Cyberpunk2077.exe'))

// ---- server modpack folder
const pack = path.join(T, 'pack')
await put(pack, 'red4ext/plugins/CyberpunkMP/CyberpunkMP.dll', 'mp-dll-v2')
await put(pack, 'red4ext/RED4ext.dll', 'red4ext')
await put(pack, 'bin/x64/winmm.dll', 'loader')
await put(pack, 'archive/pc/mod/nightcity_guns.archive', 'guns')
await put(pack, 'bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.asi', 'cet')
await put(pack, 'red4ext/logs/red4ext.log', 'ignored log in pack')
const packFiles = Object.entries(await tree(pack))
  .filter(([rel]) => rules.isModPath(rel) && !rules.isIgnored(rel))
  .map(([rel, c]) => ({ Path: rel, Sha256: sha(c), Size: Buffer.byteLength(c) }))
  .sort((a, b) => a.Path.toLowerCase() < b.Path.toLowerCase() ? -1 : 1)
const manifest = { Fingerprint: computeFingerprint(packFiles.map(e => ({ path: e.Path, sha256: e.Sha256 }))), ...config, Entries: packFiles }
assert.equal(packFiles.length, 5, 'log in pack must be ignored')

let downloads = 0
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x')
  if (url.pathname.endsWith('/modpack')) return res.end(JSON.stringify(manifest))
  if (url.pathname.endsWith('/modpack/file')) {
    const rel = url.searchParams.get('path')
    if (!packFiles.some(e => e.Path.toLowerCase() === rel.toLowerCase())) return res.writeHead(404).end('{"message":"Not part of the modpack."}')
    downloads++
    return res.end(await fs.readFile(path.join(pack, rel)))
  }
  if (url.pathname.endsWith('/info')) return res.end(JSON.stringify({ ModpackRequired: true }))
  res.writeHead(404).end()
})
await new Promise(r => server.listen(0, '127.0.0.1', r))
const apiClient = new ServerApi(`http://127.0.0.1:${server.address().port}`)
const fetched = await apiClient.manifest()
assert.equal(fetched.Fingerprint, manifest.Fingerprint)
await assert.rejects(apiClient.download('../../etc/passwd', path.join(T, 'x')), /404/)

// ---- player's game folder with their own single-player mods
const game = path.join(T, 'game')
await put(game, 'bin/x64/Cyberpunk2077.exe', 'game exe')                         // not a mod
await put(game, 'archive/pc/content/base.archive', 'base game')                  // not a mod
await put(game, 'red4ext/plugins/CyberpunkMP/CyberpunkMP.dll', 'mp-dll-v1')      // older version of a pack file
await put(game, 'red4ext/RED4ext.dll', 'red4ext')                                // identical to pack
await put(game, 'archive/pc/mod/sp_reshade.archive', 'sp mod')                   // extra
await put(game, 'bin/x64/plugins/cyber_engine_tweaks/mods/trainer/init.lua', 'cheat') // extra CET mod
await put(game, 'bin/x64/plugins/cyber_engine_tweaks/config.json', 'cet settings')    // ignored, stays
await put(game, 'bin/x64/dxgi.dll', 'reshade')                                   // extra injector
await put(game, 'red4ext/logs/old.log', 'log')                                   // ignored, stays
const before = await tree(game)
assert.notEqual(await localFingerprint(game, manifest), manifest.Fingerprint)

const stateFile = path.join(T, 'state.json')
const cacheDir = path.join(T, 'cache')
const fp = await applyModpack(game, manifest, { cacheDir, stateFile, download: (r, d) => apiClient.download(r, d) })
assert.equal(fp, manifest.Fingerprint)
const during = await tree(game)
assert.equal(during['red4ext/plugins/CyberpunkMP/CyberpunkMP.dll'], 'mp-dll-v2')
assert(!('archive/pc/mod/sp_reshade.archive' in during))
assert(!('bin/x64/plugins/cyber_engine_tweaks/mods/trainer/init.lua' in during))
assert(!('bin/x64/dxgi.dll' in during))
assert.equal(during['bin/x64/plugins/cyber_engine_tweaks/config.json'], 'cet settings')
assert.equal(during['archive/pc/content/base.archive'], 'base game')
assert.equal(downloads, 4, 'identical file must not be downloaded')
console.log('apply: game matches modpack, extras set aside, 4 downloads')

// A cheat dropped in after syncing changes the fingerprint
await put(game, 'r6/scripts/godmode.reds', 'cheat')
assert.notEqual(await localFingerprint(game, manifest), manifest.Fingerprint)
await fs.unlink(path.join(game, 'r6/scripts/godmode.reds'))

// ---- restore puts everything back exactly
assert(await restore(game, stateFile))
const after = await tree(game)
for (const k of Object.keys(after)) if (!(k in before)) assert(k === 'r6/scripts' , `unexpected file left: ${k}`)
assert.deepEqual(after, before)
console.log('restore: game folder identical to before')

// ---- second session uses the cache (no new downloads)
downloads = 0
await applyModpack(game, manifest, { cacheDir, stateFile, download: (r, d) => apiClient.download(r, d) })
assert.equal(downloads, 0)
// ---- crash: state left behind, next apply restores first and still works
await applyModpack(game, manifest, { cacheDir, stateFile, download: (r, d) => apiClient.download(r, d) })
assert.equal(await localFingerprint(game, manifest), manifest.Fingerprint)
await restore(game, stateFile)
assert.deepEqual(await tree(game), before)
console.log('cache reused; crash recovery restores cleanly')

// ---- corrupted download is rejected and nothing is left half-done
const badManifest = { ...manifest, Entries: manifest.Entries.map(e => e.Path.endsWith('.archive') ? { ...e, Sha256: 'f'.repeat(64) } : e) }
await assert.rejects(applyModpack(game, badManifest, { cacheDir: path.join(T, 'cache2'), stateFile, download: (r, d) => apiClient.download(r, d) }), /corrupted/)
await restore(game, stateFile)
assert.deepEqual(await tree(game), before)
console.log('corrupted download rejected; restore clean')

// ---- redscript's compiled scripts are put back after playing
await put(game, 'r6/cache/final.redscripts', 'vanilla scripts')
const beforeScripts = await tree(game)
await applyModpack(game, manifest, { cacheDir, stateFile, download: (r, d) => apiClient.download(r, d) })
await put(game, 'r6/cache/final.redscripts', 'compiled with multiplayer scripts')
await put(game, 'r6/cache/final.redscripts.bk', 'vanilla scripts')
await restore(game, stateFile)
assert.deepEqual(await tree(game), beforeScripts)
console.log('restore: compiled scripts put back, redscript backup removed')

console.log('FINGERPRINT_VECTOR', JSON.stringify(manifest.Entries.map(e => [e.Path, e.Sha256])), manifest.Fingerprint)
server.close()
