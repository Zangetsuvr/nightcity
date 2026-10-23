import { useCallback, useEffect, useState } from 'react'
import { Alert, Box, Button, IconButton, TextField, Tooltip } from '@mui/material'
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline'
import RefreshIcon from '@mui/icons-material/Refresh'
import ServerPanel, { type ServerInfo } from './ServerPanel.tsx'
import { ink, signage } from '../theme.ts'

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

interface Props {
  gamePath: string | null
  onSelectGame: () => void
}

export default function ServerBrowser ({ gamePath, onSelectGame }: Props) {
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
    return (
      <ServerPanel key={selected} address={selected} gamePath={gamePath} onSelectGame={onSelectGame}
                   onBack={back} canGoBack={(servers?.length ?? 0) > 1 || servers?.some(s => s.source === 'custom') === true}/>
    )
  }

  return (
    <Box sx={{ px: 6, py: 5, maxWidth: 820, width: '100%' }}>
      <Box sx={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', mb: 3 }}>
        <Box component="h1" sx={{ fontFamily: signage, fontWeight: 800, fontSize: 64, lineHeight: 0.9, m: 0 }}>
          Pick a server
        </Box>
        <Tooltip title="Check again">
          <IconButton aria-label="Check servers again" onClick={() => { void loadList() }}><RefreshIcon/></IconButton>
        </Tooltip>
      </Box>

      {error && <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>{error}</Alert>}

      {servers?.length === 0 && (
        <Box sx={{ color: 'text.secondary', mb: 3 }}>No servers in your list yet. Add one by its address below.</Box>
      )}

      <Box component="ul" sx={{ listStyle: 'none', p: 0, m: 0, borderTop: `1px solid ${ink.rail}` }}>
        {servers?.map(server => {
          const s = status[server.address]
          const info = s?.info
          const offline = s !== undefined && !s.online
          return (
            <Box component="li" key={server.address} sx={{ display: 'flex', alignItems: 'center', borderBottom: `1px solid ${ink.rail}` }}>
              <Box component="button" className="server-row" onClick={() => open(server.address)} disabled={offline}>
                <Box sx={{ fontFamily: signage, fontWeight: 700, fontSize: 30, lineHeight: 1 }}>
                  {info?.ServerName ?? server.name}
                </Box>
                <Box sx={{ color: 'text.secondary', fontSize: 14, mt: 0.75 }}>
                  {s === undefined && 'Checking…'}
                  {offline && <Box component="span" sx={{ color: ink.danger }}>Not answering right now</Box>}
                  {s?.online && `${info?.PlayersOnline ?? 0}${info?.MaxPlayers ? ` of ${info.MaxPlayers}` : ''} in the city, ${s.ping ?? '?'} ms`}
                  {info?.Description ? `. ${info.Description}` : ''}
                </Box>
              </Box>
              {server.source === 'custom' && (
                <Tooltip title="Remove from your list">
                  <IconButton aria-label={`Remove ${server.name}`} onClick={() => { void removeServer(server.address) }} sx={{ mr: 1 }}>
                    <DeleteOutlineIcon/>
                  </IconButton>
                </Tooltip>
              )}
            </Box>
          )
        })}
      </Box>

      <Box sx={{ mt: 4, display: 'flex', gap: 1, alignItems: 'center', maxWidth: 520 }}>
        <TextField
          fullWidth
          label="Add a server by address"
          placeholder="play.example.com or 1.2.3.4:11778"
          value={address}
          onChange={e => setAddress(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter' && address.trim()) void addServer() }}
        />
        <Button variant="outlined" onClick={() => { void addServer() }} disabled={adding || !address.trim()} sx={{ height: 40 }}>
          {adding ? 'Checking…' : 'Add'}
        </Button>
      </Box>
    </Box>
  )
}
