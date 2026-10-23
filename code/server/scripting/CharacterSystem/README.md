# CharacterSystem

Saved characters and a server-owned wallet for CyberpunkMP.

## What it does

- **Saves each character** (money, Street Cred XP, XP per job, current job, play time) in one
  SQLite database file on your VPS: `data/characters.db` in the server folder. See [Storage](#storage).
- **Owns all money.** Payouts, fares and purchases happen on the server. The player's game
  only shows the balance it's sent, and the server re-sends it every 10 seconds, so money a
  game adds on its own disappears.
- **Logs every money change** (who, how much, why, balance after) to the `ledger` table in the
  same database.
- **Street Cred levels.** Any XP also counts toward Street Cred. Level L needs
  `50 * L * (L - 1)` XP (level 2 at 100, 10 at 4,500, 50 at 122,500).
- **Gives other plugins one place for money and XP** through `CyberpunkSdk.GameServices`:

  ```csharp
  GameServices.Economy?.Credit(playerId, 250, "Bounty: Maelstrom ganger");
  GameServices.Economy?.Debit(playerId, 1200, "Bought: Mantis Blades");
  GameServices.Economy?.Transfer(fromId, toId, 50, "Taxi fare");
  GameServices.Progression?.AddXp(playerId, "Fixer", 40, "Gig complete");
  ```

  `Debit` and `Transfer` refuse (and change nothing) if the payer can't afford it.

## Cheat protection

The server owns every balance, so money a cheat mod or console command adds inside someone's
game isn't real: it can't be spent through the server, transferred or saved, and it's wiped at
the next sync (every 10 seconds). On top of that:

- **Tamper reports.** Each sync, the game checks whether its eddies changed since the server's
  last update. If they did, it tells the server, which corrects them right away and flags the
  player when the jump is at least `TamperFlagThreshold` (5,000 by default). Smaller jumps are
  usually loot or vendor sales and are corrected without a flag. A cheater who also disables
  this report still can't keep or transfer the money; they just don't get flagged.
- **In-game spending is charged.** When the game's eddies go *down* on their own (buying from
  an in-game vendor), the server charges the same amount so the purchase isn't refunded at the
  next sync.
- **Earnings watch.** Flags anyone who earns more than `EarningsAlertPerHour` through server
  payouts in an hour, and refuses payouts past `EarningsLimitPerHour`. This catches abuse of
  real server systems, like exploiting a job loop.
- **Frozen wallets.** An admin can freeze a character's money (no earning, spending or
  transfers) while looking into it. `FreezeOnEarningsLimit` does this automatically.
- **Rate limits** on requests from the game, so nobody can flood the server.
- Every flag goes to `data/flags.jsonl` and the server log, and shows in the admin API.

## Changes to existing code

- **JobSystem:** Delivery and Taxi pay through the server wallet, give XP, and the taxi fare
  now really moves from rider to driver. Your job is saved and given back about 5 seconds
  after you rejoin. Leaving mid-job puts the delivery or fare back on the board.
- **Client scripts:** `Delivery.reds` and `Taxi.reds` no longer add or remove eddies
  themselves. `NetworkWorldSystem.reds` asks for your balance when you connect.
  `Plugins/Character.reds` is new and applies the balance the server sends.

## Storage

Everything lives in one SQLite file on the VPS, `data/characters.db` next to the server.
There's no separate database program to install or run.

- Every change is written to the file before it counts, so a crash loses nothing and a failed
  write changes nothing.
- Transfers update both players in one transaction: both change or neither does.
- The database itself refuses any balance below zero.
- The file has two tables: `characters` (one row per character) and `ledger` (every money change).

**Viewing it:** open `characters.db` with any SQLite tool, e.g. DB Browser for SQLite, or
`sqlite3 data/characters.db` on the VPS:

```sql
SELECT display_name, balance FROM characters ORDER BY balance DESC LIMIT 20;
SELECT * FROM ledger WHERE character = 'somename' ORDER BY time DESC LIMIT 50;
```

Avoid editing balances in a SQL tool while the server is running; the server keeps online
characters in memory and would overwrite the change. Use the admin API instead.

**Backups:** copy `characters.db` (plus the `-wal` and `-shm` files next to it if they exist)
somewhere safe, ideally on a schedule. While the server is running, the safest way is
`sqlite3 data/characters.db ".backup backup.db"`.

## Settings

`config/character.json` is created on first start:

| Setting | Default | Meaning |
|---|---|---|
| StartingBalance | 1000 | Money for a brand-new character |
| MaxBalance | 1,000,000,000 | Highest balance allowed |
| MaxTransaction | 10,000,000 | Largest single payment |
| DatabaseFile | data/characters.db | The SQLite database file (any path on the VPS) |
| ResyncIntervalSeconds | 10 | How often balances are re-sent to games |
| MaxLevel | 50 | Highest Street Cred level |
| DataPath | data | Where the flags log goes |
| TamperFlagThreshold | 5,000 | Flag when a game shows this many unexplained extra eddies |
| EarningsAlertPerHour | 50,000 | Flag anyone earning more than this per hour (0 = off) |
| EarningsLimitPerHour | 250,000 | Refuse payouts past this per hour (0 = off) |
| FreezeOnEarningsLimit | false | Also freeze the wallet when the hard limit is hit |
| AdminKey | (empty) | Secret for the admin API's changes and flags; empty = off |
| Start | X -1720.4, Y -1956.6, Z 62.4, Yaw 0 | Where brand-new characters are moved the first time they connect (out of the clean start's holding room). `null` = leave them where the game put them |

## Admin API

Served by the server's web API under `/api/v1/plugins/character`:

- `GET /` — every character
- `GET /{name}` — one character
- `POST /{name}/balance` with header `X-Admin-Key: <AdminKey>` and body
  `{"amount": 500, "reason": "event prize"}`. Negative amounts remove money.
- `POST /{name}/freeze` and `POST /{name}/unfreeze` with `{"reason": "..."}` (needs the key)
- `GET /security/flags` — recent suspicious events, newest first (needs the key)

## Known limits (fix before a public launch)

- **Logins aren't verified.** CyberpunkMP sends a fixed token and the server doesn't check it,
  so anyone can join with someone else's name and use their character. Accounts need a real
  login (e.g. Discord) before going public.
- **Vendors and loot are local.** Money from selling to vendors or looting bodies is undone at
  the next sync. Worse, a cheater can add fake eddies and spend them at a vendor before the sync
  catches it, or block the spending report, and keep the item. Money stays safe, but items
  bought this way don't. Before launch, in-game vendors should be turned off or replaced with
  server-run shops.
- **Inventory items aren't saved or checked yet** — only money, XP and job. A player can still
  spawn weapons or gear in their own game. The server only sees equipment as appearance data
  inside the C++ layer, so checking gear needs that exposed to plugins first.
- **No kick or ban yet.** Plugins can't disconnect players, so the strongest action is freezing
  the wallet.
- **Flags are a separate log** (`data/flags.jsonl`), not in the database yet.
