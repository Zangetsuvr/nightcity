using System.Text.Json;

namespace CharacterSystem
{
    /// <summary>A suspicious event, written to data/flags.jsonl and shown in the admin API.</summary>
    public record SecurityFlag(DateTime TimeUtc, string Character, string Kind, string Detail);

    /// <summary>
    /// Cheat protection for money.
    ///
    /// The main protection is structural: the server owns every balance, so money
    /// a cheat mod adds inside someone's game is never real - it can't be spent
    /// through the server, transferred or saved, and it's wiped at the next sync.
    /// This class adds the layer on top:
    ///
    ///  - Tamper reports: the game tells us when its eddies changed without the
    ///    server's say-so (console commands, trainers, money mods). We resync at
    ///    once and flag big jumps.
    ///  - Earnings watch: flags anyone earning far more per hour than normal play
    ///    allows, and can refuse further payouts past a hard limit. This catches
    ///    abuse of real server systems (exploiting a job, duping a reward).
    ///  - Frozen wallets: an admin (or the hard limit, if turned on) can lock a
    ///    character's money while it's looked into.
    ///  - Rate limits so nobody can flood the server with requests.
    /// </summary>
    public class Security
    {
        private readonly Config _config;
        private readonly string _flagsFile;
        private readonly Action<string> _logWarn;

        private readonly object _lock = new();
        private readonly List<SecurityFlag> _recent = new();
        private readonly Dictionary<string, Queue<(DateTime Time, long Amount)>> _earnings = new();
        private readonly Dictionary<string, DateTime> _lastEarningsAlert = new();
        private readonly Dictionary<(ulong, string), DateTime> _lastCall = new();

        private const int MaxRecentFlags = 500;

        public Security(Config config, string dataDir, Action<string> logWarn)
        {
            _config = config;
            _flagsFile = Path.Combine(dataDir, "flags.jsonl");
            _logWarn = logWarn;
            Directory.CreateDirectory(dataDir);
        }

        /// <summary>Records a suspicious event.</summary>
        public void Flag(string character, string kind, string detail)
        {
            var flag = new SecurityFlag(DateTime.UtcNow, character, kind, detail);
            lock (_lock)
            {
                _recent.Add(flag);
                if (_recent.Count > MaxRecentFlags)
                    _recent.RemoveRange(0, _recent.Count - MaxRecentFlags);

                try
                {
                    File.AppendAllText(_flagsFile, JsonSerializer.Serialize(flag) + "\n");
                }
                catch (Exception ex)
                {
                    _logWarn($"Could not write flags file: {ex.Message}");
                }
            }
            _logWarn($"FLAG [{kind}] {character}: {detail}");
        }

        public List<SecurityFlag> RecentFlags()
        {
            lock (_lock) { return _recent.AsEnumerable().Reverse().ToList(); }
        }

        /// <summary>
        /// True if this player may make this request now. Each kind of request
        /// gets one call per <paramref name="minSeconds"/>.
        /// </summary>
        public bool AllowCall(ulong playerId, string what, double minSeconds)
        {
            var now = DateTime.UtcNow;
            lock (_lock)
            {
                if (_lastCall.TryGetValue((playerId, what), out var last) && (now - last).TotalSeconds < minSeconds)
                    return false;
                _lastCall[(playerId, what)] = now;
                return true;
            }
        }

        public void Forget(ulong playerId)
        {
            lock (_lock)
            {
                foreach (var key in _lastCall.Keys.Where(k => k.Item1 == playerId).ToList())
                    _lastCall.Remove(key);
            }
        }

        /// <summary>
        /// Called before any payout. Returns false if it would take the character
        /// past the hourly hard limit. Nothing is recorded here; call
        /// <see cref="RecordEarning"/> once the payout has actually happened.
        /// </summary>
        public bool CanEarn(string character, long amount)
        {
            if (_config.EarningsLimitPerHour <= 0)
                return true;
            return EarnedLastHour(character) + amount <= _config.EarningsLimitPerHour;
        }

        /// <summary>Counts a completed payout toward the hourly total and flags big earners.</summary>
        public void RecordEarning(string character, long amount)
        {
            var now = DateTime.UtcNow;
            lock (_lock)
            {
                if (!_earnings.TryGetValue(character, out var queue))
                    _earnings[character] = queue = new Queue<(DateTime, long)>();
                queue.Enqueue((now, amount));
            }

            var total = EarnedLastHour(character);
            if (_config.EarningsAlertPerHour <= 0 || total <= _config.EarningsAlertPerHour)
                return;

            bool alert;
            lock (_lock)
            {
                // One alert per character per hour is enough.
                alert = !_lastEarningsAlert.TryGetValue(character, out var last) || (now - last).TotalHours >= 1;
                if (alert)
                    _lastEarningsAlert[character] = now;
            }
            if (alert)
                Flag(character, "high-earnings", $"Earned {total} in the last hour (alert level {_config.EarningsAlertPerHour}).");
        }

        private long EarnedLastHour(string character)
        {
            var now = DateTime.UtcNow;
            lock (_lock)
            {
                if (!_earnings.TryGetValue(character, out var queue))
                    return 0;
                while (queue.Count > 0 && (now - queue.Peek().Time).TotalHours >= 1)
                    queue.Dequeue();
                return queue.Sum(e => e.Amount);
            }
        }

        /// <summary>
        /// The player's game reports what its eddies were just before the server
        /// corrected them. Any difference means something other than the server
        /// changed their money.
        /// </summary>
        public void OnLocalBalanceReport(string character, long localBalance, long lastFromServer)
        {
            var diff = localBalance - lastFromServer;
            if (diff >= _config.TamperFlagThreshold)
                Flag(character, "money-tamper", $"Game showed {localBalance} eddies but the server had sent {lastFromServer} (+{diff}). Corrected.");
        }
    }
}
