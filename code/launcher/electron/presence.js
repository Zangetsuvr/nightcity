// Discord Rich Presence: shows on the player's Discord profile what they're
// doing, e.g. "Roleplaying on Night City Roleplay · as Jackie Welles · 12 of 40".
//
// It talks to the Discord app running on the player's PC. If Discord isn't
// running, or the package isn't installed, it quietly does nothing.
//
// Each server's own Discord application (the same one used for login) is used,
// so the status shows that application's name and the image uploaded under
// Rich Presence → Art Assets in the Discord Developer Portal.

let client = null
let clientId = null
let connecting = null
let lastActivity = null

async function connect (id) {
  if (client && clientId === id) return client
  if (connecting && clientId === id) return connecting

  await disconnect()
  clientId = id
  connecting = (async () => {
    let Client
    try {
      ({ Client } = await import('@xhayper/discord-rpc'))
    } catch {
      return null // package not installed
    }
    const c = new Client({ clientId: id })
    c.on('disconnected', () => { if (client === c) client = null })
    try {
      await c.login()
      client = c
      return c
    } catch {
      return null // Discord isn't running
    } finally {
      connecting = null
    }
  })()
  return connecting
}

export async function disconnect () {
  const c = client
  client = null
  clientId = null
  lastActivity = null
  if (c) {
    try { await c.destroy() } catch {}
  }
}

/**
 * Updates the status. `presence`:
 *   { clientId, details, state, imageKey, imageText, startTimestamp, partySize, partyMax, buttons }
 * Pass null to clear it.
 */
export async function setPresence (presence) {
  if (!presence || !presence.clientId) {
    if (client) {
      try { await client.user?.clearActivity() } catch {}
    }
    lastActivity = null
    return
  }

  const c = await connect(presence.clientId)
  if (!c?.user) return

  const activity = {
    details: presence.details,
    state: presence.state,
    startTimestamp: presence.startTimestamp,
    largeImageKey: presence.imageKey || undefined,
    largeImageText: presence.imageText || undefined,
    instance: false
  }
  if (presence.partySize && presence.partyMax) {
    activity.partySize = presence.partySize
    activity.partyMax = presence.partyMax
  }
  if (presence.buttons?.length) activity.buttons = presence.buttons.slice(0, 2)

  const key = JSON.stringify(activity)
  if (key === lastActivity) return
  lastActivity = key

  try {
    await c.user.setActivity(activity)
  } catch {
    lastActivity = null
  }
}
