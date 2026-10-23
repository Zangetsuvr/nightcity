import { useCallback, useEffect, useState } from 'react'
import {
  Alert, Box, Button, Card, CardActionArea, CardContent, Chip, IconButton, Stack, TextField, Tooltip, Typography
} from '@mui/material'
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline'
import RefreshIcon from '@mui/icons-material/Refresh'
import ServerPanel, { type ServerInfo } from './ServerPanel.tsx'

interface ServerEntry {
  name: string
  address: string
  source: 'built-in' | 'list' | 'custom'
}

interface ServerStatus {
  online: boolean
  ping?: number
  info?: ServerInfo
}

interface Result<T> { ok: boolean, value?: T, error?: string }

const api = (): any => (window as any).mpAPI

async function call<T> (promise: Promise<Result<T>>): Promise<T> {
  const result = await promise
  if (!result.ok) throw new Error(result.error ?? 'Something went wrong.')
  return result.value as T
}

const LAST_SERVER = 'mp:last-server'

function readLastServer (): string | null {
  try { return window.localStorage.getItem(LAST_SERVER) } catch { return null }
}

function writeLastServer (address: string | null) {
  try {
    if (address) window.localStorage.setItem(LAST_SERVER, address)
    else window.localStorage.removeItem(LAST_SERVER)
  } catch {}
}

export default function ServerBrowser ({ gameReady }: { gameReady: boolean }) {
  const [servers, setServers] = useState<ServerEntry[] | null>(null)
  const [status, setStatus] = useState<Record<string, ServerStatus>>({})
  const [selected, setSelected] = useState<string | null>(null)
  const [address, setAddress] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)

  const refreshStatus = useCallback(async (list: ServerEntry[]) => {
    const results = await Promise.all(list.map(async s => [s.address, await call<ServerStatus>(api().status(s.address))] as const))
    setStatus(Object.fromEntries(results))
  }, [])

  const loadList = useCallback(async () => {
    try {
      const list = await call<ServerEntry[]>(api().list())
      setServers(list)
      void refreshStatus(list)
      return list
    } catch (e: any) {
      setError(e.message)
      return []
    }
  }, [refreshStatus])

  useEffect(() => {
    void loadList().then(list => {
      // Go straight to the last server played, or the only one there is.
      const last = readLastServer()
      if (last && list.some(s => s.address === last)) setSelected(last)
      else if (list.length === 1) setSelected(list[0].address)
    })
  }, [loadList])

  useEffect(() => {
    if (!servers || selected) return
    const timer = setInterval(() => { void refreshStatus(servers) }, 15000)
    return () => clearInterval(timer)
  }, [servers, selected, refreshStatus])

  const open = (addr: string) => {
    writeLastServer(addr)
    setSelected(addr)
  }

  const back = () => {
    writeLastServer(null)
    setSelected(null)
    if (servers) void refreshStatus(servers)
  }

  const addServer = async () => {
    setAdding(true)
    setError(null)
    try {
      const added = await call<{ address: string }>(api().addServer(address))
      setAddress('')
      await loadList()
      open(added.address)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setAdding(false)
    }
  }

  const removeServer = async (addr: string) => {
    await call(api().removeServer(addr)).catch(() => {})
    await loadList()
  }

  if (selected) {
    return <ServerPanel key={selected} address={selected} gameReady={gameReady} onBack={back}/>
  }

  return (
    <Stack spacing={2} sx={{ maxWidth: 720, mx: 'auto', mt: 4 }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between">
        <Typography variant="h4" fontWeight={700}>Servers</Typography>
        <Tooltip title="Refresh">
          <IconButton onClick={() => { void loadList() }}><RefreshIcon/></IconButton>
        </Tooltip>
      </Stack>

      {error && <Alert severity="error" onClose={() => setError(null)}>{error}</Alert>}

      {servers?.length === 0 && (
        <Typography color="text.secondary">No servers yet. Add one by its address below.</Typography>
      )}

      {servers?.map(server => {
        const s = status[server.address]
        const info = s?.info
        return (
          <Card key={server.address} variant="outlined">
            <Stack direction="row" alignItems="stretch">
              <CardActionArea onClick={() => open(server.address)} disabled={s !== undefined && !s.online}>
                <CardContent>
                  <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 0.5 }}>
                    <Typography variant="h6">{info?.ServerName ?? server.name}</Typography>
                    {s === undefined && <Chip size="small" label="Checking…"/>}
                    {s?.online === false && <Chip size="small" color="error" label="Offline"/>}
                    {s?.online && (
                      <Chip size="small" color="success"
                            label={`${info?.PlayersOnline ?? 0}${info?.MaxPlayers ? ` / ${info.MaxPlayers}` : ''} online`}/>
                    )}
                    {s?.ping !== undefined && <Chip size="small" variant="outlined" label={`${s.ping} ms`}/>}
                  </Stack>
                  {info?.Description && <Typography variant="body2" color="text.secondary">{info.Description}</Typography>}
                  {info?.Tags && (
                    <Stack direction="row" spacing={0.5} sx={{ mt: 1, flexWrap: 'wrap' }}>
                      {info.Tags.split(',').map(t => t.trim()).filter(Boolean).map(t => <Chip key={t} size="small" variant="outlined" label={t}/>)}
                    </Stack>
                  )}
                </CardContent>
              </CardActionArea>
              {server.source === 'custom' && (
                <Box sx={{ display: 'flex', alignItems: 'center', pr: 1 }}>
                  <Tooltip title="Remove from your list">
                    <IconButton onClick={() => { void removeServer(server.address) }}><DeleteOutlineIcon/></IconButton>
                  </Tooltip>
                </Box>
              )}
            </Stack>
          </Card>
        )
      })}

      <Card variant="outlined">
        <CardContent>
          <Typography gutterBottom>Add a server</Typography>
          <Stack direction="row" spacing={1} alignItems="center">
            <TextField
              size="small"
              label="Server address"
              placeholder="play.example.com or 1.2.3.4:11778"
              value={address}
              onChange={e => setAddress(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter' && address.trim()) void addServer() }}
              sx={{ m: 0 }}
            />
            <Button variant="contained" onClick={() => { void addServer() }} disabled={adding || !address.trim()}>
              {adding ? 'Checking…' : 'Add'}
            </Button>
          </Stack>
        </CardContent>
      </Card>
    </Stack>
  )
}
