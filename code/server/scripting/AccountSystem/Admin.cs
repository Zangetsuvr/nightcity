using System.Text.Json;
using AccountSystem;
using CyberpunkSdk;
using CyberpunkSdk.Systems;

namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class AdminServer
    {
        public static partial void OpenPanel_Impl(ulong playerId) => Admins.Instance.OpenPanel(playerId);
        public static partial void SetAdmin_Impl(ulong playerId, string character, bool admin) => Admins.Instance.SetAdmin(playerId, character, admin);
        public static partial void Kick_Impl(ulong playerId, string character, string reason) => Admins.Instance.Kick(playerId, character, reason);
        public static partial void Ban_Impl(ulong playerId, string character, string reason) => Admins.Instance.Ban(playerId, character, reason);
        public static partial void Heal_Impl(ulong playerId, string character) => Admins.Instance.Heal(playerId, character);
        public static partial void GoTo_Impl(ulong playerId, string character) => Admins.Instance.GoTo(playerId, character);
        public static partial void Bring_Impl(ulong playerId, string character) => Admins.Instance.Bring(playerId, character);
        public static partial void TeleportSelf_Impl(ulong playerId, float x, float y, float z) => Admins.Instance.TeleportSelf(playerId, x, y, z);
        public static partial void AddPlace_Impl(ulong playerId, string name, float x, float y, float z) => Admins.Instance.AddPlace(playerId, name, x, y, z);
        public static partial void RemovePlace_Impl(ulong playerId, string name) => Admins.Instance.RemovePlace(playerId, name);
    }
}

namespace AccountSystem
{
    public class AdminPlace
    {
        public string Name { get; set; } = "";
        public float X { get; set; }
        public float Y { get; set; }
        public float Z { get; set; }
    }

    /// <summary>config/admins.json</summary>
    public class AdminFile
    {
        /// <summary>
        /// Who's an admin: Discord user names or Discord IDs. Put your own Discord
        /// name here once; after that, grant admin from the in-game panel (/admin).
        /// </summary>
        public List<string> Admins { get; set; } = new();

        /// <summary>Places admins can teleport to. Add one in game with /addplace Name.</summary>
        public List<AdminPlace> Places { get; set; } = new();
    }

    /// <summary>
    /// Server admins and the in-game admin panel (/admin in chat). Every action
    /// is checked here; a game that isn't an admin's is refused.
    /// </summary>
    internal sealed class Admins
    {
        public static readonly Admins Instance = new();

        private readonly Logger _logger = new("Admin");
        private readonly object _lock = new();
        private AdminFile _file = new();
        private string _path = "";

        private Admins() { }

        public void Load(string serverRoot)
        {
            _path = Path.Combine(serverRoot, "config", "admins.json");
            try
            {
                if (File.Exists(_path))
                    _file = JsonSerializer.Deserialize<AdminFile>(File.ReadAllText(_path)) ?? new AdminFile();
                Save();
                if (_file.Admins.Count == 0)
                    _logger.Warn($"No admins yet. Add your Discord name to {_path} and restart, then use /admin in game.");
            }
            catch (Exception ex)
            {
                _logger.Error($"Could not read {_path}: {ex.Message}. Nobody is an admin until it's fixed.");
                _file = new AdminFile();
            }
        }

        private void Save()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllText(_path, JsonSerializer.Serialize(_file, new JsonSerializerOptions { WriteIndented = true }));
        }

        private static Plugin Accounts => Plugin.Instance;

        private Account? AccountOf(string character)
        {
            var owner = Accounts.Store.OwnerOf(character);
            return owner == null ? null : Accounts.Store.Get(owner);
        }

        private bool IsAdminAccount(Account? account)
        {
            if (account == null)
                return false;
            lock (_lock)
            {
                return _file.Admins.Any(a => string.Equals(a.Trim(), account.DiscordId, StringComparison.OrdinalIgnoreCase)
                                          || string.Equals(a.Trim(), account.DiscordName, StringComparison.OrdinalIgnoreCase));
            }
        }

        private bool IsAdmin(ulong playerId)
        {
            var player = Server.PlayerSystem.GetById(playerId);
            return player != null && IsAdminAccount(AccountOf(player.Username));
        }

        /// <summary>The admin, or null after telling a non-admin no.</summary>
        private CyberpunkSdk.Game.Player? Admin(ulong playerId)
        {
            var player = Server.PlayerSystem.GetById(playerId);
            if (player == null)
                return null;
            if (!IsAdminAccount(AccountOf(player.Username)))
            {
                player.SendChat("SERVER", "You don't have access to that.");
                _logger.Warn($"{player.Username} tried an admin action without being an admin.");
                return null;
            }
            return player;
        }

        private CyberpunkSdk.Game.Player? Online(string character) =>
            Server.PlayerSystem.PlayerIds
                .Select(id => Server.PlayerSystem.GetById(id))
                .FirstOrDefault(p => p != null && string.Equals(p.Username, character, StringComparison.OrdinalIgnoreCase));

        private void Log(CyberpunkSdk.Game.Player admin, string what) =>
            _logger.Info($"[admin] {admin.Username}: {what}");

        // ---------------------------------------------------------------- panel

        public void OpenPanel(ulong playerId)
        {
            if (Admin(playerId) == null)
                return;
            SendPanel(playerId);
        }

