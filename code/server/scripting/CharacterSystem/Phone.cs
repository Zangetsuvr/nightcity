using CharacterSystem.Store;
using CyberpunkSdk;
using CyberpunkSdk.Systems;
using Microsoft.Data.Sqlite;

namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class PhoneServer
    {
        public static partial void OpenPhone_Impl(ulong playerId) => CharacterSystem.Plugin.Instance.Phone.Open(playerId);
        public static partial void ShareContact_Impl(ulong playerId, string character) => CharacterSystem.Plugin.Instance.Phone.Share(playerId, character);
        public static partial void AnswerRequest_Impl(ulong playerId, string character, bool accept) => CharacterSystem.Plugin.Instance.Phone.Answer(playerId, character, accept);
        public static partial void SendText_Impl(ulong playerId, string character, string message) => CharacterSystem.Plugin.Instance.Phone.Text(playerId, character, message);
        public static partial void PingLocation_Impl(ulong playerId, string character) => CharacterSystem.Plugin.Instance.Phone.Ping(playerId, character);
        public static partial void RemoveContact_Impl(ulong playerId, string character) => CharacterSystem.Plugin.Instance.Phone.Remove(playerId, character);
        public static partial void SetBlocked_Impl(ulong playerId, string character, bool blocked) => CharacterSystem.Plugin.Instance.Phone.SetBlocked(playerId, character, blocked);
    }
}

namespace CharacterSystem
{
    /// <summary>
    /// The players' phone: contacts you swap in person, texts (kept for when the
    /// other person is offline), location pings, and blocking. Stored in the
    /// same database file as characters (tables phone_*).
    ///
    /// Sharing a number: both players stand near each other; one picks the other
    /// under NEARBY and shares, the other accepts under REQUESTS. Then each is in
    /// the other's contacts. Removing or blocking takes it off both phones.
    /// </summary>
    internal sealed class Phone : IDisposable
    {
        public const float NearbyMeters = 15f;
        public const int MaxText = 240;
        public const int ThreadLength = 8;

        private readonly ICharacterStore _characters;
        private readonly SqliteConnection _conn;
        private readonly object _lock = new();
        private readonly Logger _logger = new("Phone");

        // Pending "share contact" requests: (from key, to key) -> when. Not saved.
        private readonly Dictionary<(string From, string To), DateTime> _requests = new();
        private readonly Dictionary<(ulong, string), DateTime> _throttle = new();

