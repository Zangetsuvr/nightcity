// Starting the game and noticing when it has really closed.

import { execFile, spawn } from 'child_process'
import { promises as fs } from 'fs'
import path from 'path'

const EXE = 'Cyberpunk2077.exe'

/** Game folder from the path to Cyberpunk2077.exe (<game>/bin/x64/Cyberpunk2077.exe). */
export function gameRootFromExe (exePath) {
  return path.dirname(path.dirname(path.dirname(exePath)))
}

/**
 * Writes the login the game reads (see App/Network/Session.cpp):
 * { token: "<session>:<mod fingerprint>", apiUrl: "http://server:port" }
 */
export async function writeSession (gameRoot, sessionFile, session) {
  const file = path.join(gameRoot, sessionFile)
  await fs.mkdir(path.dirname(file), { recursive: true })
  await fs.writeFile(file, JSON.stringify(session))
}

/** The token works like a password until it expires, so it isn't left lying around. */
export async function clearSession (gameRoot, sessionFile) {
  try {
    await fs.unlink(path.join(gameRoot, sessionFile))
  } catch (e) {
    if (e.code !== 'ENOENT') throw e
  }
}

export function isGameRunning () {
  if (process.platform !== 'win32') return Promise.resolve(false)
  return new Promise(resolve => {
    execFile('tasklist', ['/FI', `IMAGENAME eq ${EXE}`, '/NH'], (err, stdout) => {
      resolve(!err && stdout.toLowerCase().includes(EXE.toLowerCase()))
    })
  })
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

/**
 * Starts the game pointed at the server and resolves once it has fully closed.
 * Steam and GOG sometimes restart the game through their own client, so the
 * first process can exit while the game keeps running; this waits for every
 * Cyberpunk2077.exe to be gone (two checks in a row) before resolving.
 */
export async function launchAndWait (exePath, host, port) {
  const child = spawn(exePath, ['-online', '--online', '-ip', String(host), '-port', String(port), '--launcher-skip', '-skipStartScreen'], {
    cwd: path.dirname(exePath),
    detached: true,
    stdio: 'ignore'
  })

  await new Promise((resolve, reject) => {
    child.once('error', reject)
    child.once('spawn', resolve)
  })
  child.unref()

  await new Promise(resolve => child.once('exit', resolve))
  await sleep(15000) // give a store client time to restart it

  let quietChecks = 0
  while (quietChecks < 2) {
    quietChecks = (await isGameRunning()) ? 0 : quietChecks + 1
    await sleep(5000)
  }
}
