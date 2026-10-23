# AccountSystem

Discord login, character names, and exact-modpack enforcement for your server.

Players join through the **server launcher** (`code/launcher`). The launcher:

1. logs them in with Discord,
2. installs the server's modpack and sets every other mod aside,
3. starts the game pointed at your server,
4. puts the player's own mods back when the game closes.

Characters are named **in the game**: starting a New Game adds a "Character name" box to the top
of the character creator's appearance screen (see [Character names](#character-names)).

When connecting, the game sends the save's character name plus a login token and a fingerprint of
its mods. The server refuses the connection, with a message in the in-game chat, if:

- there's no login or it has expired (12 hours by default),
- the save has no character name, the name belongs to someone else, or breaks the naming rules,
- the account already has its maximum number of characters,
- the account is banned,
- the mods don't **exactly** match the modpack: missing, extra, or a different version,
- that character is already connected.

## Setup

### 1. Discord application

1. Go to <https://discord.com/developers/applications> → **New Application**.
2. **OAuth2** → copy the **Client ID** and **Client Secret**.
3. **OAuth2 → Redirects** → add exactly `http://127.0.0.1:53134/callback`.

### 2. Server config

On first start the server creates `config/account.json`. Fill in:

```json
"ServerName": "Night City Roleplay",
"DiscordClientId": "<client id>",
"DiscordClientSecret": "<client secret>",
"RequiredGuildId": "<your Discord server id, or empty>",
"AdminKey": "<a long random secret>"
```

`RequiredGuildId` makes only members of your Discord server able to log in. That's the easiest
whitelist: kick someone from Discord and they can't log in again.

Restart the server after editing.

### 3. Modpack

Put every mod file players must have in `data/modpack/`, laid out exactly like the game folder:

```
data/modpack/
  bin/x64/winmm.dll                                   (RED4ext loader)
  bin/x64/plugins/cyber_engine_tweaks/...             (Cyber Engine Tweaks)
  red4ext/RED4ext.dll
  red4ext/plugins/zzzCyberpunkMP/...                     (the multiplayer mod itself)
  red4ext/plugins/ArchiveXL/..., TweakXL/..., Codeware/...
  r6/scripts/... , r6/tweaks/...                      (redscript and its scripts)
  archive/pc/mod/...                                  (your custom guns, cars, clothes)
```

The easiest way: set up one clean game install with exactly your mods, check it works, then copy
those folders from it. After changing the modpack, restart the server or call
`POST /modpack/reload`. Players get the update the next time they press Play; the launcher only
downloads files that changed.

**What counts as a mod:** everything under `archive/pc/mod`, `bin/x64/plugins`, `red4ext`,
`r6/scripts`, `r6/tweaks`, `r6/config/redsUserHints` and `mods`, plus the loader files
`bin/x64/version.dll`, `winmm.dll`, `d3d11.dll`, `dxgi.dll`, `dinput8.dll` and `global.ini`, and the
files redscript and Input Loader put outside those folders (`engine/tools/scc.exe`,
`engine/tools/scc_lib.dll`, `engine/config/base/scripts.ini`, `r6/config/cybercmd/scc.toml`,
`engine/config/platform/pc/input_loader.ini`, `r6/cache/inputContexts.xml`,
`r6/cache/inputUserMappings.xml`). Those last ones are added to older `account.json` files
automatically. **Ignored:** log files, CET settings
files, mod databases (`*.sqlite3`), and CyberpunkMP's `session.json` and `Rpc` folder, which
mods create while running. Both lists are in `config/account.json` (`ModRoots`, `ModFiles`,
`Ignore`). Keep `Ignore` short, since anything ignored could hide a mod.

### 4. Launcher

Players pick your server from the launcher's **server list**, so nobody has to type an address.
Edit `code/launcher/electron/launcher-config.json` before building:

```json
{
  "servers": [
    { "name": "Night City Roleplay", "address": "play.yourdomain.com:11778" }
  ],
  "serverListUrl": "",
  "sessionFile": "red4ext/plugins/zzzCyberpunkMP/session.json"
}
```

- **`servers`** are built into the launcher. Use a domain name if you have one: the launcher
  looks up its IP when starting the game, so moving to a new VPS only means updating the
  domain, not rebuilding the launcher. A plain IP works too.
- **`serverListUrl`** (optional) points to a JSON file you host anywhere, such as a file in a
  GitHub repository, with the same shape: `{"servers": [{"name": "...", "address": "..."}]}`.
  The launcher reads it every time it opens, so you can add servers later (like the loot
  server) without sending players a new launcher.
- Players can also **add a server by address**; the launcher only accepts addresses where a
  server like this one answers.
