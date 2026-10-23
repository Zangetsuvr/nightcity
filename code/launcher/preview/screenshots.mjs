// Renders the built launcher UI (electron/dist) in Chromium with fake launcher
// APIs and saves screenshots of its main states, for design review in CI.
//   node preview/screenshots.mjs <dist dir> <output dir>
import http from 'http'
import { promises as fs } from 'fs'
import path from 'path'
import { chromium } from 'playwright'

const [dist, out] = process.argv.slice(2)
await fs.mkdir(out, { recursive: true })

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.svg': 'image/svg+xml' }
const server = http.createServer(async (req, res) => {
  const rel = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  const file = path.join(dist, rel === '/' ? 'index.html' : rel)
  try {
    const body = await fs.readFile(file)
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] ?? 'application/octet-stream' }).end(body)
  } catch {
    res.writeHead(404).end()
  }
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const base = `http://127.0.0.1:${server.address().port}/`

const info = {
  ServerName: 'Night City Roleplay',
  Description: 'Serious roleplay in Night City. Jobs, cars, and a reputation you build yourself.',
  DiscordInvite: 'https://discord.gg/example',
  PlayersOnline: 12,
  MaxPlayers: 40,
  Tags: 'Roleplay, Whitelist, NA',
  LoginRequired: true,
  ModpackRequired: true,
  ModpackFiles: 94
}
const session = { discordName: 'Arcadia', characters: ['Jackie Welles'], maxCharacters: 1, expiresUtc: new Date(Date.now() + 11.5 * 3600e3).toISOString() }

const scenarios = {
  'logged-out': { servers: 1, session: null },
  'logged-in': { servers: 1, session },
  'installing': { servers: 1, session, progress: { step: 'installing', done: 41, total: 94, file: 'red4ext/plugins/ArchiveXL/ArchiveXL.dll' }, busyPlay: true },
  'server-list': { servers: 3, session: null, noLast: true },
  'keybinds': { servers: 1, session, openKeys: true }
}

const browser = await chromium.launch()
for (const [name, s] of Object.entries(scenarios)) {
  const page = await browser.newPage({ viewport: { width: 1080, height: 850 } })
  await page.addInitScript(({ s, info }) => {
    const ok = value => Promise.resolve({ ok: true, value })
    const list = [
      { name: 'Night City Roleplay', address: '40.160.151.157:11778', source: 'built-in' },
      { name: 'Badlands Loot', address: 'loot.example.com:11778', source: 'list' },
      { name: 'Friends server', address: '10.0.0.5:11778', source: 'custom' }
    ].slice(0, s.servers)
    if (s.noLast) localStorage.clear()
    let progressCb = null
    window.electronAPI = {
      getGamePath: () => Promise.resolve('C:\\Program Files (x86)\\Steam\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\Cyberpunk2077.exe'),
      pathExists: () => true, setGamePath () {}, selectGameDialog: () => Promise.resolve({ canceled: true }),
      minimizeApp () {}, maximizeApp () {}, closeApp () {}
    }
    window.mpAPI = {
      list: () => ok(list),
      status: () => ok({ online: true, ping: 34, info }),
      info: () => ok({ ...info, session: s.session }),
      login: () => new Promise(() => {}),
      logout: () => ok(null),
      play: () => { if (s.progress) setTimeout(() => progressCb?.(s.progress), 50); return new Promise(() => {}) },
      addServer: () => ok({ address: 'x' }),
      removeServer: () => ok(true),
      keybinds: () => ok({
        actions: [
          { id: 'chat', label: 'Open chat', defaultKey: 'IK_Semicolon' },
          { id: 'job', label: 'Job board / dealership', defaultKey: 'IK_Comma' },
          { id: 'emote', label: 'Emote wheel (hold)', defaultKey: 'IK_Period' },
          { id: 'connect', label: 'Connect / disconnect (hold)', defaultKey: 'IK_Slash' },
          { id: 'chatTop', label: 'Chat: scroll up', defaultKey: 'IK_PageUp' },
          { id: 'chatBottom', label: 'Chat: scroll down', defaultKey: 'IK_PageDown' }
        ],
        binds: { chat: 'IK_Semicolon', job: 'IK_F', emote: 'IK_Period', connect: 'IK_Slash', chatTop: 'IK_PageUp', chatBottom: 'IK_PageDown' }
      }),
      setKeybinds: (b) => ok(b),
      onProgress (cb) { progressCb = cb; return () => {} }
    }
  }, { s, info })
  await page.goto(base)
  await page.waitForTimeout(600)
  if (s.openKeys) {
    await page.click('text=Keys')
    await page.waitForTimeout(400)
  }
  if (s.busyPlay) {
    await page.click('button.enter')
    await page.waitForTimeout(300)
  }
  await page.screenshot({ path: path.join(out, `${name}.png`) })
  await page.close()
}
await browser.close()
server.close()
console.log('screenshots written to', out)
