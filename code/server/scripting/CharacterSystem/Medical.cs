using CyberpunkSdk;
using CyberpunkSdk.Systems;

namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class MedicalServer
    {
        public static partial void Downed_Impl(ulong playerId, float x, float y, float z) =>
            CharacterSystem.Plugin.Instance.Medical.Downed(playerId, x, y, z);

        public static partial void GoToHospital_Impl(ulong playerId) =>
            CharacterSystem.Plugin.Instance.Medical.GoToHospital(playerId);
    }
}

namespace CharacterSystem
{
    /// <summary>
    /// Flatlining on the server. The player's game keeps them alive at the last
    /// moment (no death screen, no reload) and reports them down. They stay down
    /// for Medical.DownedSeconds while Trauma Team is called for them; a medic who
    /// reaches them (or an admin) gets them up where they are. After the wait
    /// they can choose the hospital: the nearest one in character.json, minus
    /// the bill.
    /// </summary>
    internal sealed class MedicalService : IMedical
    {
        private readonly Config _config;
        private readonly Logger _logger = new("Medical");
        private readonly object _lock = new();
        private readonly Dictionary<ulong, (DateTime Since, float X, float Y, float Z)> _downed = new();

        public MedicalService(Config config)
        {
            _config = config;
            GameServices.Medical = this;
            Server.PlayerSystem.PlayerLeftEvent += id => { lock (_lock) _downed.Remove(id); };
        }

        public bool IsDowned(ulong playerId)
        {
            lock (_lock)
                return _downed.ContainsKey(playerId);
        }

        public void Downed(ulong playerId, float x, float y, float z)
        {
            var player = Server.PlayerSystem.GetById(playerId);
            if (player == null)
                return;
            lock (_lock)
            {
                if (_downed.ContainsKey(playerId))
                    return;
                _downed[playerId] = (DateTime.UtcNow, x, y, z);
            }
            var wait = Math.Max(0, _config.Medical.DownedSeconds);
            _logger.Info($"{player.Username} is down.");
            Cyberpunk.Rpc.Client.Plugins.MedicalClient.SetDowned(playerId, wait);
            GameServices.Dispatch?.CallService(playerId, "trauma", true);
        }

        public void GoToHospital(ulong playerId)
        {
            var player = Server.PlayerSystem.GetById(playerId);
            if (player == null)
                return;
            float x, y, z;
            lock (_lock)
            {
                if (!_downed.TryGetValue(playerId, out var down))
                    return;
                if ((DateTime.UtcNow - down.Since).TotalSeconds < _config.Medical.DownedSeconds - 2)
                    return;
                _downed.Remove(playerId);
                (x, y, z) = (down.X, down.Y, down.Z);
            }

            var (name, hx, hy, hz) = Nearest(x, y, z);
            var economy = GameServices.Economy;
            long paid = 0;
            if (economy != null && _config.Medical.Bill > 0)
            {
                var amount = Math.Min(_config.Medical.Bill, economy.GetBalance(playerId));
                if (amount > 0 && economy.Debit(playerId, amount, "Hospital bill"))
                    paid = amount;
            }
            var note = paid > 0
                ? $"You woke up at {name}. Hospital bill: {paid} eddies."
                : $"You woke up at {name}.";
            _logger.Info($"{player.Username} went to {name} (paid {paid}).");
            Cyberpunk.Rpc.Client.Plugins.MedicalClient.Revive(playerId, hx, hy, hz, note);
        }

        public bool ReviveInPlace(ulong playerId, string by)
        {
            lock (_lock)
            {
                if (!_downed.Remove(playerId))
                    return false;
            }
            var player = Server.PlayerSystem.GetById(playerId);
            if (player == null)
                return false;
            var pos = player.MovementComponent.Position;
            _logger.Info($"{player.Username} was revived by {by}.");
            Cyberpunk.Rpc.Client.Plugins.MedicalClient.Revive(playerId, pos.X, pos.Y, pos.Z, $"{by} got you back on your feet.");
            return true;
        }

        private (string Name, float X, float Y, float Z) Nearest(float x, float y, float z)
        {
            var hospitals = _config.Medical.Hospitals;
            if (hospitals.Count == 0)
            {
                var s = _config.Start ?? new StartPoint();
                return ("the clinic", s.X, s.Y, s.Z);
            }
            var best = hospitals
                .OrderBy(h => (h.X - x) * (h.X - x) + (h.Y - y) * (h.Y - y) + (h.Z - z) * (h.Z - z))
                .First();
            return (string.IsNullOrWhiteSpace(best.Name) ? "the hospital" : best.Name, best.X, best.Y, best.Z);
        }
    }
}
