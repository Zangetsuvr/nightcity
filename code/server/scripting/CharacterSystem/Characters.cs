using CharacterSystem.Store;
using CyberpunkSdk;

namespace CharacterSystem
{
    /// <summary>
    /// The rules for money and progress. Knows which players are online and
    /// which saved character each one is, and applies every change through the
    /// store so it gets saved and logged.
    ///
    /// Talks to the game only through the callbacks passed in, so the rules can
    /// be tested without a running server.
    /// </summary>
    public class Characters : IEconomy, IProgression
    {
        private readonly ICharacterStore _store;
        private readonly Config _config;
        private readonly Security _security;

        private readonly object _onlineLock = new();
        private readonly Dictionary<ulong, string> _online = new();
        private readonly Dictionary<ulong, DateTime> _joinedAt = new();

        /// <summary>Tell a player's game their balance.</summary>
        public Action<ulong, long> PushBalance { get; set; } = (_, _) => { };

        /// <summary>Tell a player's game their level, XP and XP needed for next level.</summary>
        public Action<ulong, int, long, long> PushProgress { get; set; } = (_, _, _, _) => { };

        /// <summary>Give a player's game its starter kit ("item,quantity,equip|...").</summary>
        public Action<ulong, string> PushStarterKit { get; set; } = (_, _) => { };

        /// <summary>Tell a player's game its cyberware tier: tier, capacity, best quality (1-5), price of the next tier (0 = none).</summary>
        public Action<ulong, int, int, int, int> PushCyberware { get; set; } = (_, _, _, _, _) => { };

        /// <summary>Send a player's game the dealership (where it is and what it sells).</summary>
        public Action<ulong, string> PushShopData { get; set; } = (_, _) => { };

        /// <summary>Make the given cars ("|"-separated records) available in the player's garage.</summary>
        public Action<ulong, string> PushVehicles { get; set; } = (_, _) => { };

        /// <summary>Show a player a short message.</summary>
        public Action<ulong, string> Notify { get; set; } = (_, _) => { };

        internal ICharacterStore Store => _store;
        internal Security Security => _security;

        public Characters(ICharacterStore store, Config config, Security security)
        {
            _store = store;
            _config = config;
            _security = security;
        }

        // ---------------------------------------------------------------- sessions

        public void OnJoin(ulong playerId, string username)
        {
            var record = _store.LoadOrCreate(username, _config.StartingBalance, out var created);

            lock (_onlineLock)
            {
                // The same name connecting twice would let two sessions share one
                // wallet. The newest session wins; the old id stops resolving.
                foreach (var (id, key) in _online.ToList())
                {
                    if (key == record.Key && id != playerId)
                    {
                        _online.Remove(id);
                        _joinedAt.Remove(id);
                    }
                }

                _online[playerId] = record.Key;
                _joinedAt[playerId] = DateTime.UtcNow;
            }

            _store.Modify(record.Key, r => { r.LastSeenUtc = DateTime.UtcNow; return true; });

            if (created)
            {
                _store.AppendLedger(new LedgerEntry(DateTime.UtcNow, record.Key, _config.StartingBalance, _config.StartingBalance, "Starting money", null));
                Notify(playerId, $"Welcome to Night City. You start with {_config.StartingBalance} eddies.");
            }
            else
            {
                Notify(playerId, $"Welcome back. Balance: {GetBalance(playerId)} eddies.");
            }

            Sync(playerId);
        }

        public void OnLeave(ulong playerId)
        {
            _security.Forget(playerId);

            string? key;
            DateTime joined;
            lock (_onlineLock)
            {
                if (!_online.Remove(playerId, out key))
                    return;
                _joinedAt.Remove(playerId, out joined);
            }

            var seconds = (long)Math.Max(0, (DateTime.UtcNow - joined).TotalSeconds);
            _store.Modify(key, r =>
            {
                r.LastSeenUtc = DateTime.UtcNow;
                r.PlaySeconds += seconds;
                return true;
            });

            // Only drop it from memory if no newer session took over this character.
            bool stillOnline;
            lock (_onlineLock) { stillOnline = _online.ContainsValue(key); }
            if (stillOnline)
                _store.Flush();
            else
                _store.Unload(key);
        }