        public Phone(string databaseFile, ICharacterStore characters)
        {
            _characters = characters;
            _conn = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = databaseFile,
                Mode = SqliteOpenMode.ReadWriteCreate,
            }.ToString());
            _conn.Open();
            Execute(@"
                PRAGMA busy_timeout = 5000;

                CREATE TABLE IF NOT EXISTS phone_contacts (
                    owner       TEXT NOT NULL,
                    other       TEXT NOT NULL,
                    other_name  TEXT NOT NULL,
                    since       TEXT NOT NULL,
                    PRIMARY KEY (owner, other)
                );

                CREATE TABLE IF NOT EXISTS phone_blocks (
                    owner       TEXT NOT NULL,
                    other       TEXT NOT NULL,
                    other_name  TEXT NOT NULL,
                    PRIMARY KEY (owner, other)
                );

                CREATE TABLE IF NOT EXISTS phone_texts (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    time            TEXT    NOT NULL,
                    sender          TEXT    NOT NULL,
                    sender_name     TEXT    NOT NULL,
                    recipient       TEXT    NOT NULL,
                    recipient_name  TEXT    NOT NULL,
                    body            TEXT    NOT NULL,
                    delivered       INTEGER NOT NULL DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS phone_texts_pair ON phone_texts (sender, recipient, id);
                CREATE INDEX IF NOT EXISTS phone_texts_waiting ON phone_texts (recipient, delivered);");
        }

        public void Dispose()
        {
            lock (_lock)
                _conn.Dispose();
        }

        // ---------------------------------------------------------------- players

        private static CyberpunkSdk.Game.Player? Player(ulong id) => Server.PlayerSystem.GetById(id);

        private static IEnumerable<CyberpunkSdk.Game.Player> Online() =>
            Server.PlayerSystem.PlayerIds.Select(id => Server.PlayerSystem.GetById(id)).Where(p => p != null)!;

        private static CyberpunkSdk.Game.Player? OnlineByKey(string key) =>
            Online().FirstOrDefault(p => CharacterKeys.Normalize(p.Username) == key);

        private static string Key(string name) => CharacterKeys.Normalize(name);

        private bool Throttled(ulong playerId, string what, double seconds)
        {
            var now = DateTime.UtcNow;
            lock (_throttle)
            {
                if (_throttle.TryGetValue((playerId, what), out var last) && (now - last).TotalSeconds < seconds)
                    return true;
                _throttle[(playerId, what)] = now;
                return false;
            }
        }

        private static void Notice(ulong playerId, string message) =>
            Cyberpunk.Rpc.Client.Plugins.PhoneClient.Notice(playerId, message);

        // ---------------------------------------------------------------- open / payload

        public void Open(ulong playerId)
        {
            var me = Player(playerId);
            if (me == null || Throttled(playerId, "open", 0.3))
                return;
            Cyberpunk.Rpc.Client.Plugins.PhoneClient.ShowPhone(playerId, Payload(me));
        }

        private void Refresh(ulong playerId)
        {
            var me = Player(playerId);
            if (me != null)
                Cyberpunk.Rpc.Client.Plugins.PhoneClient.ShowPhone(playerId, Payload(me));
        }

        private void RefreshKey(string key)
        {
            // Only redrawn if their phone is open; the game ignores it otherwise.
            var p = OnlineByKey(key);
            if (p != null)
                Cyberpunk.Rpc.Client.Plugins.PhoneClient.ShowPhone(p.Id, Payload(p));
        }

        private string Payload(CyberpunkSdk.Game.Player me)
        {
            var myKey = Key(me.Username);
            var parts = new List<string>();
            var onlineKeys = Online().Select(p => Key(p.Username)).ToHashSet();

            lock (_lock)
            {
                PruneRequests();
                foreach (var ((from, to), _) in _requests)
                {
                    if (to == myKey)
                        parts.Add(Record("R", NameOf(from)));
                }

                var contacts = Contacts(myKey);
                foreach (var (key, name) in contacts)
                    parts.Add(Record("C", name, onlineKeys.Contains(key) ? "1" : "0"));

                // Last few texts with each contact, oldest first.
                foreach (var (key, name) in contacts.Take(40))
                {
                    using var cmd = Command(@"
                        SELECT sender, body, time FROM phone_texts
                        WHERE (sender = $me AND recipient = $other) OR (sender = $other AND recipient = $me)
                        ORDER BY id DESC LIMIT $n");
                    cmd.Parameters.AddWithValue("$me", myKey);
                    cmd.Parameters.AddWithValue("$other", key);
                    cmd.Parameters.AddWithValue("$n", ThreadLength);
                    var thread = new List<string>();
                    using (var reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            var fromMe = reader.GetString(0) == myKey;
                            var time = DateTime.TryParse(reader.GetString(2), out var t) ? t.ToString("MMM d HH:mm") : "";
                            thread.Add(Record("T", name, fromMe ? "1" : "0", reader.GetString(1), time));
                        }
                    }
                    thread.Reverse();
                    parts.AddRange(thread);
                }

                var contactKeys = contacts.Select(c => c.Key).ToHashSet();
                var blocked = Blocked(myKey);
                var blockedKeys = blocked.Select(b => b.Key).ToHashSet();
                var myPos = me.MovementComponent.Position;
                foreach (var p in Online())
                {
                    var key = Key(p.Username);
                    if (key == myKey || contactKeys.Contains(key) || blockedKeys.Contains(key) || IsBlockedBy(myKey, key))
                        continue;
                    var pos = p.MovementComponent.Position;
                    var dx = pos.X - myPos.X;
                    var dy = pos.Y - myPos.Y;
                    var dz = pos.Z - myPos.Z;
                    var meters = MathF.Sqrt(dx * dx + dy * dy + dz * dz);
                    if (meters > NearbyMeters)
                        continue;
                    var sent = _requests.ContainsKey((myKey, key)) ? "1" : "0";
                    parts.Add(Record("N", p.Username, ((int)meters).ToString(), sent));
                }

                foreach (var (_, name) in blocked)
                    parts.Add(Record("B", name));
            }
            return string.Join("^", parts);
        }

        // ---------------------------------------------------------------- sharing

        public void Share(ulong playerId, string character)
        {
            var me = Player(playerId);
            if (me == null || Throttled(playerId, "share", 2))
                return;
            var myKey = Key(me.Username);
            var target = Online().FirstOrDefault(p => string.Equals(p.Username, character, StringComparison.OrdinalIgnoreCase));
            if (target == null)
            {
                Notice(playerId, $"{character} isn't around any more.");
                return;
            }
            var theirKey = Key(target.Username);
            if (theirKey == myKey)
                return;

            var a = me.MovementComponent.Position;
            var b = target.MovementComponent.Position;
            var dx = a.X - b.X; var dy = a.Y - b.Y; var dz = a.Z - b.Z;
            if (dx * dx + dy * dy + dz * dz > NearbyMeters * NearbyMeters)
            {
                Notice(playerId, $"Get closer to {target.Username} to swap numbers.");
                return;
            }

            lock (_lock)
            {
                if (IsBlockedBy(myKey, theirKey) || IsBlockedBy(theirKey, myKey) || AreContacts(myKey, theirKey))
                {
                    Refresh(playerId);
                    return;
                }
                // They already asked us: sharing back is accepting.
                if (_requests.Remove((theirKey, myKey)))
                {
                    AddContacts(myKey, me.Username, theirKey, target.Username);
                    Notice(playerId, $"You and {target.Username} swapped numbers.");
                    Notice(target.Id, $"You and {me.Username} swapped numbers.");
                }
                else
                {
                    _requests[(myKey, theirKey)] = DateTime.UtcNow;
                    Notice(playerId, $"Sent your number to {target.Username}.");
                    Notice(target.Id, $"{me.Username} wants to swap numbers. Open your phone to answer.");
                }
            }
            Refresh(playerId);
            RefreshKey(theirKey);
        }

        public void Answer(ulong playerId, string character, bool accept)
        {
            var me = Player(playerId);
            if (me == null)
                return;
            var myKey = Key(me.Username);
            var theirKey = Key(character);
            lock (_lock)
            {
                if (!_requests.Remove((theirKey, myKey)))
                {
                    Refresh(playerId);
                    return;
                }
                if (accept)
                {
                    var theirName = NameOf(theirKey);
                    AddContacts(myKey, me.Username, theirKey, theirName);
                    Notice(playerId, $"{theirName} added to your contacts.");
                    var them = OnlineByKey(theirKey);
                    if (them != null)
                        Notice(them.Id, $"{me.Username} saved your number.");
                }
            }
            Refresh(playerId);
            RefreshKey(theirKey);
        }

        public void Remove(ulong playerId, string character)
        {
            var me = Player(playerId);
            if (me == null)
                return;
            var myKey = Key(me.Username);
            var theirKey = Key(character);
            lock (_lock)
                RemoveContacts(myKey, theirKey);
            Refresh(playerId);
            RefreshKey(theirKey);
        }

        public void SetBlocked(ulong playerId, string character, bool blocked)
        {
            var me = Player(playerId);
            if (me == null)
                return;
            var myKey = Key(me.Username);
            var theirKey = Key(character);
            if (theirKey == myKey)
                return;
            lock (_lock)
            {
                if (blocked)
                {
                    RemoveContacts(myKey, theirKey);
                    _requests.Remove((theirKey, myKey));
                    _requests.Remove((myKey, theirKey));
                    using var cmd = Command("INSERT OR REPLACE INTO phone_blocks (owner, other, other_name) VALUES ($o, $t, $n)");
                    cmd.Parameters.AddWithValue("$o", myKey);
                    cmd.Parameters.AddWithValue("$t", theirKey);
                    cmd.Parameters.AddWithValue("$n", NameOf(theirKey, character));
                    cmd.ExecuteNonQuery();
                }
                else
                {
                    using var cmd = Command("DELETE FROM phone_blocks WHERE owner = $o AND other = $t");
                    cmd.Parameters.AddWithValue("$o", myKey);
                    cmd.Parameters.AddWithValue("$t", theirKey);
                    cmd.ExecuteNonQuery();
                }
            }
            Notice(playerId, blocked ? $"Blocked {character}." : $"Unblocked {character}.");
            Refresh(playerId);
            RefreshKey(theirKey);
        }

        // ---------------------------------------------------------------- texts and pings

        public void Text(ulong playerId, string character, string message)
        {
            var me = Player(playerId);
            if (me == null)
                return;
            message = (message ?? "").Trim();
            if (message.Length == 0)
                return;
            if (message.Length > MaxText)
                message = message[..MaxText];
            if (Throttled(playerId, "text", 0.8))
            {
                Notice(playerId, "Slow down a little.");
                return;
            }
            var myKey = Key(me.Username);
            var theirKey = Key(character);
            string theirName;
            lock (_lock)
            {
                if (!AreContacts(myKey, theirKey))
                {
                    Notice(playerId, $"{character} isn't in your contacts.");
                    return;
                }
                theirName = NameOf(theirKey, character);
                var them = OnlineByKey(theirKey);
                using var cmd = Command(@"
                    INSERT INTO phone_texts (time, sender, sender_name, recipient, recipient_name, body, delivered)
                    VALUES ($time, $s, $sn, $r, $rn, $body, $d)");
                cmd.Parameters.AddWithValue("$time", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
                cmd.Parameters.AddWithValue("$s", myKey);
                cmd.Parameters.AddWithValue("$sn", me.Username);
                cmd.Parameters.AddWithValue("$r", theirKey);
                cmd.Parameters.AddWithValue("$rn", theirName);
                cmd.Parameters.AddWithValue("$body", message);
                cmd.Parameters.AddWithValue("$d", them != null ? 1 : 0);
                cmd.ExecuteNonQuery();

                if (them != null)
                    Cyberpunk.Rpc.Client.Plugins.PhoneClient.ReceiveText(them.Id, me.Username, message);
                else
                    Notice(playerId, $"{theirName} is offline. They'll get it when they're back.");
            }
            me.SendChat("TEXT to " + theirName, message);
            Refresh(playerId);
        }

        public void Ping(ulong playerId, string character)
        {
            var me = Player(playerId);
            if (me == null || Throttled(playerId, "ping", 5))
                return;
            var myKey = Key(me.Username);
            var theirKey = Key(character);
            CyberpunkSdk.Game.Player? them;
            lock (_lock)
            {
                if (!AreContacts(myKey, theirKey))
                    return;
                them = OnlineByKey(theirKey);
            }
            if (them == null)
            {
                Notice(playerId, $"{character} is offline.");
                return;
            }
            var pos = me.MovementComponent.Position;
            Cyberpunk.Rpc.Client.Plugins.PhoneClient.ReceivePing(them.Id, me.Username, pos.X, pos.Y, pos.Z);
            Notice(playerId, $"Sent your location to {them.Username}.");
        }

        /// <summary>Texts that arrived while this character was offline.</summary>
        public void OnJoin(ulong playerId, string username)
        {
            var key = Key(username);
            var waiting = new List<(long Id, string From, string Body)>();
            lock (_lock)
            {
                using (var cmd = Command("SELECT id, sender_name, body FROM phone_texts WHERE recipient = $r AND delivered = 0 ORDER BY id LIMIT 50"))
                {
                    cmd.Parameters.AddWithValue("$r", key);
                    using var reader = cmd.ExecuteReader();
                    while (reader.Read())
                        waiting.Add((reader.GetInt64(0), reader.GetString(1), reader.GetString(2)));
                }
                if (waiting.Count > 0)
                {
                    using var mark = Command("UPDATE phone_texts SET delivered = 1 WHERE recipient = $r AND delivered = 0");
                    mark.Parameters.AddWithValue("$r", key);
                    mark.ExecuteNonQuery();
                }
            }
            if (waiting.Count == 0)
                return;
            // A moment later, once the game is listening (see Tick).
            lock (_due)
                _due.Add((DateTime.UtcNow.AddSeconds(8), playerId, waiting.Select(w => (w.From, w.Body)).ToList()));
        }

        private readonly List<(DateTime When, ulong PlayerId, List<(string From, string Body)> Texts)> _due = new();

        /// <summary>Hands over waiting texts once their time comes (runs every second).</summary>
        public void Tick()
        {
            List<(DateTime When, ulong PlayerId, List<(string From, string Body)> Texts)> ready;
            lock (_due)
            {
                var now = DateTime.UtcNow;
                ready = _due.Where(d => d.When <= now).ToList();
                _due.RemoveAll(d => d.When <= now);
            }
            foreach (var (_, playerId, texts) in ready)
            {
                var player = Player(playerId);
                if (player == null)
                    continue;
                Notice(playerId, texts.Count == 1 ? "1 text while you were away." : $"{texts.Count} texts while you were away.");
                foreach (var (from, body) in texts)
                    player.SendChat("TEXT from " + from, body);
            }
        }

        public void OnLeave(ulong playerId)
        {
            lock (_throttle)
            {
                foreach (var k in _throttle.Keys.Where(k => k.Item1 == playerId).ToList())
                    _throttle.Remove(k);
            }
        }

        // ---------------------------------------------------------------- storage

        private void PruneRequests()
        {
            var cutoff = DateTime.UtcNow.AddMinutes(-10);
            foreach (var k in _requests.Where(r => r.Value < cutoff).Select(r => r.Key).ToList())
                _requests.Remove(k);
        }

        private List<(string Key, string Name)> Contacts(string owner)
        {
            var list = new List<(string, string)>();
            using var cmd = Command("SELECT other, other_name FROM phone_contacts WHERE owner = $o ORDER BY other_name COLLATE NOCASE");
            cmd.Parameters.AddWithValue("$o", owner);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
                list.Add((reader.GetString(0), reader.GetString(1)));
            return list;
        }

        private List<(string Key, string Name)> Blocked(string owner)
        {
            var list = new List<(string, string)>();
            using var cmd = Command("SELECT other, other_name FROM phone_blocks WHERE owner = $o ORDER BY other_name COLLATE NOCASE");
            cmd.Parameters.AddWithValue("$o", owner);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
                list.Add((reader.GetString(0), reader.GetString(1)));
            return list;
        }

        private bool AreContacts(string a, string b)
        {
            using var cmd = Command("SELECT 1 FROM phone_contacts WHERE owner = $a AND other = $b");
            cmd.Parameters.AddWithValue("$a", a);
            cmd.Parameters.AddWithValue("$b", b);
            return cmd.ExecuteScalar() != null;
        }

        /// <summary>Has <paramref name="owner"/> blocked <paramref name="other"/>?</summary>
        private bool IsBlockedBy(string other, string owner)
        {
            using var cmd = Command("SELECT 1 FROM phone_blocks WHERE owner = $o AND other = $t");
            cmd.Parameters.AddWithValue("$o", owner);
            cmd.Parameters.AddWithValue("$t", other);
            return cmd.ExecuteScalar() != null;
        }

        private void AddContacts(string aKey, string aName, string bKey, string bName)
        {
            var now = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
            using var tx = _conn.BeginTransaction();
            foreach (var (owner, other, otherName) in new[] { (aKey, bKey, bName), (bKey, aKey, aName) })
            {
                using var cmd = Command("INSERT OR REPLACE INTO phone_contacts (owner, other, other_name, since) VALUES ($o, $t, $n, $s)");
                cmd.Transaction = tx;
                cmd.Parameters.AddWithValue("$o", owner);
                cmd.Parameters.AddWithValue("$t", other);
                cmd.Parameters.AddWithValue("$n", otherName);
                cmd.Parameters.AddWithValue("$s", now);
                cmd.ExecuteNonQuery();
            }
            tx.Commit();
            _logger.Info($"{aName} and {bName} swapped numbers.");
        }

        private void RemoveContacts(string a, string b)
        {
            using var cmd = Command("DELETE FROM phone_contacts WHERE (owner = $a AND other = $b) OR (owner = $b AND other = $a)");
            cmd.Parameters.AddWithValue("$a", a);
            cmd.Parameters.AddWithValue("$b", b);
            cmd.ExecuteNonQuery();
        }

        private string NameOf(string key, string fallback = "")
        {
            var online = OnlineByKey(key);
            if (online != null)
                return online.Username;
            var record = _characters.Snapshot(key);
            if (record != null && !string.IsNullOrEmpty(record.DisplayName))
                return record.DisplayName;
            return string.IsNullOrEmpty(fallback) ? key : fallback;
        }

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

        private static string Record(params string[] fields) =>
            string.Join("~", fields.Select(f => (f ?? "").Replace("~", "-").Replace("^", "-")));
    }
}
