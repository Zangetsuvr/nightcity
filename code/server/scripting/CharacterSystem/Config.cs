using System.Text.Json;

namespace CharacterSystem
{
    /// <summary>
    /// Settings read from config/character.json next to the server.
    /// The file is created with these defaults the first time the server starts.
    /// </summary>
    public class Config
    {
        /// <summary>Money a brand-new character starts with.</summary>
        public long StartingBalance { get; set; } = 1000;

        /// <summary>No balance can go above this. Keeps numbers inside what the game can show.</summary>
        public long MaxBalance { get; set; } = 1_000_000_000;

        /// <summary>Largest single payout, purchase or transfer allowed.</summary>
        public long MaxTransaction { get; set; } = 10_000_000;


        /// <summary>
        /// How often every online player's money is re-sent to their game, in seconds.
        /// This undoes any money a player's game added on its own (cheats, vendors).
        /// </summary>
        public float ResyncIntervalSeconds { get; set; } = 10;

        /// <summary>
        /// Flag a player when their game shows at least this many more eddies than
        /// the server gave them (a sign of a money cheat). Small amounts are usually
        /// loot pickups or vendor sales, which are also undone but not flagged.
        /// </summary>
        public long TamperFlagThreshold { get; set; } = 5_000;

        /// <summary>Flag anyone who earns more than this through server payouts in one hour. 0 = off.</summary>
        public long EarningsAlertPerHour { get; set; } = 50_000;

        /// <summary>Refuse payouts past this much earned in one hour. 0 = off.</summary>
        public long EarningsLimitPerHour { get; set; } = 250_000;

        /// <summary>Also freeze the wallet when someone hits the hourly hard limit.</summary>
        public bool FreezeOnEarningsLimit { get; set; } = false;

        /// <summary>Highest Street Cred level.</summary>
        public int MaxLevel { get; set; } = 50;

        /// <summary>
        /// The SQLite database file holding characters and the money log.
        /// Relative to the server folder. Back this file up regularly.
        /// </summary>
        public string DatabaseFile { get; set; } = "data/characters.db";

        /// <summary>Folder for the flags log. Relative to the server folder.</summary>
        public string DataPath { get; set; } = "data";

        /// <summary>
        /// Secret needed to change balances through the admin web API (sent as the
        /// X-Admin-Key header). Empty means changes through the API are switched off.
        /// </summary>
        public string AdminKey { get; set; } = "";

        public static Config Load(string serverRoot, Action<string> logError)
        {
            var dir = Path.Combine(serverRoot, "config");
            var path = Path.Combine(dir, "character.json");
            try
            {
                Directory.CreateDirectory(dir);
                if (File.Exists(path))
                {
                    var loaded = JsonSerializer.Deserialize<Config>(File.ReadAllText(path));
                    if (loaded != null)
                        return loaded;
                }

                var defaults = new Config();
                File.WriteAllText(path, JsonSerializer.Serialize(defaults, new JsonSerializerOptions { WriteIndented = true }));
                return defaults;
            }
            catch (Exception ex)
            {
                logError($"Could not read {path}, using defaults: {ex.Message}");
                return new Config();
            }
        }
    }
}
