import { useCallback, useEffect, useState } from 'react'
import { Alert, Box, Button, CircularProgress, LinearProgress } from '@mui/material'
import { ink } from '../theme.ts'

interface SessionInfo {
  discordName: string
  characters: string[]
  maxCharacters: number
  expiresUtc: string
}

export interface ServerInfo {
  ServerName: string
  Description: string
  DiscordInvite: string
  PlayersOnline: number
  MaxPlayers: number
  Tags: string
  LoginRequired: boolean
  ModpackRequired: boolean
  ModpackFiles: number
  session: SessionInfo | null
}

interface Progress {
  step: string
  done?: number
  total?: number
  file?: string
  note?: string
}

interface Result<T> { ok: boolean, value?: T, error?: string }

const api = (): any => (window as any).mpAPI

async function call<T> (promise: Promise<Result<T>>): Promise<T> {
  const result = await promise
  if (!result.ok) throw new Error(result.error ?? 'Something went wrong.')
  return result.value as T
}

const STEP_TEXT: Record<string, string> = {
  'checking-server': 'Checking the server…',
  'setting-aside': 'Setting your other mods aside…',
  installing: 'Installing the server\'s mods…',
  checking: 'Checking your files…',
  ready: 'Mods ready.',
  playing: 'You\'re in the city. Have fun.',
  restoring: 'Putting your own mods back…',
  done: 'Your own mods are back. See you next time.'
}

function shortPath (p: string) {
  const parts = p.split(/[\\/]/)
  const game = parts.findIndex(x => x.toLowerCase() === 'cyberpunk 2077')
  return game >= 0 ? parts.slice(0, game + 1).join('\\') : p
}

function timeLeft (expiresUtc: string) {
  const ms = new Date(expiresUtc).getTime() - Date.now()
  if (!Number.isFinite(ms) || ms <= 0) return 'expired'
  const hours = Math.floor(ms / 3600000)
  const minutes = Math.floor((ms % 3600000) / 60000)
  return hours > 0 ? `${hours} h ${minutes} min` : `${minutes} min`
}

interface Props {
  address: string
  gamePath: string | null
  onSelectGame: () => void
  onBack: () => void
  canGoBack: boolean
}