        private void SendPanel(ulong playerId)
        {
            var parts = new List<string>();
            foreach (var id in Server.PlayerSystem.PlayerIds)
            {
                var p = Server.PlayerSystem.GetById(id);
                if (p == null)
                    continue;
                var account = AccountOf(p.Username);
                parts.Add(Record("P", p.Username, account?.DiscordName ?? "", IsAdminAccount(account) ? "1" : "0", id == playerId ? "1" : "0"));
            }
            lock (_lock)
            {
                foreach (var place in _file.Places)
                    parts.Add(Record("L", place.Name, F(place.X), F(place.Y), F(place.Z)));
            }
            Cyberpunk.Rpc.Client.Plugins.AdminClient.ShowPanel(playerId, string.Join("^", parts));
        }

        // ---------------------------------------------------------------- actions on players

        public void SetAdmin(ulong playerId, string character, bool admin)
        {
            var me = Admin(playerId);
            if (me == null)
                return;
            var account = AccountOf(character);
            if (account == null)
            {
                me.SendChat("SERVER", $"No account owns '{character}'.");
                return;
            }
            lock (_lock)
            {
                _file.Admins.RemoveAll(a => string.Equals(a.Trim(), account.DiscordId, StringComparison.OrdinalIgnoreCase)
                                         || string.Equals(a.Trim(), account.DiscordName, StringComparison.OrdinalIgnoreCase));
                if (admin)
                    _file.Admins.Add(account.DiscordId);
                Save();
            }
            Log(me, $"{(admin ? "made" : "removed")} admin: {character} ({account.DiscordName})");
            me.SendChat("SERVER", admin ? $"{character} is now an admin." : $"{character} is no longer an admin.");
            Online(character)?.SendChat("SERVER", admin ? "You're now an admin. Type /admin to open the panel." : "You're no longer an admin.");
            SendPanel(playerId);
        }

        public void Kick(ulong playerId, string character, string reason)
        {
            var me = Admin(playerId);
            var target = Online(character);
            if (me == null || target == null)
                return;
            var why = string.IsNullOrWhiteSpace(reason) ? "Kicked by an admin." : reason.Trim();
            target.SendChat("SERVER", $"You were kicked: {why}");
            Log(me, $"kicked {character}: {why}");
            Cyberpunk.Rpc.Client.Plugins.AdminClient.Kicked(target.Id, why);
            target.Kick();
            me.SendChat("SERVER", $"Kicked {character}.");
        }

        public void Ban(ulong playerId, string character, string reason)
        {
            var me = Admin(playerId);
            if (me == null)
                return;
            var account = AccountOf(character);
            if (account == null)
            {
                me.SendChat("SERVER", $"No account owns '{character}'.");
                return;
            }
            if (IsAdminAccount(account))
            {
                me.SendChat("SERVER", "Remove their admin first.");
                return;
            }
            var why = string.IsNullOrWhiteSpace(reason) ? "Banned by an admin." : reason.Trim();
            Accounts.Store.SetBanned(account.DiscordId, true, why);
            Log(me, $"banned {character} ({account.DiscordName}): {why}");
            var target = Online(character);
            if (target != null)
            {
                target.SendChat("SERVER", $"You were banned: {why}");
                Cyberpunk.Rpc.Client.Plugins.AdminClient.Kicked(target.Id, $"Banned: {why}");
                target.Kick();
            }
            me.SendChat("SERVER", $"Banned {character} ({account.DiscordName}). Unban from the server's web admin.");
        }

        public void Heal(ulong playerId, string character)
        {
            var me = Admin(playerId);
            var target = Online(character);
            if (me == null || target == null)
                return;
            Cyberpunk.Rpc.Client.Plugins.AdminClient.Heal(target.Id, $"Healed by an admin.");
            Log(me, $"healed {character}");
        }

        public void GoTo(ulong playerId, string character)
        {
            var me = Admin(playerId);
            var target = Online(character);
            if (me == null || target == null)
                return;
            var pos = target.MovementComponent.Position;
            Cyberpunk.Rpc.Client.Plugins.AdminClient.Teleport(playerId, pos.X + 1.5f, pos.Y, pos.Z);
            Log(me, $"went to {character}");
        }

        public void Bring(ulong playerId, string character)
        {
            var me = Admin(playerId);
            var target = Online(character);
            if (me == null || target == null)
                return;
            var pos = me.MovementComponent.Position;
            Cyberpunk.Rpc.Client.Plugins.AdminClient.Teleport(target.Id, pos.X + 1.5f, pos.Y, pos.Z);
            target.SendChat("SERVER", "An admin brought you to them.");
            Log(me, $"brought {character}");
        }

        // ---------------------------------------------------------------- places

        public void TeleportSelf(ulong playerId, float x, float y, float z)
        {
            var me = Admin(playerId);
            if (me == null)
                return;
            Cyberpunk.Rpc.Client.Plugins.AdminClient.Teleport(playerId, x, y, z);
            Log(me, $"teleported to {F(x)}, {F(y)}, {F(z)}");
        }

        public void AddPlace(ulong playerId, string name, float x, float y, float z)
        {
            var me = Admin(playerId);
            name = (name ?? "").Trim();
            if (me == null || name.Length == 0)
                return;
            lock (_lock)
            {
                _file.Places.RemoveAll(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
                _file.Places.Add(new AdminPlace { Name = name, X = x, Y = y, Z = z });
                Save();
            }
            me.SendChat("SERVER", $"Saved '{name}' to the admin teleport list.");
            Log(me, $"added place {name}");
        }

        public void RemovePlace(ulong playerId, string name)
        {
            var me = Admin(playerId);
            if (me == null)
                return;
            lock (_lock)
            {
                _file.Places.RemoveAll(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
                Save();
            }
            Log(me, $"removed place {name}");
            SendPanel(playerId);
        }

        private static string F(float v) => v.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

        private static string Record(params string[] fields) =>
            string.Join("~", fields.Select(f => (f ?? "").Replace("~", "-").Replace("^", "-")));
    }
}
