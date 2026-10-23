// The multiplayer mod's own keys (chat, emotes, job board...), which players
// can change in the launcher.
//
// They live in the modpack's input file. That file is part of the modpack, so
// it's checked against the server's copy; the launcher therefore puts the
// player's keys into it only after that check, just before starting the game.
// The next launch restores the server's copy and applies them again.

import path from 'path'
import { promises as fs } from 'fs'

export const INPUT_FILE = 'red4ext/plugins/zzzCyberpunkMP/assets/Inputs/CyberpunkMP.xml'

// Each action can drive more than one mapping in the file (connect and
// disconnect share a key; so do the job board and cancelling a job).
export const ACTIONS = [
  { id: 'chat', label: 'Open chat', mappings: ['UIEnterChatMessage_Button'], key: 'IK_Semicolon' },
  { id: 'job', label: 'Job board / dealership', mappings: ['UIJob_Button', 'UIShop_Button'], key: 'IK_Comma' },
  { id: 'emote', label: 'Emote wheel (hold)', mappings: ['UIEmote_Button'], key: 'IK_Period' },
  { id: 'connect', label: 'Connect / disconnect (hold)', mappings: ['UIConnectToServer_Button', 'UIDisconnectFromServer_Button'], key: 'IK_Slash' },
  { id: 'chatTop', label: 'Chat: scroll up', mappings: ['ChatTop_Button'], key: 'IK_PageUp' },
  { id: 'chatBottom', label: 'Chat: scroll down', mappings: ['ChatBottom_Button'], key: 'IK_PageDown' }
]

const KEY = /^IK_[A-Za-z0-9]+$/

/** The player's keys: { actionId: 'IK_...' }, defaults filled in. */
export function readBinds (store) {
  const saved = store.get('mp_keybinds') || {}
  const out = {}
  for (const action of ACTIONS) {
    out[action.id] = KEY.test(saved[action.id] || '') ? saved[action.id] : action.key
  }
  return out
}

export function saveBinds (store, binds) {
  const clean = {}
  for (const action of ACTIONS) {
    const key = binds?.[action.id]
    if (KEY.test(key || '') && key !== action.key) clean[action.id] = key
  }
  store.set('mp_keybinds', clean)
  return readBinds(store)
}

/** Writes the keys into the installed input file. Missing file: nothing to do. */
export async function applyBinds (gameRoot, binds) {
  const file = path.join(gameRoot, ...INPUT_FILE.split('/'))
  let xml
  try {
    xml = await fs.readFile(file, 'utf8')
  } catch {
    return false
  }
  for (const action of ACTIONS) {
    const key = binds[action.id]
    if (!KEY.test(key || '')) continue
    for (const mapping of action.mappings) {
      const block = new RegExp(`(<mapping\\s+name="${mapping}"[^>]*>[\\s\\S]*?<button\\s+id=")[^"]*(")`)
      xml = xml.replace(block, `$1${key}$2`)
    }
  }
  await fs.writeFile(file, xml, 'utf8')
  return true
}
