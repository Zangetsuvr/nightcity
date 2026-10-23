// Everything the launcher does for a server: the server list, Discord login,
// the modpack, starting the game and Discord status. app.js calls
// registerServerLauncher() once the app is ready.
//
// Every IPC call resolves to { ok: true, value } or { ok: false, error }, so
// the window always gets a plain message to show.

import path from 'path'
import { existsSync, readFileSync } from 'fs'
import { ServerApi } from './server-api.js'
import { discordLogin } from './discord-login.js'
import { applyModpack, restore } from './modpack.js'
import { gameRootFromExe, writeSession, clearSession, launchAndWait, isGameRunning } from './game.js'
import { parseAddress, apiUrl, resolveHost, loadServerList } from './servers.js'
import { setPresence } from './presence.js'

export function registerServerLauncher ({ electron, store, getWindow, configDir }) {
  const config = loadLauncherConfig(configDir)
  const userData = () => electron.app.getPath('userData')
  const stateFile = () => path.join(userData(), 'modpack-state.json')
  const cacheDir = () => path.join(userData(), 'modpack-cache')

  let playing = null // { key, info, startedAt } while the game runs

  const apiFor = (address) => new ServerApi(apiUrl(parseAddress(address)))
  const progress = (update) => getWindow()?.webContents.send('mp:progress', update)

  // ---------------------------------------------------------------- sessions (one per server)

  function saveSession (key, session) {
    const secure = electron.safeStorage.isEncryptionAvailable()
    const all = store.get('mp_sessions') || {}
    all[key] = {
      ...session,
      token: secure ? electron.safeStorage.encryptString(session.token).toString('base64') : session.token,
      encrypted: secure
    }
    store.set('mp_sessions', all)
  }

  function deleteSession (key) {
    const all = store.get('mp_sessions') || {}
    delete all[key]
    store.set('mp_sessions', all)
  }

  function loadSession (key) {
    const saved = (store.get('mp_sessions') || {})[key]
    if (!saved) return null
    if (new Date(saved.expiresUtc) <= new Date()) {
      deleteSession(key)
      return null
    }
    try {
      const token = saved.encrypted ? electron.safeStorage.decryptString(Buffer.from(saved.token, 'base64')) : saved.token
      return { ...saved, token }
    } catch {
      deleteSession(key)
      return null
    }
  }

  const publicSession = (s) => s
    ? { discordName: s.discordName, characters: s.characters || [], maxCharacters: s.maxCharacters || 1, expiresUtc: s.expiresUtc }
    : null

  // ---------------------------------------------------------------- Discord status

  function launcherPresence (info) {
    if (!info?.DiscordClientId) return setPresence(null)
    return setPresence({
      clientId: info.DiscordClientId,
      details: `Getting ready for ${info.ServerName}`,
      state: 'In the launcher',
      imageKey: info.DiscordImageKey,
      imageText: info.ServerName,
      buttons: inviteButton(info)
    })
  }

  function playingPresence (info, onlineAs, startedAt) {
    if (!info?.DiscordClientId) return setPresence(null)
    return setPresence({
      clientId: info.DiscordClientId,
      details: `Roleplaying on ${info.ServerName}`,
      state: onlineAs ? `as ${onlineAs}` : 'Loading into Night City',
      imageKey: info.DiscordImageKey,
      imageText: info.ServerName,
      startTimestamp: startedAt,
      partySize: info.PlayersOnline > 0 ? info.PlayersOnline : undefined,
      partyMax: info.MaxPlayers > 0 ? info.MaxPlayers : undefined,
      buttons: inviteButton(info)
    })
  }

  const inviteButton = (info) =>
    /^https:\/\/(discord\.gg|discord\.com\/invite)\//i.test(info?.DiscordInvite || '')
      ? [{ label: 'Join the Discord', url: info.DiscordInvite }]
      : undefined

  // While playing, refresh the status every 30 s: player count and which
  // character the player loaded.
  async function presenceLoop (key) {
    while (playing?.key === key) {
      try {
        const api = apiFor(key)
        const session = loadSession(key)
        const [info, me] = await Promise.all([api.info(), session ? api.me(session.token) : null])
        if (playing?.key !== key) break
        playing.info = info
        await playingPresence(info, me?.OnlineAs, playing.startedAt)
      } catch {
        // keep the last status if the server doesn't answer for a moment
      }
      await new Promise(resolve => setTimeout(resolve, 30000))
    }
  }

  // ---------------------------------------------------------------- playing

  async function play (address) {
    const { key, host, port } = parseAddress(address)
    const api = apiFor(key)

    const exePath = store.get('game_path')
    if (!exePath || !existsSync(exePath)) throw new Error('Pick your Cyberpunk2077.exe first.')
    const gameRoot = gameRootFromExe(exePath)

    const session = loadSession(key)
    if (!session) throw new Error('Your login expired. Log in with Discord again.')

    progress({ step: 'checking-server' })
    const info = await api.info()
    const gameIp = await resolveHost(host).catch(() => {
      throw new Error(`Couldn't find the server's address (${host}).`)
    })

    let fingerprint = ''
    if (info.ModpackRequired) {
      const manifest = await api.manifest()
      try {
        fingerprint = await applyModpack(gameRoot, manifest, {
          cacheDir: cacheDir(),
          stateFile: stateFile(),
          download: (rel, dest) => api.download(rel, dest),
          onProgress: progress
        })
      } catch (e) {
        progress({ step: 'restoring' })
        await restore(gameRoot, stateFile()).catch(() => {})
        throw e
      }
    }

    // The character name comes from the save (named in the game's character
    // creator); the session carries the login and where the server is.
    await writeSession(gameRoot, config.sessionFile, {
      token: `${session.token}:${fingerprint}`,
      apiUrl: apiUrl({ host, port })
    })

    playing = { key, info, startedAt: new Date() }
    progress({ step: 'playing' })
    void presenceLoop(key)
    try {
      await launchAndWait(exePath, gameIp, port)
    } finally {
      playing = null
      await clearSession(gameRoot, config.sessionFile).catch(() => {})
      progress({ step: 'restoring' })
      await restore(gameRoot, stateFile())
      progress({ step: 'done' })
      await launcherPresence(info).catch(() => {})
    }
  }

  // ---------------------------------------------------------------- IPC

  const handle = (channel, fn) => electron.ipcMain.handle(channel, async (event, ...args) => {
    try {
      return { ok: true, value: await fn(...args) }
    } catch (e) {
      return { ok: false, error: e.message || String(e) }
    }
  })

  handle('mp:list', async () => loadServerList(config, store.get('mp_custom_servers') || []))

  handle('mp:add-server', async (address) => {
    const { key } = parseAddress(address)
    // Only add servers that actually run this launcher's server side.
    const info = await apiFor(key).info().catch(() => {
      throw new Error('No compatible server answered at that address.')
    })
    const custom = store.get('mp_custom_servers') || []
    if (!custom.some(s => parseAddress(s.address).key === key)) {
      custom.push({ name: info.ServerName, address: key })
      store.set('mp_custom_servers', custom)
    }
    return { name: info.ServerName, address: key }
  })

  handle('mp:remove-server', async (address) => {
    const { key } = parseAddress(address)
    store.set('mp_custom_servers', (store.get('mp_custom_servers') || []).filter(s => parseAddress(s.address).key !== key))
    deleteSession(key)
    return true
  })

  // Live details for one server card: name, players, ping. Never throws, so a
  // dead server just shows as offline.
  handle('mp:status', async (address) => {
    const started = Date.now()
    try {
      const info = await apiFor(address).info()
      return { online: true, ping: Date.now() - started, info }
    } catch {
      return { online: false }
    }
  })

  handle('mp:info', async (address) => {
    const { key } = parseAddress(address)
    const api = apiFor(key)
    const info = await api.info()
    const session = loadSession(key)
    if (session) {
      try {
        const me = await api.me(session.token)
        session.characters = me.Characters
        session.maxCharacters = me.MaxCharacters
        saveSession(key, session)
      } catch (e) {
        if (e.status === 401) {
          deleteSession(key)
          if (!playing) await launcherPresence(info).catch(() => {})
          return { ...info, session: null }
        }
      }
    }
    if (!playing) await launcherPresence(info).catch(() => {})
    return { ...info, session: publicSession(session) }
  })

  handle('mp:login', async (address) => {
    const { key } = parseAddress(address)
    const api = apiFor(key)
    const info = await api.info()
    const code = await discordLogin(info, url => electron.shell.openExternal(url))
    const result = await api.login(code)
    const session = {
      token: result.Token,
      expiresUtc: result.ExpiresUtc,
      discordName: result.DiscordName,
      characters: result.Characters,
      maxCharacters: result.MaxCharacters
    }
    saveSession(key, session)
    getWindow()?.focus()
    return publicSession(session)
  })

  handle('mp:logout', async (address) => {
    deleteSession(parseAddress(address).key)
    return null
  })

  handle('mp:play', play)
  handle('mp:is-playing', async () => playing !== null)

  return {
    isPlaying: () => playing !== null,
    progress,
    restoreLeftovers: async () => {
      try {
        if (!existsSync(stateFile())) return
        if (await isGameRunning()) return // still playing; restored after the next session instead
        const exePath = store.get('game_path')
        await restore(exePath ? gameRootFromExe(exePath) : '', stateFile())
      } catch (e) {
        console.error('Restoring mods failed:', e)
      }
    }
  }
}

function loadLauncherConfig (configDir) {
  const candidates = [
    path.join(configDir, 'launcher-config.json'),
    path.join(process.resourcesPath || '', 'launcher-config.json'),
    path.join(path.dirname(process.execPath), 'launcher-config.json')
  ]
  const file = candidates.find(existsSync)
  if (!file) throw new Error('launcher-config.json is missing.')
  const config = JSON.parse(readFileSync(file, 'utf8'))
  return {
    servers: config.servers || [],
    serverListUrl: config.serverListUrl || '',
    sessionFile: config.sessionFile || 'red4ext/plugins/CyberpunkMP/session.json'
  }
}
