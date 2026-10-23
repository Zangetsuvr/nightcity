import assert from 'assert'
import { discordLogin } from '../discord-login.js'
const info = { DiscordClientId: '123', DiscordRedirectUri: 'http://127.0.0.1:53134/callback', DiscordScopes: 'identify guilds' }
// Simulate Discord sending the browser back with a code
const code = await discordLogin(info, async (url) => {
  const u = new URL(url)
  assert.equal(u.searchParams.get('redirect_uri'), info.DiscordRedirectUri)
  assert.equal(u.searchParams.get('scope'), 'identify guilds')
  const r = await fetch(`${info.DiscordRedirectUri}?code=abc123&state=${u.searchParams.get('state')}`)
  assert((await r.text()).includes('Logged in'))
})
assert.equal(code, 'abc123')
// Wrong state is refused
await assert.rejects(discordLogin(info, async () => { await fetch(`${info.DiscordRedirectUri}?code=evil&state=nope`) }), /interrupted/)
// Cancelled at Discord
await assert.rejects(discordLogin(info, async (url) => {
  const s = new URL(url).searchParams.get('state'); await fetch(`${info.DiscordRedirectUri}?error=access_denied&state=${s}`)
}), /cancelled/)
console.log('discord login flow ok')
