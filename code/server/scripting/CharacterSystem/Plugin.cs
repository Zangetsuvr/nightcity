using CharacterSystem.Store;
using CyberpunkSdk;
using CyberpunkSdk.Systems;

namespace CharacterSystem
{
    /// <summary>
    /// Entry point. The server finds this class by name (CharacterSystem.Plugin)
    /// and runs its static constructor when the plugin loads.
    /// </summary>
    public class Plugin : IWebApiHook
    {
        public static Plugin Instance { get; set; }

        internal Characters Characters { get; }
        internal Config Config { get; }

        private readonly Logger _logger = new("Character");

        static Plugin()
        {
            Instance = new Plugin();
        }

        private Plugin()
        {
            var root = AppContext.BaseDirectory;
            Config = Config.Load(root, msg => _logger.Error(msg));

            var dataDir = Resolve(root, Config.DataPath);
            var databaseFile = Resolve(root, Config.DatabaseFile);

            NativeSqlite.Register();
            var store = new SqliteCharacterStore(databaseFile, msg => _logger.Error(msg));
            _logger.Info($"Characters stored in {databaseFile}");

            var security = new Security(Config, dataDir, msg => _logger.Warn(msg));

            var prices = Prices.Load(root, Config, msg => _logger.Error(msg));
            Characters = new Characters(store, Config, security, prices)
            {
                PushBalance = (id, balance) => Cyberpunk.Rpc.Client.Plugins.CharacterClient.SetBalance(id, balance),
                PushProgress = (id, level, xp, next) => Cyberpunk.Rpc.Client.Plugins.CharacterClient.SetProgress(id, level, xp, next),
                PushCyberware = (id, tier, capacity, quality, next) => Cyberpunk.Rpc.Client.Plugins.CharacterClient.SetCyberware(id, tier, capacity, quality, next),
                PushShopData = (id, data) => Cyberpunk.Rpc.Client.Plugins.CharacterClient.ShopData(id, data),
                PushVehicles = (id, records) => Cyberpunk.Rpc.Client.Plugins.CharacterClient.UnlockVehicles(id, records),
                PushStarterKit = (id, kit) => Cyberpunk.Rpc.Client.Plugins.CharacterClient.GiveStarterKit(id, kit),
                Notify = (id, message) => Server.PlayerSystem.GetById(id)?.SendChat("SERVER", message),
            };

            // Other plugins (jobs, shops, loot) reach money and XP through these.
            GameServices.Economy = Characters;
            GameServices.Progression = Characters;

            Server.PlayerSystem.PlayerJoinEvent += OnPlayerJoin;
            Server.PlayerSystem.PlayerLeftEvent += OnPlayerLeave;

            // Close the database cleanly when the server shuts down.
            AppDomain.CurrentDomain.ProcessExit += (_, _) => store.Dispose();

            Server.Timer.Add(_ => Characters.SyncAll(), Config.ResyncIntervalSeconds);

        }

        private static string Resolve(string root, string path) =>
            Path.IsPathRooted(path) ? path : Path.Combine(root, path);

        private void OnPlayerJoin(ulong id)
        {
            var player = Server.PlayerSystem.GetById(id);
            if (player == null)
                return;

            try
            {
                Characters.OnJoin(id, player.Username);
                _logger.Info($"{player.Username} joined, balance {Characters.GetBalance(id)}");
            }
            catch (Exception ex)
            {
                _logger.Error($"Loading character for {player.Username} failed: {ex}");
            }
        }

        private void OnPlayerLeave(ulong id)
        {
            try
            {
                Characters.OnLeave(id);
            }
            catch (Exception ex)
            {
                _logger.Error($"Saving character for player {id} failed: {ex}");
            }
        }

        public Func<PluginWebApiController> BuildController()
        {
            return () => new CharacterController(this);
        }
    }
}

namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class CharacterServer
    {
        /// <summary>The player's game asks for a fresh copy of its balance and progress.</summary>
        public static partial void RequestSync_Impl(ulong playerId)
        {
            CharacterSystem.Plugin.Instance.Characters.RequestedSync(playerId);
        }

        /// <summary>Move up one cyberware tier (from the ripperdoc screen).</summary>
        public static partial void BuyCyberwareTier_Impl(ulong playerId)
        {
            CharacterSystem.Plugin.Instance.Characters.BuyCyberwareTier(playerId);
        }

        /// <summary>Buy a car at the dealership.</summary>
        public static partial void BuyVehicle_Impl(ulong playerId, string record)
        {
            CharacterSystem.Plugin.Instance.Characters.BuyVehicle(playerId, record);
        }

        /// <summary>The player's game says which lifepath the character was made with.</summary>
        public static partial void ClaimStarterKit_Impl(ulong playerId, int lifepath)
        {
            CharacterSystem.Plugin.Instance.Characters.ClaimStarterKit(playerId, lifepath);
        }

        /// <summary>
        /// The player's game found its eddies had changed since the server's last
        /// update - something other than the server touched their money.
        /// </summary>
        public static partial void ReportLocalBalance_Impl(ulong playerId, long localBalance, long lastFromServer)
        {
            CharacterSystem.Plugin.Instance.Characters.OnLocalBalanceReport(playerId, localBalance, lastFromServer);
        }
    }
}
