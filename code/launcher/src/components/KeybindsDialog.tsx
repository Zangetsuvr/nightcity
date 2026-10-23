import { useEffect, useState } from 'react'
import { Box, Button, Dialog, DialogActions, DialogContent, DialogTitle } from '@mui/material'
import { ink } from '../theme.ts'

interface Action { id: string, label: string, defaultKey: string }
type Binds = Record<string, string>

const api = (): any => (window as any).mpAPI

// Browser key codes to the game's key names (EInputKey).
const NAMED: Record<string, string> = {
  Semicolon: 'IK_Semicolon',
  Comma: 'IK_Comma',
  Period: 'IK_Period',
  Slash: 'IK_Slash',
  Backslash: 'IK_Backslash',
  Quote: 'IK_SingleQuote',
  Backquote: 'IK_Tilde',
  BracketLeft: 'IK_LeftBracket',
  BracketRight: 'IK_RightBracket',
  Minus: 'IK_Minus',
  Equal: 'IK_Equals',
  PageUp: 'IK_PageUp',
  PageDown: 'IK_PageDown',
  Home: 'IK_Home',
  End: 'IK_End',
  Insert: 'IK_Insert',
  Delete: 'IK_Delete',
  Tab: 'IK_Tab',
  Backspace: 'IK_Backspace',
  ArrowUp: 'IK_Up',
  ArrowDown: 'IK_Down',
  ArrowLeft: 'IK_Left',
  ArrowRight: 'IK_Right',
  NumpadAdd: 'IK_Add',
  NumpadSubtract: 'IK_Subtract',
  NumpadMultiply: 'IK_Multiply',
  NumpadDivide: 'IK_Divide',
  NumpadDecimal: 'IK_Decimal'
}

function toGameKey (e: KeyboardEvent): string | null {
  const code = e.code
  if (/^Key[A-Z]$/.test(code)) return 'IK_' + code.slice(3)
  if (/^Digit[0-9]$/.test(code)) return 'IK_' + code.slice(5)
  if (/^F([1-9]|1[0-2])$/.test(code)) return 'IK_' + code
  if (/^Numpad[0-9]$/.test(code)) return 'IK_NumPad' + code.slice(6)
  return NAMED[code] ?? null
}

function mouseToGameKey (button: number): string | null {
  if (button === 1) return 'IK_MiddleMouse'
  if (button === 3) return 'IK_ThumbMouseButton'
  if (button === 4) return 'IK_ThumbMouseButton2'
  return null
}

// How a key name reads to a person.
export function keyLabel (key: string): string {
  const name = key.replace(/^IK_/, '')
  const pretty: Record<string, string> = {
    Semicolon: ';', Comma: ',', Period: '.', Slash: '/', Backslash: '\\', SingleQuote: "'", Tilde: '`',
    LeftBracket: '[', RightBracket: ']', Minus: '-', Equals: '=', PageUp: 'Page Up', PageDown: 'Page Down',
    MiddleMouse: 'Middle mouse', ThumbMouseButton: 'Mouse 4', ThumbMouseButton2: 'Mouse 5'
  }
  return pretty[name] ?? name.replace(/^NumPad/, 'Numpad ')
}

// Keys the game itself uses a lot; taking one means the game's action is lost.
const GAME_KEYS = new Set(['IK_W', 'IK_A', 'IK_S', 'IK_D', 'IK_F', 'IK_R', 'IK_Q', 'IK_E', 'IK_C', 'IK_V', 'IK_X', 'IK_Z', 'IK_T', 'IK_I', 'IK_M', 'IK_J', 'IK_P', 'IK_H', 'IK_Tab', 'IK_1', 'IK_2', 'IK_3', 'IK_4'])

export default function KeybindsDialog ({ open, onClose }: { open: boolean, onClose: () => void }) {
  const [actions, setActions] = useState<Action[]>([])
  const [binds, setBinds] = useState<Binds>({})
  const [listening, setListening] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    if (!open) return
    setSaved(false)
    api().keybinds().then((r: any) => {
      if (r.ok) {
        setActions(r.value.actions)
        setBinds(r.value.binds)
      }
    })
  }, [open])

  useEffect(() => {
    if (listening === null) return
    const take = (key: string | null) => {
      if (key !== null) setBinds(b => ({ ...b, [listening]: key }))
      setListening(null)
    }
    const onKey = (e: KeyboardEvent) => {
      e.preventDefault()
      e.stopPropagation()
      if (e.code === 'Escape') { setListening(null); return }
      take(toGameKey(e))
    }
    const onMouse = (e: MouseEvent) => {
      const key = mouseToGameKey(e.button)
      if (key !== null) { e.preventDefault(); take(key) }
    }
    window.addEventListener('keydown', onKey, true)
    window.addEventListener('mousedown', onMouse, true)
    return () => {
      window.removeEventListener('keydown', onKey, true)
      window.removeEventListener('mousedown', onMouse, true)
    }
  }, [listening])

  const save = async () => {
    const r = await api().setKeybinds(binds)
    if (r.ok) {
      setBinds(r.value)
      setSaved(true)
    }
  }

  const reset = () => {
    const out: Binds = {}
    for (const a of actions) out[a.id] = a.defaultKey
    setBinds(out)
  }

  const used = (id: string, key: string) => actions.some(a => a.id !== id && binds[a.id] === key)

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Multiplayer keys</DialogTitle>
      <DialogContent>
        <Box sx={{ color: 'text.secondary', fontSize: 14, mb: 2, lineHeight: 1.5 }}>
          Keys for the server's own features. They take effect the next time you enter the city.
          The game's own keys are changed in the game's settings as usual.
        </Box>
        {actions.map(a => {
          const key = binds[a.id] ?? a.defaultKey
          const clash = used(a.id, key)
          const gameKey = GAME_KEYS.has(key)
          return (
            <Box key={a.id} sx={{ display: 'flex', alignItems: 'center', gap: 2, py: 1, borderBottom: `1px solid ${ink.rail}` }}>
              <Box sx={{ flex: 1 }}>
                {a.label}
                {(clash || gameKey) && (
                  <Box sx={{ fontSize: 12, color: ink.sodium }}>
                    {clash ? 'Same key as another action.' : 'The game also uses this key.'}
                  </Box>
                )}
              </Box>
              <Button variant={listening === a.id ? 'contained' : 'outlined'} onClick={() => setListening(a.id)} sx={{ minWidth: 150 }}>
                {listening === a.id ? 'Press a key…' : keyLabel(key)}
              </Button>
            </Box>
          )
        })}
      </DialogContent>
      <DialogActions>
        {saved && <Box sx={{ mr: 'auto', ml: 2, fontSize: 14, color: 'text.secondary' }}>Saved.</Box>}
        <Button onClick={reset}>Defaults</Button>
        <Button onClick={onClose}>Close</Button>
        <Button variant="contained" onClick={() => { void save() }}>Save</Button>
      </DialogActions>
    </Dialog>
  )
}
