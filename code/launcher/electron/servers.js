// The launcher's server list.
//
// Servers come from three places, merged in this order:
//   1. "servers" in launcher-config.json (built into the launcher),
//   2. "serverListUrl" in launcher-config.json: a small JSON file you host
//      anywhere (e.g. a GitHub file) listing servers, so the list can change
//      without rebuilding the launcher,
//   3. servers the player added by address.
// Each entry is { name, address } where address is "host:port", and host can be
// a domain name. Live details (players, description) come from each server.

import dns from 'dns/promises'
import net from 'net'

export const DEFAULT_PORT = 11778

/** "play.example.com", "1.2.3.4:11778", "http://x:1/" → { host, port, key } */
export function parseAddress (input) {
  let text = String(input || '').trim().replace(/^[a-z]+:\/\//i, '').replace(/\/.*$/, '')
  if (!text) throw new Error('Enter a server address.')

  let host = text
  let port = DEFAULT_PORT
  const bracketed = /^\[([^\]]+)\](?::(\d+))?$/.exec(text) // [ipv6]:port
  if (bracketed) {
    host = bracketed[1]
    if (bracketed[2]) port = Number(bracketed[2])
  } else if ((text.match(/:/g) || []).length === 1) {
    const [h, p] = text.split(':')
    host = h
    port = Number(p)
  }

  if (!host || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('That doesn\'t look like a server address. Use host or host:port.')
  }
  const key = `${host.toLowerCase()}:${port}`
  return { host, port, key }
}

/** Base URL of a server's web API. */
export function apiUrl ({ host, port }) {
  return net.isIPv6(host) ? `http://[${host}]:${port}` : `http://${host}:${port}`
}

/**
 * The game connects by IP address, so domain names are looked up first
 * (IPv4 preferred). Lets you give players a name like play.example.com that
 * keeps working if the VPS's IP changes.
 */
export async function resolveHost (host) {
  if (net.isIP(host)) return host
  try {
    const { address } = await dns.lookup(host, { family: 4 })
    return address
  } catch {
    const { address } = await dns.lookup(host)
    return address
  }
}

/** Merges the built-in list, the hosted list and the player's own servers (no duplicates). */
export async function loadServerList (launcherConfig, customServers, fetchImpl = fetch) {
  const entries = []
  const seen = new Set()
  const add = (entry, source) => {
    try {
      const parsed = parseAddress(entry.address)
      if (seen.has(parsed.key)) return
      seen.add(parsed.key)
      entries.push({ name: entry.name || parsed.host, address: parsed.key, source })
    } catch {
      // skip malformed entries
    }
  }

  for (const s of launcherConfig.servers || []) add(s, 'built-in')

  if (launcherConfig.serverListUrl) {
    try {
      const response = await fetchImpl(launcherConfig.serverListUrl, { signal: AbortSignal.timeout(10000) })
      if (response.ok) {
        const data = await response.json()
        for (const s of (Array.isArray(data) ? data : data.servers) || []) add(s, 'list')
      }
    } catch {
      // the hosted list is optional; built-in and custom servers still show
    }
  }

  for (const s of customServers || []) add(s, 'custom')
  return entries
}
