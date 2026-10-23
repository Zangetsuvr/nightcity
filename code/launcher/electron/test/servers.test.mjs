// Tests for the server list helpers and Discord status (without Discord running).
import assert from 'assert'
import { parseAddress, apiUrl, resolveHost, loadServerList } from '../servers.js'
import { setPresence, disconnect } from '../presence.js'

// ---- addresses
assert.deepEqual(parseAddress('play.example.com'), { host: 'play.example.com', port: 11778, key: 'play.example.com:11778' })
assert.deepEqual(parseAddress('PLAY.Example.com:1234'), { host: 'PLAY.Example.com', port: 1234, key: 'play.example.com:1234' })
assert.deepEqual(parseAddress('http://1.2.3.4:11778/api'), { host: '1.2.3.4', port: 11778, key: '1.2.3.4:11778' })
assert.equal(parseAddress('[2001:db8::1]:5000').port, 5000)
assert.equal(apiUrl(parseAddress('[2001:db8::1]:5000')), 'http://[2001:db8::1]:5000')
assert.equal(apiUrl(parseAddress('1.2.3.4')), 'http://1.2.3.4:11778')
assert.throws(() => parseAddress(''), /Enter a server address/)
assert.throws(() => parseAddress('host:99999'), /doesn't look like/)
assert.throws(() => parseAddress('host:abc'), /doesn't look like/)
console.log('addresses ok')

// ---- IPs pass through; names resolve
assert.equal(await resolveHost('203.0.113.7'), '203.0.113.7')
assert.match(await resolveHost('localhost'), /^(127\.0\.0\.1|::1)$/)
console.log('host resolution ok')

// ---- list merge: built-in, hosted list, custom; duplicates and junk dropped
const hosted = { servers: [{ name: 'Loot', address: 'loot.example.com' }, { name: 'Dup', address: 'PLAY.example.com:11778' }, { address: '' }] }
const fakeFetch = async () => ({ ok: true, json: async () => hosted })
const list = await loadServerList(
  { servers: [{ name: 'RP', address: 'play.example.com' }], serverListUrl: 'https://x/servers.json' },
  [{ name: 'Mine', address: '10.0.0.5:2000' }, { name: 'Again', address: 'loot.example.com:11778' }],
  fakeFetch)
assert.deepEqual(list.map(s => [s.name, s.address, s.source]), [
  ['RP', 'play.example.com:11778', 'built-in'],
  ['Loot', 'loot.example.com:11778', 'list'],
  ['Mine', '10.0.0.5:2000', 'custom']
])
// The hosted list being down doesn't break the launcher
const offline = await loadServerList({ servers: [{ name: 'RP', address: 'play.example.com' }], serverListUrl: 'https://x' }, [], async () => { throw new Error('down') })
assert.equal(offline.length, 1)
console.log('server list ok')

// ---- Discord status never throws without Discord / the package
await setPresence({ clientId: '123', details: 'x', state: 'y' })
await setPresence(null)
await disconnect()
console.log('discord status ok (no-op without Discord)')
