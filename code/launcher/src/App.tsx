import { Alert, Box, CssBaseline, Snackbar, ThemeProvider } from '@mui/material'
import { useEffect, useState } from 'react'
import ServerBrowser from './components/ServerBrowser.tsx'
import WindowFrame from './components/WindowFrame.tsx'
import Skyline from './components/Skyline.tsx'
import UpdateBar from './components/UpdateBar.tsx'
import { theme } from './theme.ts'

interface Notice { severity: 'error' | 'warning' | 'success', text: string }

const KNOWN_PATHS = [
  'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\Cyberpunk2077.exe',
  'C:\\Program Files (x86)\\GOG Galaxy\\Games\\Cyberpunk 2077\\bin\\x64\\Cyberpunk2077.exe',
  'C:\\Program Files\\Epic Games\\Cyberpunk 2077\\bin\\x64\\Cyberpunk2077.exe'
]

const electronApi = (): any => (window as any).electronAPI

export default function App () {
  const [gamePath, setGamePath] = useState<string | null>(null)
  const [notice, setNotice] = useState<Notice | null>(null)

  const selectGame = async () => {
    try {
      const result = await electronApi().selectGameDialog()
      if (result.canceled) return
      const filePath: string = result.filePaths[0]
      if (!filePath.endsWith('Cyberpunk2077.exe')) {
        setNotice({ severity: 'error', text: 'Pick Cyberpunk2077.exe. It\'s in the game folder, under bin\\x64.' })
        return
      }
      electronApi().setGamePath(filePath)
      setGamePath(filePath)
      setNotice({ severity: 'success', text: 'Game found.' })
    } catch (err) {
      setNotice({ severity: 'error', text: `Couldn't open the file picker: ${String(err)}` })
    }
  }

  useEffect(() => {
    electronApi()?.getGamePath().then((saved?: string) => {
      if (saved && electronApi().pathExists(saved)) {
        setGamePath(saved)
        return
      }
      const found = KNOWN_PATHS.find(p => electronApi().pathExists(p))
      if (found) {
        electronApi().setGamePath(found)
        setGamePath(found)
      } else {
        setNotice({ severity: 'warning', text: 'Couldn\'t find Cyberpunk 2077 automatically. Show the launcher where it is.' })
      }
    })
  }, [])

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline/>
      <div className="sky" aria-hidden="true"/>
      <Skyline/>
      <div className="rain" aria-hidden="true"/>
      <WindowFrame/>

      <Box component="main" sx={{ position: 'relative', zIndex: 1, height: '100vh', overflowY: 'auto', pt: '36px', display: 'flex', flexDirection: 'column' }}>
        <UpdateBar/>
        <ServerBrowser gamePath={gamePath} onSelectGame={() => { void selectGame() }}/>
      </Box>

      <Snackbar open={notice !== null} onClose={() => setNotice(null)} autoHideDuration={5000}
                anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}>
        <Alert severity={notice?.severity ?? 'success'} variant="outlined" onClose={() => setNotice(null)}>
          {notice?.text}
        </Alert>
      </Snackbar>
    </ThemeProvider>
  )
}
