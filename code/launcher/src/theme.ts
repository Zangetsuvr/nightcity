import { createTheme } from '@mui/material'

// Night City at 2 a.m.: smog lit from below by sodium street lamps, with the
// odd holographic ad. Orange does the work (actions, the horizon); rose and
// rainlight are kept for the permit's hologram and secondary text.
export const ink = {
  smog: '#15132B', // background sky
  overpass: '#24213F', // raised surfaces
  rail: '#3A3660', // borders, dividers
  sodium: '#FF9F43', // primary actions, horizon glow
  rose: '#F0549B', // hologram accent
  rainlight: '#9FD8E6', // links, secondary text on dark
  bone: '#EDE6D6', // body text
  danger: '#FF5A5F'
}

export const signage = '"Big Shoulders Display", "Barlow", sans-serif'
export const body = '"Barlow", "Segoe UI", sans-serif'

export const theme = createTheme({
  palette: {
    mode: 'dark',
    background: { default: ink.smog, paper: ink.overpass },
    primary: { main: ink.sodium, contrastText: '#1B1206' },
    secondary: { main: ink.rainlight },
    error: { main: ink.danger },
    text: { primary: ink.bone, secondary: '#B4AEC9' },
    divider: ink.rail
  },
  shape: { borderRadius: 2 },
  typography: {
    fontFamily: body,
    fontSize: 15,
    button: { textTransform: 'none', fontWeight: 600, letterSpacing: 0 }
  },
  components: {
    MuiButton: {
      styleOverrides: {
        root: { lineHeight: 'normal' }
      }
    },
    MuiTextField: {
      defaultProps: { size: 'small' }
    },
    MuiAlert: {
      styleOverrides: {
        root: { border: `1px solid ${ink.rail}`, backgroundColor: ink.overpass }
      }
    }
  }
})
