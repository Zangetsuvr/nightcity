// Keeps the launcher itself up to date.
//
// New versions are published as GitHub releases of this repo by the launcher
// build (CI, when the version in electron/package.json goes up). On start and
// every 30 minutes the launcher checks for a newer one and downloads it in the
// background. When it's ready the window shows "Restart to update"; if the
// player doesn't, it installs the next time the launcher closes. Never while
// the game is running from it (the launcher has to put the player's own mods
// back afterwards).

import updaterPackage from 'electron-updater'

const { autoUpdater } = updaterPackage

export function startAutoUpdate ({ electron, getWindow, isPlaying, isDev }) {
  let state = { step: 'idle' }
  const send = (next) => {
    state = next
    getWindow()?.webContents.send('update:state', state)
  }

  electron.ipcMain.handle('update:get', () => state)
  electron.ipcMain.handle('update:install', () => {
    if (state.step !== 'ready' || isPlaying()) return false
    // Quietly, and open the new version straight after.
    setImmediate(() => autoUpdater.quitAndInstall(true, true))
    return true
  })

  if (isDev) return

  autoUpdater.autoDownload = true
  autoUpdater.autoInstallOnAppQuit = true

  autoUpdater.on('update-available', (info) => send({ step: 'downloading', version: info.version, percent: 0 }))
  autoUpdater.on('download-progress', (p) => send({ ...state, step: 'downloading', percent: Math.round(p.percent ?? 0) }))
  autoUpdater.on('update-downloaded', (info) => send({ step: 'ready', version: info.version }))
  autoUpdater.on('update-not-available', () => { if (state.step !== 'ready') send({ step: 'idle' }) })
  // A failed check isn't worth bothering the player about; the next one may work.
  autoUpdater.on('error', () => { if (state.step !== 'ready') send({ step: 'idle' }) })

  const check = () => { if (state.step !== 'ready') autoUpdater.checkForUpdates().catch(() => {}) }
  setTimeout(check, 5000)
  setInterval(check, 30 * 60 * 1000)
}
