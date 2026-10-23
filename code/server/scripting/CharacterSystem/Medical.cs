using CyberpunkSdk;
using CyberpunkSdk.Systems;

namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class MedicalServer
    {
        public static partial void Flatlined_Impl(ulong playerId, float x, float y, float z) =>
            CharacterSystem.Plugin.Instance.Medical.Flatlined(playerId, x, y, z);
    }
}

namespace CharacterSystem
{
    /// <summary>
    /// A player flatlined. Their game kept them alive at the last moment (no death
    /// screen, no reload) and asks where to wake up: the nearest hospital in
    /// character.json (Medical), or the start point, minus the bill.
    /// </summary>
    internal sealed class MedicalService
    {
        private readonly Config _config;
        private readonly Logger _logger = new("Medical");
        private readonly Dictionary<ulong, DateTime> _last = new();

        public MedicalService(Config config)
        {
            _config = config;
        }

        public void Flatlined(ulong playerId, float x, float y, float z)
        {
            var player = Server.PlayerSystem.GetById(playerId);
            if (player == null)
                return;
            lock (_last)
            {
                // One trip per flatline, however many times the game asks.
                if (_last.TryGetValue(playerId, out var when) && (DateTime.UtcNow - when).TotalSeconds < 10)
                    return;
                _last[playerId] = DateTime.UtcNow;
            }

            var (name, hx, hy, hz) = Nearest(x, y, z);

            var economy = GameServices.Economy;
            long paid = 0;
            if (economy != null && _config.Medical.Bill > 0)
            {
                var amount = Math.Min(_config.Medical.Bill, economy.GetBalance(playerId));
                if (amount > 0 && economy.Debit(playerId, amount, "Trauma bill"))
                    paid = amount;
            }

            var note = paid > 0
                ? $"Flatlined. You woke up at {name}. Trauma bill: {paid} eddies."
                : $"Flatlined. You woke up at {name}.";
            _logger.Info($"{player.Username} flatlined, sent to {name} (paid {paid}).");
            Cyberpunk.Rpc.Client.Plugins.MedicalClient.Revive(playerId, hx, hy, hz, note);
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