- Each server card shows live details from that server: name, description, players online
  (out of `MaxPlayer` in the server's `server.json`), tags, ping and Discord invite.
- `sessionFile` must point inside the CyberpunkMP plugin folder from your modpack.

The address isn't secret: a player's PC has to connect to it, so anyone determined can find it.
The list just means players never need to be told it.

### 5. Discord status (Rich Presence)

While someone plays, their Discord profile shows e.g. *Roleplaying on Night City Roleplay ·
as Jackie Welles · 12 of 40*, with your logo and a "Join the Discord" button. It uses the same
Discord application as the login. To finish it:

1. In the Discord Developer Portal, open your application → **Rich Presence → Art Assets** and
   upload your logo with the name `logo` (or set `DiscordImageKey` to the name you used).
2. Set `DiscordInvite` in `config/account.json` to a permanent invite link
   (`https://discord.gg/...`) for the button.
3. The Discord app's name is what shows as the game title, so name the application after the
   server.

It works only while the Discord desktop app is running on the player's PC; otherwise nothing
happens.

## Settings (`config/account.json`)

| Setting | Default | Meaning |
|---|---|---|
| RequireLogin | true | Refuse anyone who didn't log in through the launcher. Turn off only for local testing |
| EnforceModpack | true | Refuse anyone whose mods don't exactly match |
| ServerName | Night City Roleplay | Shown in the launcher and Discord status |
| Description | (empty) | Shown under the name in the launcher's server list |
| DiscordInvite | (empty) | Invite link shown in the launcher and as a button on Discord status |
| DiscordImageKey | logo | Art asset name for Discord status |
| DiscordClientId / DiscordClientSecret | (empty) | From the Discord Developer Portal |
| DiscordRedirectUri | http://127.0.0.1:53134/callback | Must match the Developer Portal |
| RequiredGuildId | (empty) | Only members of this Discord server may log in |
| MaxCharactersPerAccount | 1 | How many characters one Discord account may have |
| SessionHours | 12 | How long a login lasts |
| DatabaseFile | data/accounts.db | Accounts, names, sessions (SQLite) |
| ModpackFolder | data/modpack | The modpack |
| ModRoots / ModFiles / Ignore | see above | What counts as a mod |
| AdminKey | (empty) | Secret for admin endpoints; empty = off |

## Admin API

Under `/api/v1/plugins/account`, with header `X-Admin-Key: <AdminKey>`:

- `GET /accounts` — everyone who has logged in, with Discord ID and character name
- `POST /accounts/{discordId}/ban` with `{"reason": "..."}` — also ends their login
- `POST /accounts/{discordId}/unban`
- `POST /modpack/reload` — re-read `data/modpack` after changing it

## Character names

- **Where:** a "Character name" box at the top of the appearance screen in the character creator.
  It only appears for a New Game started from the launcher; plain single player is unchanged.
- **While typing:** after a short pause the game asks the server whether the name is free and
  shows *Available*, *Taken*, or what's wrong with it.
- **On Confirm:** the name is reserved for the player's Discord account in `data/accounts.db`
  before the creator continues. If it was taken in the meantime, the player is told and stays
  on the screen.
- **In the save:** the name is stored in that game's save. Each save is its own character, and
  loading a save plays that character. `MaxCharactersPerAccount` limits how many characters one
  account can have (1 by default).
- **Changing your mind:** a name only becomes permanent once that character first joins the
  server. Until then it's just a reservation: if the player goes back and picks another name, or
  abandons that new game, their oldest unplayed reservation is released to make room. One
  connection per Discord account at a time, whichever character it plays.
- **Rules:** 3–24 characters: letters, spaces, apostrophes, hyphens and periods, starting with a
  letter. Unique across the server, ignoring case.

Staff can look names up with `GET /accounts`, or in the `characters` table of `data/accounts.db`.
Renaming a character means changing it there **and** in `data/characters.db` (money and progress
are stored under the name), with the server stopped.

## Limits

- **A modified client can lie.** The fingerprint comes from the player's PC. Someone who edits
  the launcher or the multiplayer mod can send the "right" fingerprint with different mods. This
  stops honest mismatches and ordinary cheat mods, not a determined cheater, which is why money
  stays server-owned.
- **Mods can change after Play.** Cyber Engine Tweaks can reload Lua mods while the game runs, so
  a file dropped in mid-game isn't caught until the next login.
- **Plain HTTP.** The login token travels unencrypted between the launcher and the server. Put
  the web API behind HTTPS (e.g. Caddy as a reverse proxy) before going public.
- One server only. Characters and accounts live in SQLite files on this server.

## Checking the fingerprint rule

The launcher (`code/launcher/electron/modpack.js`) and this plugin (`Modpack.cs`) must compute the
same fingerprint. Test vector: these five files and hashes

```
archive/pc/mod/nightcity_guns.archive                          30cf1c20022cf1959929016d444bf9ff202382c26b01631ec8783c9034bcde98
bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.asi    014b813850156c80c54c8b76e3f616b39bf159542e35e63b96a98c2087901269
bin/x64/winmm.dll                                              d47712cceb4c780603026e6325221c1bcff90679ebc076baa51c71ebe796717c
red4ext/plugins/zzzCyberpunkMP/CyberpunkMP.dll                    424927bca55fb638adcf96af37a089a50c187e376d38fbaca030345d032f067b
red4ext/RED4ext.dll                                            efe73a3dbe582a99ef4780855e80ac82591a69d39853c16fde173443186ef9a0
```

must give `7e60086039a5c99ec33a550666a1b302973f876568ac46b0fdd21d2e2c12e030`.