        public IReadOnlyList<ulong> OnlinePlayers()
        {
            lock (_onlineLock) { return _online.Keys.ToList(); }
        }

        public bool IsOnline(string username)
        {
            var key = CharacterKeys.Normalize(username);
            lock (_onlineLock) { return _online.ContainsValue(key); }
        }

        /// <summary>Re-send balance and progress to a player's game.</summary>
        public void Sync(ulong playerId)
        {
            var key = KeyOf(playerId);
            if (key == null)
                return;

            var balance = _store.Read(key, r => r.Balance);
            var xp = _store.Read(key, r => r.GetXp(Leveling.StreetCred));

            PushBalance(playerId, balance);
            PushProgress(playerId, Leveling.LevelForXp(xp, _config.MaxLevel), xp, Leveling.NextLevelXp(xp, _config.MaxLevel));
        }

        public void SyncAll()
        {
            foreach (var id in OnlinePlayers())
                Sync(id);
        }

        // ---------------------------------------------------------------- money

        public long GetBalance(ulong playerId)
        {
            var key = KeyOf(playerId);
            return key == null ? 0 : _store.Read(key, r => r.Balance);
        }

        public bool Credit(ulong playerId, long amount, string reason)
        {
            var key = KeyOf(playerId);
            if (key == null || !ValidAmount(amount) || IsFrozen(key))
                return false;

            if (!AllowEarning(playerId, key, amount, reason))
                return false;

            long after = 0;
            var ok = _store.Modify(key, r =>
            {
                if (r.Frozen || r.Balance + amount > _config.MaxBalance)
                    return false;
                r.Balance += amount;
                after = r.Balance;
                return true;
            });

            if (!ok)
                return false;

            _security.RecordEarning(key, amount);
            _store.AppendLedger(new LedgerEntry(DateTime.UtcNow, key, amount, after, reason, null));
            PushBalance(playerId, after);
            return true;
        }

        public bool Debit(ulong playerId, long amount, string reason)
        {
            var key = KeyOf(playerId);
            if (key == null || !ValidAmount(amount))
                return false;

            long after = 0;
            var ok = _store.Modify(key, r =>
            {
                if (r.Frozen || r.Balance < amount)
                    return false;
                r.Balance -= amount;
                after = r.Balance;
                return true;
            });

            if (!ok)
                return false;

            _store.AppendLedger(new LedgerEntry(DateTime.UtcNow, key, -amount, after, reason, null));
            PushBalance(playerId, after);
            return true;
        }

        public bool Transfer(ulong fromPlayerId, ulong toPlayerId, long amount, string reason)
        {
            var fromKey = KeyOf(fromPlayerId);
            var toKey = KeyOf(toPlayerId);
            if (fromKey == null || toKey == null || !ValidAmount(amount))
                return false;

            if (IsFrozen(fromKey) || IsFrozen(toKey))
                return false;

            if (!AllowEarning(toPlayerId, toKey, amount, reason))
                return false;

            long fromAfter = 0, toAfter = 0;
            var ok = _store.ModifyPair(fromKey, toKey, (from, to) =>
            {
                if (from.Frozen || to.Frozen || from.Balance < amount || to.Balance + amount > _config.MaxBalance)
                    return false;
                from.Balance -= amount;
                to.Balance += amount;
                fromAfter = from.Balance;
                toAfter = to.Balance;
                return true;
            });

            if (!ok)
                return false;

            _security.RecordEarning(toKey, amount);
            var now = DateTime.UtcNow;
            _store.AppendLedger(new LedgerEntry(now, fromKey, -amount, fromAfter, reason, toKey));
            _store.AppendLedger(new LedgerEntry(now, toKey, amount, toAfter, reason, fromKey));
            PushBalance(fromPlayerId, fromAfter);
            PushBalance(toPlayerId, toAfter);
            return true;
        }

