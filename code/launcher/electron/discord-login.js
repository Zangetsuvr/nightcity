// Discord login. Opens Discord's login page in the player's browser and waits
// for Discord to send them back to a tiny local web page this launcher serves
// (the redirect address set on the server and in the Discord Developer
// Portal). That gives a one-time code, which the game server swaps for the
// player's identity using its secret. The launcher never sees the secret.

import http from 'http'
import { randomBytes } from 'crypto'

const PAGE = (title, text) => `<!doctype html><meta charset="utf-8"><title>${title}</title>
<body style="font-family:system-ui;background:#111;color:#eee;display:grid;place-items:center;height:100vh;margin:0">
<div style="text-align:center"><h2>${title}</h2><p>${text}</p></div></body>`

/**
 * Resolves with the Discord login code.
 * info: { DiscordClientId, DiscordRedirectUri, DiscordScopes } from the server.
 * openBrowser: (url) => void
 */
export function discordLogin (info, openBrowser, timeoutMs = 5 * 60 * 1000) {
  const redirect = new URL(info.DiscordRedirectUri)
  if (redirect.hostname !== '127.0.0.1' && redirect.hostname !== 'localhost') {
    return Promise.reject(new Error('The server\'s Discord redirect must be a 127.0.0.1 address.'))
  }

  const state = randomBytes(16).toString('hex')
  const authorize = new URL('https://discord.com/oauth2/authorize')
  authorize.searchParams.set('client_id', info.DiscordClientId)
  authorize.searchParams.set('redirect_uri', info.DiscordRedirectUri)
  authorize.searchParams.set('response_type', 'code')
  authorize.searchParams.set('scope', info.DiscordScopes)
  authorize.searchParams.set('state', state)
  authorize.searchParams.set('prompt', 'none')

  return new Promise((resolve, reject) => {
    let finished = false
    const finish = (err, code) => {
      if (finished) return
      finished = true
      clearTimeout(timer)
      server.close()
      err ? reject(err) : resolve(code)
    }

    const server = http.createServer((req, res) => {
      const url = new URL(req.url, `http://${req.headers.host}`)
      if (url.pathname !== redirect.pathname) {
        res.writeHead(404).end()
        return
      }

      const error = url.searchParams.get('error')
      const code = url.searchParams.get('code')
      // "Connection: close" so the browser doesn't keep the socket open and
      // stop this little server from shutting down.
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', Connection: 'close' })

      if (url.searchParams.get('state') !== state) {
        res.end(PAGE('Login failed', 'This login link is out of date. Go back to the launcher and try again.'))
        return finish(new Error('Login was interrupted. Please try again.'))
      }
      if (error || !code) {
        res.end(PAGE('Login cancelled', 'You can close this tab and go back to the launcher.'))
        return finish(new Error('Discord login was cancelled.'))
      }

      res.end(PAGE('Logged in', 'You can close this tab and go back to the launcher.'))
      finish(null, code)
    })

    server.on('error', (e) => finish(new Error(
      e.code === 'EADDRINUSE'
        ? `Another program is using port ${redirect.port}. Close other launchers and try again.`
        : `Couldn't start the login: ${e.message}`)))

    const timer = setTimeout(() => finish(new Error('Login timed out. Please try again.')), timeoutMs)

    server.listen(Number(redirect.port) || 80, redirect.hostname, () => openBrowser(authorize.toString()))
  })
}
