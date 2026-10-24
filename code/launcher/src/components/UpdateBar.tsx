import { useEffect, useState } from 'react'
import { Box, Button } from '@mui/material'
import { ink } from '../theme.ts'

interface UpdateState { step: 'idle' | 'downloading' | 'ready', version?: string, percent?: number }

const api = (): any => (window as any).mpAPI

// A thin bar under the title bar while a launcher update downloads, and a
// "Restart to update" button once it's ready (see electron/updater.js).
export default function UpdateBar () {
  const [state, setState] = useState<UpdateState>({ step: 'idle' })
  const [playing, setPlaying] = useState(false)

  useEffect(() => {
    if (!api()?.onUpdate) return
    api().updateState().then((s: UpdateState) => setState(s)).catch(() => {})
    return api().onUpdate((s: UpdateState) => setState(s))
  }, [])

  useEffect(() => {
    if (state.step !== 'ready') return
    const check = () => { api().isPlaying().then((r: any) => setPlaying(r?.ok ? r.value : Boolean(r))).catch(() => {}) }
    check()
    const timer = setInterval(check, 5000)
    return () => clearInterval(timer)
  }, [state.step])

  if (state.step === 'idle') return null

  return (
    <Box sx={{
      position: 'relative', zIndex: 2, display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap',
      px: 3, py: 0.75, fontSize: 14, borderBottom: `1px solid ${ink.rail}`,
      background: 'rgba(20, 18, 32, 0.85)'
    }} aria-live="polite">
      {state.step === 'downloading'
        ? <Box sx={{ color: 'text.secondary' }}>Downloading launcher update{state.version ? ` ${state.version}` : ''}… {state.percent ?? 0}%</Box>
        : (
          <>
            <Box>Launcher {state.version} is ready.</Box>
            <Button size="small" variant="contained" disabled={playing} onClick={() => { void api().installUpdate() }}>
              Restart to update
            </Button>
            {playing && <Box sx={{ color: 'text.secondary', fontSize: 13 }}>After you close the game. It also installs when you close the launcher.</Box>}
          </>
          )}
    </Box>
  )
}