export default function ServerPanel ({ address, gamePath, onSelectGame, onBack, canGoBack }: Props) {
  const [info, setInfo] = useState<ServerInfo | null>(null)
  const [session, setSession] = useState<SessionInfo | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [progress, setProgress] = useState<Progress | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const value = await call<ServerInfo>(api().info(address))
      setInfo(value)
      setSession(value.session)
    } catch (e: any) {
      setError(e.message)
    }
  }, [address])

  useEffect(() => {
    void load()
    return api().onProgress((update: Progress) => setProgress(update))
  }, [load])

  const run = async (label: string, action: () => Promise<void>) => {
    setBusy(label)
    setError(null)
    try {
      await action()
    } catch (e: any) {
      setError(e.message)
    } finally {
      setBusy(null)
    }
  }

  const login = async () => await run('login', async () => {
    setSession(await call<SessionInfo>(api().login(address)))
  })

  const logout = async () => await run('logout', async () => {
    await call(api().logout(address))
    setSession(null)
  })

  const play = async () => await run('play', async () => {
    setProgress(null)
    await call(api().play(address))
  })

  if (!info && !error) {
    return <Box sx={{ display: 'grid', placeItems: 'center', flex: 1 }}><CircularProgress/></Box>
  }

  const percent = progress?.total ? Math.round(((progress.done ?? 0) / progress.total) * 100) : undefined
  const tags = (info?.Tags ?? '').split(',').map(t => t.trim()).filter(Boolean)
  const playing = busy === 'play'

  return (
    <Box className="stage">
      {/* Left: the server, set like a sign over the skyline */}
      <Box className="stage-sign">
        {canGoBack && (
          <Button size="small" onClick={onBack} disabled={playing} sx={{ alignSelf: 'flex-start', mb: 2, color: 'text.secondary' }}>
            Other servers
          </Button>
        )}
        <Box component="h1" className="server-name">{info?.ServerName ?? 'Server'}</Box>
        {info && (
          <Box className="server-facts">
            <span className="live-dot" aria-hidden="true"/>
            {info.PlayersOnline}{info.MaxPlayers > 0 ? ` of ${info.MaxPlayers}` : ''} in the city now
          </Box>
        )}
        {info?.Description && <Box sx={{ mt: 2, maxWidth: 460, color: 'text.secondary', lineHeight: 1.5 }}>{info.Description}</Box>}
        {tags.length > 0 && (
          <Box sx={{ mt: 2, display: 'flex', gap: 1, flexWrap: 'wrap' }}>
            {tags.map(t => <span key={t} className="tag">{t}</span>)}
          </Box>
        )}
        {info?.DiscordInvite && (
          <Box component="a" href={info.DiscordInvite} target="_blank" rel="noreferrer" className="link" sx={{ mt: 3 }}>
            Join the server's Discord
          </Box>
        )}
      </Box>

      {/* Right: your entry permit and the way in */}
      <Box className="stage-permit">
        {error && (
          <Alert severity="error" sx={{ mb: 2 }} action={<Button color="inherit" size="small" onClick={() => { void load() }}>Try again</Button>}>
            {error}
          </Alert>
        )}

        <Box className={`permit${session ? ' issued' : ''}`}>
          <div className="holo" aria-hidden="true"/>
          <Box className="permit-head">
            <span>Entry permit</span>
            <span>{session ? `Valid ${timeLeft(session.expiresUtc)}` : 'Not issued'}</span>
          </Box>

          {session
            ? (
              <>
                <Box className="permit-name">{session.discordName}</Box>
                <Box className="permit-row">
                  <span>Characters</span>
                  <span>{session.characters.length > 0 ? session.characters.join(', ') : 'None yet'}</span>
                </Box>
                <Box className="permit-row">
                  <span>Slots</span>
                  <span>{session.characters.length} of {session.maxCharacters}</span>
                </Box>
              </>
              )
            : (
              <Box sx={{ py: 2, color: 'text.secondary', lineHeight: 1.5 }}>
                The city checks who you are with Discord. Your Discord name is all it sees.
              </Box>
              )}
        </Box>

        {!session && info && (
          <button className="enter" onClick={() => { void login() }} disabled={busy !== null}>
            {busy === 'login' ? 'Finish in your browser…' : 'Get a permit with Discord'}
          </button>
        )}

        {session && (
          <>
            <button className="enter" onClick={() => { void play() }} disabled={busy !== null || !gamePath}>
              {playing ? (progress?.step === 'playing' ? 'In the city' : 'Getting ready…') : 'Enter Night City'}
            </button>
            {session.characters.length === 0 && !playing && (
              <Box sx={{ mt: 1.5, fontSize: 14, color: 'text.secondary', lineHeight: 1.5 }}>
                First time in: start a New Game and name your character in the character creator.
              </Box>
            )}
          </>
        )}

        {progress && (
          <Box sx={{ mt: 2 }} aria-live="polite">
            <Box sx={{ fontSize: 14 }}>{STEP_TEXT[progress.step] ?? progress.step}</Box>
            {progress.note && <Box sx={{ fontSize: 13, color: 'text.secondary' }}>{progress.note}</Box>}
            {playing && progress.step !== 'playing' && (
              <LinearProgress variant={percent === undefined ? 'indeterminate' : 'determinate'} value={percent} sx={{ mt: 1, height: 3 }}/>
            )}
            {progress.file && progress.step !== 'playing' && (
              <Box sx={{ fontSize: 12, color: 'text.secondary', mt: 0.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {progress.file}
              </Box>
            )}
          </Box>
        )}

        <Box className="permit-foot">
          {gamePath
            ? <span title={gamePath}>Game: {shortPath(gamePath)}</span>
            : <span style={{ color: ink.sodium }}>Show the launcher where Cyberpunk 2077 is installed.</span>}
          <Button size="small" onClick={onSelectGame} disabled={playing}>{gamePath ? 'Change' : 'Find game'}</Button>
          {session && <Button size="small" onClick={() => { void logout() }} disabled={busy !== null}>Log out</Button>}
        </Box>

        {info?.ModpackRequired && session && !playing && (
          <Box sx={{ mt: 2, fontSize: 13, color: 'text.secondary', lineHeight: 1.5 }}>
            Entering installs the server's mods ({info.ModpackFiles} files) and sets your own aside.
            They're put back when the game closes.
          </Box>
        )}
      </Box>
    </Box>
  )
}

