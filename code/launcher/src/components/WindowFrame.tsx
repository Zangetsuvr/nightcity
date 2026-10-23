import { Box, IconButton } from '@mui/material'
import CloseIcon from '@mui/icons-material/Close'
import MinimizeIcon from '@mui/icons-material/Minimize'
import CropSquareIcon from '@mui/icons-material/CropSquare'
import { ink, signage } from '../theme.ts'

const api = (): any => (window as any).electronAPI

// The window has no system frame; this strip is what you drag it by.
export default function WindowFrame () {
  return (
    <Box className="titlebar" sx={{
      position: 'fixed', top: 0, left: 0, right: 0, height: 36, zIndex: 10,
      display: 'flex', alignItems: 'center', pl: 2,
      borderBottom: `1px solid ${ink.rail}`, background: 'rgba(21, 19, 43, 0.7)', backdropFilter: 'blur(6px)'
    }}>
      <Box sx={{ fontFamily: signage, fontWeight: 700, fontSize: 15, letterSpacing: '0.04em', flex: 1, color: ink.bone }}>
        Night City Roleplay
      </Box>
      <Box className="no-drag" sx={{ display: 'flex' }}>
        <IconButton aria-label="Minimize" size="small" onClick={() => api()?.minimizeApp()} sx={{ borderRadius: 0, width: 44 }}>
          <MinimizeIcon fontSize="small"/>
        </IconButton>
        <IconButton aria-label="Maximize" size="small" onClick={() => api()?.maximizeApp()} sx={{ borderRadius: 0, width: 44 }}>
          <CropSquareIcon fontSize="small"/>
        </IconButton>
        <IconButton aria-label="Close" size="small" onClick={() => api()?.closeApp()}
                    sx={{ borderRadius: 0, width: 44, '&:hover': { background: ink.danger, color: '#fff' } }}>
          <CloseIcon fontSize="small"/>
        </IconButton>
      </Box>
    </Box>
  )
}
