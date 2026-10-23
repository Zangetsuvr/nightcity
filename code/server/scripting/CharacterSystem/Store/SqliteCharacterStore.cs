using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace CharacterSystem.Store
{
    /// <summary>
    /// Characters and the money log in one SQLite database file on the server
    /// (data/characters.db by default). No separate database program is needed,
    /// and the file can be opened with any SQLite tool (e.g. DB Browser for SQLite).
    ///
    /// - Every change is written to the file before it counts, so a crash loses
    ///   nothing and a failed write changes nothing.
    /// - Transfers update both characters in one transaction.
    /// - The database refuses any balance below zero.
    ///
    /// Tables are created automatically on first start.
    /// </summary>
    public sealed class SqliteCharacterStore : ICharacterStore, IDisposable
    {
        private static readonly JsonSerializerOptions JsonOptions = new();

        private readonly SqliteConnection _conn;
        private readonly Action<string> _logError;

        // One connection, used under this lock: game ticks and the admin web API
        // run on different threads.
        private readonly object _lock = new();
        private readonly Dictionary<string, CharacterRecord> _loaded = new();

        public SqliteCharacterStore(string databaseFile, Action<string> logError)
        {
            _logError = logError;

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
                PRAGMA journal_mode = WAL;     -- safe against crashes, readers don't block writes
                PRAGMA synchronous = FULL;     -- every committed change is on disk
                PRAGMA busy_timeout = 5000;    -- wait if a SQL tool has the file open

                CREATE TABLE IF NOT EXISTS characters (
                    key            TEXT    PRIMARY KEY,
                    display_name   TEXT    NOT NULL,
                    balance        INTEGER NOT NULL CHECK (balance >= 0),
                    data           TEXT    NOT NULL,
                    created_at     TEXT    NOT NULL DEFAULT (datetime('now')),
                    updated_at     TEXT    NOT NULL DEFAULT (datetime('now'))
                );

                CREATE TABLE IF NOT EXISTS ledger (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    time           TEXT    NOT NULL,
                    character      TEXT    NOT NULL,
                    amount         INTEGER NOT NULL,
                    balance_after  INTEGER NOT NULL,
                    reason         TEXT    NOT NULL,
                    counterparty   TEXT
                );

                CREATE INDEX IF NOT EXISTS ledger_character_time ON ledger (character, time);");
        }

        // ---------------------------------------------------------------- loading

        public CharacterRecord LoadOrCreate(string username, long startingBalance, out bool created)
        {
            var key = CharacterKeys.Normalize(username);
            lock (_lock)
            {
                created = false;
                if (_loaded.TryGetValue(key, out var cached))
                    return cached;

                var record = ReadRecord(key);
                if (record != null)
                {
                    record.Key = key;
                    record.DisplayName = username;
                    record.LastSeenUtc = DateTime.UtcNow;
                    Save(null, record);
                }
                else
                {
                    var now = DateTime.UtcNow;
                    record = new CharacterRecord
                    {
                        Key = key,
                        DisplayName = username,
                        Balance = startingBalance,
                        FirstSeenUtc = now,
                        LastSeenUtc = now,
                    };

                    using var insert = Command(null, @"
                        INSERT INTO characters (key, display_name, balance, data)
                        VALUES ($key, $name, $balance, $data)");
                    AddRecordParams(insert, record);
                    insert.ExecuteNonQuery();
                    created = true;
                }

                _loaded[key] = record;
                return record;
            }
        }

        /// <summary>Drops a character from memory. Its changes are already saved.</summary>
        public void Unload(string key)
        {
            lock (_lock) { _loaded.Remove(key); }
        }

        /// <summary>Nothing to do: every change is saved as it happens.</summary>
        public void Flush()
        {
        }

        // ---------------------------------------------------------------- changes

        public bool Modify(string key, Func<CharacterRecord, bool> change)
        {
            lock (_lock)
            {
                if (!_loaded.TryGetValue(key, out var current))
                    return false;

                // Change a copy; only keep it if the database accepted it.
                var next = Clone(current);
                if (!change(next))
                    return false;

                try
                {
                    Save(null, next);
                }
                catch (Exception ex)
                {
                    _logError($"Saving character '{key}' failed, change not applied: {ex.Message}");
                    return false;
                }

                _loaded[key] = next;
                return true;
            }
        }

        public bool ModifyPair(string keyA, string keyB, Func<CharacterRecord, CharacterRecord, bool> change)
        {
            if (keyA == keyB)
                return false;

            lock (_lock)
            {
                if (!_loaded.TryGetValue(keyA, out var currentA) || !_loaded.TryGetValue(keyB, out var currentB))
                    return false;

                var a = Clone(currentA);
                var b = Clone(currentB);
                if (!change(a, b))
                    return false;

                try
                {
                    using var tx = _conn.BeginTransaction();
                    Save(tx, a);
                    Save(tx, b);
                    tx.Commit();
                }
                catch (Exception ex)
                {
                    _logError($"Transfer between '{keyA}' and '{keyB}' failed, nothing changed: {ex.Message}");
                    return false;
                }

                _loaded[keyA] = a;
                _loaded[keyB] = b;
                return true;
            }
        }

        public T? Read<T>(string key, Func<CharacterRecord, T> read)
        {
            lock (_lock)
            {
                return _loaded.TryGetValue(key, out var record) ? read(record) : default;
            }
        }

        public bool ModifyOffline(string username, Func<CharacterRecord, bool> change)
        {
            var key = CharacterKeys.Normalize(username);
            lock (_lock)
            {
                if (_loaded.ContainsKey(key))
                    return Modify(key, change);

                try
                {
                    var record = ReadRecord(key);
                    if (record == null || !change(record))
                        return false;

                    Save(null, record);
                    return true;
                }
                catch (Exception ex)
                {
                    _logError($"Changing offline character '{key}' failed: {ex.Message}");
                    return false;
                }
            }
        }

        // ---------------------------------------------------------------- reading

        public CharacterRecord? Snapshot(string username)
        {
            var key = CharacterKeys.Normalize(username);
            lock (_lock)
            {
                return _loaded.TryGetValue(key, out var record) ? Clone(record) : ReadRecord(key);
            }
        }

        public List<CharacterRecord> ListAll()
        {
            var result = new List<CharacterRecord>();
            lock (_lock)
            {
                using var cmd = Command(null, "SELECT data FROM characters ORDER BY key LIMIT 5000");
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                {
                    var record = JsonSerializer.Deserialize<CharacterRecord>(reader.GetString(0), JsonOptions);
                    if (record != null)
                        result.Add(record);
                }
            }
            return result;
        }

        public void AppendLedger(LedgerEntry entry)
        {
            try
            {
                lock (_lock)
                {
                    using var cmd = Command(null, @"
                        INSERT INTO ledger (time, character, amount, balance_after, reason, counterparty)
                        VALUES ($time, $character, $amount, $after, $reason, $counterparty)");
                    cmd.Parameters.AddWithValue("$time", entry.TimeUtc.ToString("yyyy-MM-dd HH:mm:ss.fff"));
                    cmd.Parameters.AddWithValue("$character", entry.Character);
                    cmd.Parameters.AddWithValue("$amount", entry.Amount);
                    cmd.Parameters.AddWithValue("$after", entry.BalanceAfter);
                    cmd.Parameters.AddWithValue("$reason", entry.Reason);
                    cmd.Parameters.AddWithValue("$counterparty", (object?)entry.Counterparty ?? DBNull.Value);
                    cmd.ExecuteNonQuery();
                }
            }
            catch (Exception ex)
            {
                _logError($"Failed to write money log: {ex.Message}");
            }
        }

        public void Dispose()
        {
            lock (_lock)
            {
                _conn.Dispose();
            }
        }

        // ---------------------------------------------------------------- helpers

        private SqliteCommand Command(SqliteTransaction? tx, string sql)
        {
            var cmd = _conn.CreateCommand();
            cmd.CommandText = sql;
            cmd.Transaction = tx;
            return cmd;
        }

        private void Execute(string sql)
        {
            using var cmd = Command(null, sql);
            cmd.ExecuteNonQuery();
        }

        private CharacterRecord? ReadRecord(string key)
        {
            using var cmd = Command(null, "SELECT data FROM characters WHERE key = $key");
            cmd.Parameters.AddWithValue("$key", key);
            var json = cmd.ExecuteScalar() as string;
            return json == null ? null : JsonSerializer.Deserialize<CharacterRecord>(json, JsonOptions);
        }

        private void Save(SqliteTransaction? tx, CharacterRecord record)
        {
            using var cmd = Command(tx, @"
                UPDATE characters SET data = $data, balance = $balance, display_name = $name, updated_at = datetime('now')
                WHERE key = $key");
            AddRecordParams(cmd, record);
            if (cmd.ExecuteNonQuery() != 1)
                throw new InvalidOperationException($"Character '{record.Key}' is missing from the database.");
        }

        private static void AddRecordParams(SqliteCommand cmd, CharacterRecord record)
        {
            cmd.Parameters.AddWithValue("$key", record.Key);
            cmd.Parameters.AddWithValue("$name", record.DisplayName);
            cmd.Parameters.AddWithValue("$balance", record.Balance);
            cmd.Parameters.AddWithValue("$data", JsonSerializer.Serialize(record, JsonOptions));
        }

        private static CharacterRecord Clone(CharacterRecord r) =>
            JsonSerializer.Deserialize<CharacterRecord>(JsonSerializer.Serialize(r, JsonOptions), JsonOptions)!;
    }
}