        /// <summary>
        /// Admin change to anyone's balance, online or offline. A positive amount
        /// adds, a negative one removes; the balance can't go below zero.
        /// </summary>
        public bool AdminAdjust(string username, long amount, string reason, out long balanceAfter)
        {
            long after = 0;
            balanceAfter = 0;
            if (amount == 0 || amount == long.MinValue || Math.Abs(amount) > _config.MaxBalance)
                return false;

            var ok = _store.ModifyOffline(username, r =>
            {
                var next = r.Balance + amount;
                if (next < 0 || next > _config.MaxBalance)
                    return false;
                r.Balance = next;
                after = next;
                return true;
            });

            if (!ok)
                return false;

            balanceAfter = after;
            var key = CharacterKeys.Normalize(username);
            _store.AppendLedger(new LedgerEntry(DateTime.UtcNow, key, amount, after, "Admin: " + reason, null));

            foreach (var id in IdsOf(key))
                PushBalance(id, after);
            return true;
        }

        // ---------------------------------------------------------------- cheat protection

        /// <summary>
        /// The player's game says its eddies were <paramref name="localBalance"/>
        /// although the server last sent <paramref name="lastFromServer"/>.
        /// Flag it if the jump is big, and correct the game straight away.
        /// </summary>
        public void OnLocalBalanceReport(ulong playerId, long localBalance, long lastFromServer)
        {
            var key = KeyOf(playerId);
            if (key == null || localBalance < 0 || lastFromServer < 0)
                return;

            var spent = lastFromServer - localBalance;
            if (spent > 0)
            {
                // The game spent money on its own, almost always an in-game vendor.
                // Charge it on the server too, otherwise the next sync would refund
                // the purchase and every item would be free. Never rate-limited, so
                // no purchase can slip through; a player spamming these only
                // charges themselves.
                if (!Debit(playerId, Math.Min(spent, _config.MaxTransaction), "Spent in game (vendor)"))
                    _security.Flag(key, "unpaid-spend", $"Game spent {spent} eddies the server couldn't charge (frozen or not enough money).");
                return; // Debit already sent the new balance.
            }

            // The game gained money on its own: undone by the sync below, and
            // flagged if it's a big jump. Limited so a cheat can't flood flags.
            if (!_security.AllowCall(playerId, "balance-report", 2))
                return;

            _security.OnLocalBalanceReport(key, localBalance, lastFromServer);
            Sync(playerId);
        }

        /// <summary>A sync the player's game asked for. Limited to one every 2 seconds.</summary>
        public void RequestedSync(ulong playerId)
        {
            if (!_security.AllowCall(playerId, "sync", 2))
                return;
            PlaceIfNew(playerId);
            Sync(playerId);
            SendShopState(playerId);
        }

        // ---------------------------------------------------------------- cyberware and cars

        /// <summary>Cyberware tier, the dealership and the cars this character owns.</summary>
        public void SendShopState(ulong playerId)
        {
            var key = KeyOf(playerId);
            if (key == null)
                return;

            SendCyberware(playerId, _store.Read(key, r => r.CyberwareTier));

            var d = _config.Dealership;
            var lines = new List<string>
            {
                string.Join("~", "D", Clean(d.Name), d.Location.X.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    d.Location.Y.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    d.Location.Z.ToString(System.Globalization.CultureInfo.InvariantCulture)),
            };
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            foreach (var m in _config.MapMarkers)
                lines.Add(string.Join("~", "M", Clean(m.Type), Clean(m.Name), m.X.ToString(inv), m.Y.ToString(inv), m.Z.ToString(inv)));
            foreach (var car in d.Cars)
                lines.Add(string.Join("~", "V", Clean(car.Record), Clean(car.Name), car.Price.ToString()));
            PushShopData(playerId, string.Join("^", lines));

            var owned = _store.Read(key, r => r.OwnedVehicles.ToList());
            if (owned.Count > 0)
                PushVehicles(playerId, string.Join("|", owned));
        }

        private void SendCyberware(ulong playerId, int tier)
        {
            var tiers = _config.CyberwareTiers.OrderBy(t => t.Tier).ToList();
            var current = tiers.LastOrDefault(t => t.Tier <= tier) ?? tiers.FirstOrDefault();
            if (current == null)
                return;
            var next = tiers.FirstOrDefault(t => t.Tier > current.Tier);
            PushCyberware(playerId, current.Tier, current.Capacity, QualityRank(current.MaxQuality),
                next == null ? 0 : (int)Math.Min(int.MaxValue, next.Price));
        }

