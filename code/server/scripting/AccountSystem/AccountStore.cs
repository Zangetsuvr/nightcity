using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.Sqlite;

namespace AccountSystem
{
    public record Account(
        string DiscordId,
        string DiscordName,
        bool Banned,
        string? BanReason,
        DateTime CreatedUtc,
        DateTime LastLoginUtc);

    public record SessionInfo(string DiscordId, DateTime ExpiresUtc);

    public enum ClaimResult { Claimed, AlreadyYours, Taken, TooMany }

    /// <summary>
    /// Accounts (one per Discord user), their characters (names), and launcher
    /// sessions, in one SQLite file. Session tokens are stored only as hashes,
    /// so a copy of the database can't be used to log in as anyone.
    /// </summary>
    public sealed class AccountStore : IDisposable
    {
        private readonly SqliteConnection _conn;
        private readonly object _lock = new();

        public AccountStore(string databaseFile)
        {
            var dir = Path.GetDirectoryName(Path.GetFullPath(databaseFile));
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);

            _conn = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = databaseFile,
                Mode = SqliteOpenMode.ReadWriteCreate,
            }.ToString());
            _conn.Open();

            Execute(@"
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = FULL;
                PRAGMA busy_timeout = 5000;

                CREATE TABLE IF NOT EXISTS accounts (
                    discord_id      TEXT PRIMARY KEY,
                    discord_name    TEXT NOT NULL,
                    banned          INTEGER NOT NULL DEFAULT 0,
                    ban_reason      TEXT,
                    created_at      TEXT NOT NULL,
                    last_login      TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash  TEXT PRIMARY KEY,
                    discord_id  TEXT NOT NULL REFERENCES accounts(discord_id),
                    created_at  TEXT NOT NULL,
                    expires_at  TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS sessions_discord ON sessions (discord_id);

                -- One row per character. Names are unique across the server, ignoring case.
                -- played_at stays empty until the character first joins the server;
                -- until then the name is only a reservation (see ClaimCharacter).
                CREATE TABLE IF NOT EXISTS characters (
                    name        TEXT PRIMARY KEY COLLATE NOCASE,
                    discord_id  TEXT NOT NULL REFERENCES accounts(discord_id),
                    created_at  TEXT NOT NULL,
                    played_at   TEXT
                );

                CREATE INDEX IF NOT EXISTS characters_discord ON characters (discord_id);");
        }

        // ---------------------------------------------------------------- accounts

        /// <summary>Creates the account on first login, or updates its Discord name.</summary>
        public Account Upsert(string discordId, string discordName)
        {
            var now = Stamp(DateTime.UtcNow);
            lock (_lock)
            {
                using var cmd = Command(@"
                    INSERT INTO accounts (discord_id, discord_name, created_at, last_login)
                    VALUES ($id, $name, $now, $now)
                    ON CONFLICT (discord_id) DO UPDATE SET discord_name = $name, last_login = $now");
                cmd.Parameters.AddWithValue("$id", discordId);
                cmd.Parameters.AddWithValue("$name", discordName);
                cmd.Parameters.AddWithValue("$now", now);
                cmd.ExecuteNonQuery();
                return Get(discordId)!;
            }
        }

        public Account? Get(string discordId)
        {
            lock (_lock)
            {
                using var cmd = Command("SELECT * FROM accounts WHERE discord_id = $id");
                cmd.Parameters.AddWithValue("$id", discordId);
                using var r = cmd.ExecuteReader();
                return r.Read() ? ReadAccount(r) : null;
            }
        }

        /// <summary>The account that owns a character name, or null if the name is free.</summary>
        public string? OwnerOf(string characterName)
        {
            lock (_lock)
            {
                using var cmd = Command("SELECT discord_id FROM characters WHERE name = $name");
                cmd.Parameters.AddWithValue("$name", characterName.Trim());
                return cmd.ExecuteScalar() as string;
            }
        }

        /// <summary>The account's character names, oldest first, with the exact spelling chosen.</summary>
        public List<string> CharactersOf(string discordId)
        {
            lock (_lock)
            {
                using var cmd = Command("SELECT name FROM characters WHERE discord_id = $id ORDER BY created_at, name");
                cmd.Parameters.AddWithValue("$id", discordId);
                using var r = cmd.ExecuteReader();
                var names = new List<string>();
                while (r.Read())
                    names.Add(r.GetString(0));
                return names;
            }
        }

        /// <summary>
        /// Gives a character name to an account, unless someone else has it or
        /// the account is full. The check and the insert happen under one lock,
        /// so two players can't both win the same name.
        ///
        /// A name reserved in the character creator but never played (the player
        /// went back, or abandoned that new game) doesn't block a new one: when
        /// the account is full, its oldest unplayed reservation is released to
        /// make room. Characters that have joined the server are never released.
        /// </summary>
        public ClaimResult ClaimCharacter(string discordId, string name, int maxPerAccount)
        {
            lock (_lock)
            {
                var owner = OwnerOf(name);
                if (owner == discordId)
                    return ClaimResult.AlreadyYours;
                if (owner != null)
                    return ClaimResult.Taken;

                if (CharactersOf(discordId).Count >= Math.Max(1, maxPerAccount))
                {
                    using var release = Command(@"
                        DELETE FROM characters WHERE name = (
                            SELECT name FROM characters
                            WHERE discord_id = $id AND played_at IS NULL
                            ORDER BY created_at LIMIT 1)");
                    release.Parameters.AddWithValue("$id", discordId);
                    if (release.ExecuteNonQuery() == 0)
                        return ClaimResult.TooMany;
                }

                try
                {
                    using var cmd = Command("INSERT INTO characters (name, discord_id, created_at) VALUES ($name, $id, $now)");
                    cmd.Parameters.AddWithValue("$name", name.Trim());
                    cmd.Parameters.AddWithValue("$id", discordId);
                    cmd.Parameters.AddWithValue("$now", Stamp(DateTime.UtcNow));
                    cmd.ExecuteNonQuery();
                    return ClaimResult.Claimed;
                }
                catch (SqliteException ex) when (ex.SqliteErrorCode == 19) // UNIQUE: taken a moment ago
                {
                    return ClaimResult.Taken;
                }
            }
        }

        /// <summary>How many of the account's characters have joined the server.</summary>
        public int PlayedCount(string discordId)
        {
            lock (_lock)
            {
                using var cmd = Command("SELECT COUNT(*) FROM characters WHERE discord_id = $id AND played_at IS NOT NULL");
                cmd.Parameters.AddWithValue("$id", discordId);
                return Convert.ToInt32(cmd.ExecuteScalar());
            }
        }

        /// <summary>Marks a character as played (its name can no longer be released).</summary>
        public void MarkPlayed(string characterName)
        {
            lock (_lock)
            {
                using var cmd = Command("UPDATE characters SET played_at = $now WHERE name = $name AND played_at IS NULL");
                cmd.Parameters.AddWithValue("$now", Stamp(DateTime.UtcNow));
                cmd.Parameters.AddWithValue("$name", characterName.Trim());
                cmd.ExecuteNonQuery();
            }
        }

        public List<Account> All()
        {
            lock (_lock)
            {
                using var cmd = Command("SELECT * FROM accounts ORDER BY created_at");
                using var r = cmd.ExecuteReader();
                var list = new List<Account>();
                while (r.Read())
                    list.Add(ReadAccount(r));
                return list;
            }
        }

        public bool SetBanned(string discordId, bool banned, string? reason)
        {
            lock (_lock)
            {
                using var cmd = Command("UPDATE accounts SET banned = $b, ban_reason = $r WHERE discord_id = $id");
                cmd.Parameters.AddWithValue("$b", banned ? 1 : 0);
                cmd.Parameters.AddWithValue("$r", banned ? (object?)reason ?? DBNull.Value : DBNull.Value);
                cmd.Parameters.AddWithValue("$id", discordId);
                var ok = cmd.ExecuteNonQuery() == 1;

                // A ban also ends every session, so the launcher can't keep using one.
                if (ok && banned)
                    RevokeSessions(discordId);
                return ok;
            }
        }

        // ---------------------------------------------------------------- sessions

        /// <summary>Starts a launcher session and returns its token (shown once, never stored).</summary>
        public string CreateSession(string discordId, TimeSpan lifetime, out DateTime expiresUtc)
        {
            var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                .TrimEnd('=').Replace('+', '-').Replace('/', '_');
            var now = DateTime.UtcNow;
            expiresUtc = now + lifetime;

            lock (_lock)
            {
                using (var clean = Command("DELETE FROM sessions WHERE expires_at < $now"))
                {
                    clean.Parameters.AddWithValue("$now", Stamp(now));
                    clean.ExecuteNonQuery();
                }

                using var cmd = Command(@"
                    INSERT INTO sessions (token_hash, discord_id, created_at, expires_at)
                    VALUES ($hash, $id, $now, $expires)");
                cmd.Parameters.AddWithValue("$hash", Hash(token));
                cmd.Parameters.AddWithValue("$id", discordId);
                cmd.Parameters.AddWithValue("$now", Stamp(now));
                cmd.Parameters.AddWithValue("$expires", Stamp(expiresUtc));
                cmd.ExecuteNonQuery();
            }
            return token;
        }

        /// <summary>The session behind a token, expired or not; null if unknown.</summary>
        public SessionInfo? FindSession(string token)
        {
            if (string.IsNullOrEmpty(token))
                return null;

            lock (_lock)
            {
                using var cmd = Command("SELECT discord_id, expires_at FROM sessions WHERE token_hash = $hash");
                cmd.Parameters.AddWithValue("$hash", Hash(token));
                using var r = cmd.ExecuteReader();
                if (!r.Read())
                    return null;
                return new SessionInfo(r.GetString(0), Parse(r.GetString(1)));
            }
        }

        public void RevokeSessions(string discordId)
        {
            lock (_lock)
            {
                using var cmd = Command("DELETE FROM sessions WHERE discord_id = $id");
                cmd.Parameters.AddWithValue("$id", discordId);
                cmd.ExecuteNonQuery();
            }
        }

        public void Dispose()
        {
            lock (_lock) { _conn.Dispose(); }
        }

        // ---------------------------------------------------------------- helpers

        private static string Hash(string token) =>
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();

        // Sortable UTC text, so "expires_at < now" works as plain text comparison.
        private static string Stamp(DateTime utc) => utc.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss");

        private static DateTime Parse(string stamp) =>
            DateTime.SpecifyKind(DateTime.ParseExact(stamp, "yyyy-MM-dd HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture), DateTimeKind.Utc);

        private static Account ReadAccount(SqliteDataReader r) => new(
            r.GetString(r.GetOrdinal("discord_id")),
            r.GetString(r.GetOrdinal("discord_name")),
            r.GetInt64(r.GetOrdinal("banned")) != 0,
            r.IsDBNull(r.GetOrdinal("ban_reason")) ? null : r.GetString(r.GetOrdinal("ban_reason")),
            Parse(r.GetString(r.GetOrdinal("created_at"))),
            Parse(r.GetString(r.GetOrdinal("last_login"))));

        private SqliteCommand Command(string sql)
        {
            var cmd = _conn.CreateCommand();
            cmd.CommandText = sql;
            return cmd;
        }

        private void Execute(string sql)
        {
            using var cmd = Command(sql);
            cmd.ExecuteNonQuery();
        }
    }
}
