// Talks to the account plugin on the game server
// (/api/v1/plugins/account, see AccountSystem/WebApi.cs).

import { createWriteStream } from 'fs'
import { Readable } from 'stream'
import { pipeline } from 'stream/promises'

export class ServerApi {
  constructor (serverUrl) {
    this.base = serverUrl.replace(/\/+$/, '') + '/api/v1/plugins/account'
  }

  async request (method, route, { token, body } = {}) {
    const headers = {}
    if (token) headers.Authorization = `Bearer ${token}`
    if (body !== undefined) headers['Content-Type'] = 'application/json'

    let response
    try {
      response = await fetch(this.base + route, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(30000)
      })
    } catch {
      throw new Error('Can\'t reach the server. Check your internet connection, or the server may be down.')
    }

    const text = await response.text()
    if (!response.ok) {
      const error = new Error(readError(text) || `Server error (${response.status}).`)
      error.status = response.status
      throw error
    }
    return text ? JSON.parse(text) : null
  }

  info () { return this.request('GET', '/info') }
  login (code) { return this.request('POST', '/login', { body: { code } }) }
  me (token) { return this.request('GET', '/me', { token }) }
  manifest () { return this.request('GET', '/modpack') }

  /** Streams one modpack file to disk. */
  async download (relPath, destFile) {
    const url = `${this.base}/modpack/file?path=${encodeURIComponent(relPath)}`
    const response = await fetch(url)
    if (!response.ok || !response.body) throw new Error(`Couldn't download ${relPath} (${response.status}).`)
    await pipeline(Readable.fromWeb(response.body), createWriteStream(destFile))
  }
}

// EmbedIO errors come back as JSON or HTML; pull out the human message.
function readError (text) {
  if (!text) return null
  try {
    const json = JSON.parse(text)
    return json.message || json.Message || json.error || null
  } catch {
    // EmbedIO's error page has "<strong>Message:</strong> ..."; its other <p>
    // is a generic "contact the administrator" note, so fall back to the title.
    const match = /<strong>Message:<\/strong>\s*([^<]+)/i.exec(text) || /<title>([^<]+)<\/title>/i.exec(text)
    return match ? decodeHtml(match[1].trim()) : text.slice(0, 200)
  }
}

function decodeHtml (text) {
  return text
    .replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
}