        public static int QualityRank(string quality) => quality.Trim().ToLowerInvariant() switch
        {
            "common" => 1,
            "uncommon" => 2,
            "rare" => 3,
            "epic" => 4,
            "legendary" => 5,
            _ => 5,
        };

        /// <summary>Move up one cyberware tier, if the player can pay for it.</summary>
        public void BuyCyberwareTier(ulong playerId)
        {
            var key = KeyOf(playerId);
            if (key == null || !_security.AllowCall(playerId, "cyberware-tier", 2))
                return;

            var tier = _store.Read(key, r => r.CyberwareTier);
            var next = _config.CyberwareTiers.OrderBy(t => t.Tier).FirstOrDefault(t => t.Tier > tier);
            if (next == null)
            {
                Notify(playerId, "You're already at the highest cyberware tier.");
                return;
            }

            if (next.Price > 0 && !Debit(playerId, next.Price, $"Cyberware tier {next.Tier}"))
            {
                Notify(playerId, $"Cyberware tier {next.Tier} costs {next.Price} eddies. You can't cover it.");
                return;
            }

            _store.Modify(key, r => { r.CyberwareTier = next.Tier; return true; });
            Notify(playerId, $"Cyberware tier {next.Tier}: capacity {next.Capacity}, implants up to {next.MaxQuality}.");
            SendCyberware(playerId, next.Tier);
        }

        /// <summary>Buy a car from the dealership. It goes to the player's garage.</summary>
        public void BuyVehicle(ulong playerId, string record)
        {
            var key = KeyOf(playerId);
            if (key == null || !_security.AllowCall(playerId, "buy-vehicle", 2))
                return;

            var offer = _config.Dealership.Cars.FirstOrDefault(c => string.Equals(c.Record, record, StringComparison.Ordinal));
            if (offer == null)
                return;

            if (_store.Read(key, r => r.OwnedVehicles.Contains(offer.Record)))
            {
                Notify(playerId, $"You already own a {offer.Name}. Call it from your phone.");
                return;
            }

            if (offer.Price > 0 && !Debit(playerId, offer.Price, $"Dealership: {offer.Name}"))
            {
                Notify(playerId, $"The {offer.Name} costs {offer.Price} eddies. You can't cover it.");
                return;
            }

            _store.Modify(key, r => { r.OwnedVehicles.Add(offer.Record); return true; });
            Notify(playerId, $"You bought a {offer.Name}. It's in your garage: call it from your phone.");
            PushVehicles(playerId, offer.Record);
        }

        private static string Clean(string text) => (text ?? "").Replace("~", "-").Replace("^", "-").Replace("|", "-");

        /// <summary>
        /// The game asks for a sync once it's connected and standing in the world.
        /// A character that has never been placed is moved to the start point then,
        /// out of the holding room a clean New Game leaves them in. Happens once.
        /// </summary>
        private void PlaceIfNew(ulong playerId)
        {
            var start = _config.Start;
            var key = KeyOf(playerId);
            if (start == null || key == null)
                return;

            if (_store.Read(key, r => r.SpawnedBefore))
                return;

            if (_store.Modify(key, r => { r.SpawnedBefore = true; return true; }))
                Cyberpunk.Rpc.Client.Plugins.CharacterClient.Teleport(playerId, start.X, start.Y, start.Z, start.Yaw);
        }

        /// <summary>
        /// The game, once connected, says which lifepath this character picked in
        /// the creator. A character that hasn't had its starter kit yet gets it now;
        /// after that this does nothing, so a reconnect never hands out a second one.
        /// </summary>
        public void ClaimStarterKit(ulong playerId, int lifepath)
        {
            var key = KeyOf(playerId);
            if (key == null || !_security.AllowCall(playerId, "starter-kit", 2))
                return;

            // The game's own numbering (gamedataLifePath).
            var name = lifepath switch { 0 => "Corpo", 1 => "Nomad", 2 => "StreetKid", _ => null };
            if (name == null)
                return;

            if (_store.Read(key, r => r.StarterKitGranted))
                return;

            if (!_config.StarterKits.TryGetValue(name, out var kit) || kit.Count == 0)
            {
                _store.Modify(key, r => { r.Lifepath = name; r.StarterKitGranted = true; return true; });
                return;
            }

            // Marked first: if anything goes wrong after this, the worst case is a
            // character without a kit (fixable by an admin), never one with two.
            if (!_store.Modify(key, r => { r.Lifepath = name; r.StarterKitGranted = true; return true; }))
                return;

            var lines = kit
                .Where(i => !string.IsNullOrWhiteSpace(i.Item) && i.Quantity > 0)
                .Select(i => $"{i.Item.Trim()},{i.Quantity},{(i.Equip ? 1 : 0)}");
            PushStarterKit(playerId, string.Join("|", lines));
        }

