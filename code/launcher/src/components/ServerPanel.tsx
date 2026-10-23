import { useCallback, useEffect, useState } from 'react'
import {
  Alert, Box, Button, Card, CardContent, Chip, CircularProgress, LinearProgress, Stack, Typography
} from '@mui/material'

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
  installing: 'Installing the server modpack…',
  checking: 'Checking your files…',
  ready: 'Mods ready.',
  playing: 'Game running. Have fun in Night City.',
  restoring: 'Putting your own mods back…',
  done: 'Your own mods are back. See you next time.'
}

export default function ServerPanel ({ address, gameReady, onBack }: { address: string, gameReady: boolean, onBack: () => void }) {
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
    return <Box sx={{ display: 'grid', placeItems: 'center', height: 300 }}><CircularProgress/></Box>
  }

  const percent = progress?.total ? Math.round(((progress.done ?? 0) / progress.total) * 100) : undefined

  return (
    <Stack spacing={2} sx={{ maxWidth: 560, mx: 'auto', mt: 4 }}>
      <Box>
        <Button size="small" onClick={onBack} disabled={busy === 'play'}>← All servers</Button>
      </Box>
      <Typography variant="h4" fontWeight={700}>{info?.ServerName ?? 'Server'}</Typography>
      {info?.Description && <Typography color="text.secondary">{info.Description}</Typography>}
      {info && (
        <Typography variant="body2" color="text.secondary">
          {info.PlayersOnline}{info.MaxPlayers > 0 ? ` / ${info.MaxPlayers}` : ''} players online
          {info.DiscordInvite && (
            <> · <a href={info.DiscordInvite} target="_blank" rel="noreferrer" style={{ color: 'inherit' }}>Join the Discord</a></>
          )}
        </Typography>
      )}

      {error && (
        <Alert severity="error" action={<Button color="inherit" size="small" onClick={load}>Retry</Button>}>
          {error}
        </Alert>
      )}

      {info && !session && (
        <Card variant="outlined">
          <CardContent>
            <Typography gutterBottom>Log in with Discord to join.</Typography>
            <Button variant="contained" onClick={login} disabled={busy !== null}>
              {busy === 'login' ? 'Waiting for Discord in your browser…' : 'Log in with Discord'}
            </Button>
          </CardContent>
        </Card>
      )}

      {session && (
        <Card variant="outlined">
          <CardContent>
            <Typography variant="body2" color="text.secondary" gutterBottom>
              Logged in as {session.discordName} on Discord
            </Typography>

            {session.characters.length > 0
              ? (
                <Stack direction="row" spacing={1} sx={{ flexWrap: 'wrap', my: 1 }}>
                  {session.characters.map(c => <Chip key={c} label={c}/>)}
                </Stack>
                )
              : (
                <Typography sx={{ my: 1 }}>
                  No characters yet. Press Play, start a <b>New Game</b>, and name your character in the
                  character creator.
                </Typography>
                )}

            {session.characters.length > 0 && (
              <Typography variant="body2" color="text.secondary">
                Load that character's save to play them
                {session.characters.length < session.maxCharacters
                  ? ', or start a New Game to create another.'
                  : '.'}
              </Typography>
            )}

            <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
              <Button
                variant="contained"
                size="large"
                onClick={play}
                disabled={busy !== null || !gameReady}
              >
                {busy === 'play' ? 'Playing…' : 'Play'}
              </Button>
              <Button onClick={logout} disabled={busy !== null}>Log out</Button>
            </Stack>

            {!gameReady && (
              <Typography variant="body2" color="warning.main" sx={{ mt: 1 }}>
                Select your Cyberpunk2077.exe first.
              </Typography>
            )}

            {info?.ModpackRequired && (
              <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>
                Play installs the server's modpack ({info.ModpackFiles} files) and sets your other mods
                aside while you play. They're put back when the game closes.
              </Typography>
            )}
          </CardContent>
        </Card>
      )}

      {progress && (
        <Box>
          <Typography variant="body2">{STEP_TEXT[progress.step] ?? progress.step}</Typography>
          {progress.note && <Typography variant="body2" color="text.secondary">{progress.note}</Typography>}
          {(busy === 'play' && progress.step !== 'playing') && (
            <LinearProgress variant={percent === undefined ? 'indeterminate' : 'determinate'} value={percent} sx={{ mt: 1 }}/>
          )}
          {progress.file && progress.step !== 'playing' && (
            <Typography variant="caption" color="text.secondary" noWrap display="block">{progress.file}</Typography>
          )}
        </Box>
      )}
    </Stack>
  )
}