        /// <summary>Locks or unlocks a character's money (admin).</summary>
        public bool SetFrozen(string username, bool frozen, string reason)
        {
            var ok = _store.ModifyOffline(username, r =>
            {
                r.Frozen = frozen;
                r.FrozenReason = frozen ? reason : null;
                return true;
            });

            if (ok)
            {
                var key = CharacterKeys.Normalize(username);
                _security.Flag(key, frozen ? "frozen" : "unfrozen", reason);
                foreach (var id in IdsOf(key))
                    Notify(id, frozen ? "Your wallet has been frozen by an admin." : "Your wallet has been unfrozen.");
            }
            return ok;
        }

        // ---------------------------------------------------------------- progress

        public void AddXp(ulong playerId, string track, long amount, string reason)
        {
            var key = KeyOf(playerId);
            if (key == null || amount <= 0 || string.IsNullOrWhiteSpace(track))
                return;

            int levelBefore = 1, levelAfter = 1;
            long credAfter = 0;
            _store.Modify(key, r =>
            {
                var credBefore = r.GetXp(Leveling.StreetCred);
                levelBefore = Leveling.LevelForXp(credBefore, _config.MaxLevel);

                r.Xp[track] = r.GetXp(track) + amount;
                // Every kind of XP also counts toward the overall Street Cred level.
                if (track != Leveling.StreetCred)
                    r.Xp[Leveling.StreetCred] = credBefore + amount;

                credAfter = r.GetXp(Leveling.StreetCred);
                levelAfter = Leveling.LevelForXp(credAfter, _config.MaxLevel);
                return true;
            });

            PushProgress(playerId, levelAfter, credAfter, Leveling.NextLevelXp(credAfter, _config.MaxLevel));
            if (levelAfter > levelBefore)
                Notify(playerId, $"Street Cred level {levelAfter}!");
        }

        public long GetXp(ulong playerId, string track)
        {
            var key = KeyOf(playerId);
            return key == null ? 0 : _store.Read(key, r => r.GetXp(track));
        }

        public string? GetSavedJob(ulong playerId)
        {
            var key = KeyOf(playerId);
            return key == null ? null : _store.Read(key, r => r.Job);
        }

        public void SetSavedJob(ulong playerId, string? job)
        {
            var key = KeyOf(playerId);
            if (key != null)
                _store.Modify(key, r => { r.Job = job; return true; });
        }

        // ---------------------------------------------------------------- helpers

        private string? KeyOf(ulong playerId)
        {
            lock (_onlineLock)
            {
                return _online.TryGetValue(playerId, out var key) ? key : null;
            }
        }

        private List<ulong> IdsOf(string key)
        {
            lock (_onlineLock)
            {
                return _online.Where(kv => kv.Value == key).Select(kv => kv.Key).ToList();
            }
        }

        private bool ValidAmount(long amount) => amount > 0 && amount <= _config.MaxTransaction;

        private bool IsFrozen(string key) => _store.Read(key, r => r.Frozen);

        /// <summary>Hourly earnings check before paying someone.</summary>
        private bool AllowEarning(ulong playerId, string key, long amount, string reason)
        {
            if (_security.CanEarn(key, amount))
                return true;

            _security.Flag(key, "earnings-limit", $"Payout of {amount} refused ({reason}): over {_config.EarningsLimitPerHour} earned this hour.");
            if (_config.FreezeOnEarningsLimit)
                SetFrozen(_store.Read(key, r => r.DisplayName) ?? key, true, "Hit the hourly earnings limit");
            else
                Notify(playerId, "You've hit the hourly earnings limit. Payouts resume later.");
            return false;
        }
    }
}
