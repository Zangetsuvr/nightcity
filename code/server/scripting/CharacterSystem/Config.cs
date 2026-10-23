using System.Text.Json;

namespace CharacterSystem
{
    /// <summary>
    /// Settings read from config/character.json next to the server.
    /// The file is created with these defaults the first time the server starts.
    /// </summary>
    /// <summary>A place in the world: position in metres and facing (degrees).</summary>
    public class StartPoint
    {
        public float X { get; set; } = -1720.4f;
        public float Y { get; set; } = -1956.6f;
        public float Z { get; set; } = 62.4f;
        public float Yaw { get; set; } = 0f;
    }

    /// <summary>One item in a starter kit.</summary>
    public class KitItem
    {
        /// <summary>The item's record name, e.g. "Items.Preset_Unity_Default".</summary>
        public string Item { get; set; } = "";
        public int Quantity { get; set; } = 1;
        /// <summary>Put it on / in hand straight away (clothes, the sidearm).</summary>
        public bool Equip { get; set; } = true;

        public KitItem() { }
        public KitItem(string item, int quantity = 1, bool equip = true)
        {
            Item = item;
            Quantity = quantity;
            Equip = equip;
        }
    }

    /// <summary>A cyberware tier: how much chrome you can carry, and the best implants you may install.</summary>
    public class CyberwareTier
    {
        public int Tier { get; set; }
        /// <summary>Cyberware capacity at this tier (replaces the game's own number).</summary>
        public int Capacity { get; set; }
        /// <summary>What it costs to move up to this tier.</summary>
        public long Price { get; set; }
        /// <summary>Best implant quality allowed: Common, Uncommon, Rare, Epic or Legendary.</summary>
        public string MaxQuality { get; set; } = "Common";
    }

    /// <summary>A car the dealership sells.</summary>
    public class CarOffer
    {
        /// <summary>The game's vehicle record, e.g. "Vehicle.v_standard2_archer_hella_player".</summary>
        public string Record { get; set; } = "";
        public string Name { get; set; } = "";
        public long Price { get; set; }

        public CarOffer() { }
        public CarOffer(string record, string name, long price) { Record = record; Name = name; Price = price; }
    }

    public class Dealership
    {
        public string Name { get; set; } = "Night City Motors";
        /// <summary>Where it is. Stand there in game and type /where in chat to get the numbers.</summary>
        public StartPoint Location { get; set; } = new() { X = -1729.0f, Y = -1948.1f, Z = 61.4f };
        public List<CarOffer> Cars { get; set; } = new()
        {
            new("Vehicle.v_standard2_archer_hella_player", "Archer Hella", 9000),
            new("Vehicle.v_standard2_makigai_maimai_player", "Makigai MaiMai", 11000),
            new("Vehicle.v_standard2_villefort_cortes_player", "Villefort Cortes", 16000),
            new("Vehicle.v_standard25_thorton_colby_player", "Thorton Colby", 18000),
            new("Vehicle.v_standard3_thorton_mackinaw_player", "Thorton Mackinaw", 24000),
            new("Vehicle.v_standard25_mahir_supron_player", "Mahir Supron", 27000),
            new("Vehicle.v_standard3_chevalier_emperor_player", "Chevalier Emperor", 35000),
            new("Vehicle.v_sportbike1_yaiba_kusanagi_player", "Yaiba Kusanagi", 42000),
            new("Vehicle.v_sport2_villefort_alvarado_player", "Villefort Alvarado", 55000),
            new("Vehicle.v_sport2_mizutani_shion_player", "Mizutani Shion", 75000),
            new("Vehicle.v_sport2_quadra_type66_player", "Quadra Type-66", 90000),
            new("Vehicle.v_sport1_quadra_turbo_player", "Quadra Turbo-R", 140000),
            new("Vehicle.v_sport1_herrera_outlaw_player", "Herrera Outlaw", 200000),
            new("Vehicle.v_sport1_rayfield_caliburn_player", "Rayfield Caliburn", 350000),
        };
    }

    /// <summary>An extra icon on everyone's map: a gun shop, ripperdoc, clothing store...</summary>
    public class Hospital
    {
        public string Name { get; set; } = "";
        public float X { get; set; }
        public float Y { get; set; }
        public float Z { get; set; }
    }

    public class Medical
    {
        /// <summary>Trauma bill for each flatline. Taken from what you have; never puts you below zero.</summary>
        public long Bill { get; set; } = 250;

        public List<Hospital> Hospitals { get; set; } = new();
    }

    public class MapMarker
    {
        /// <summary>guns, ripperdoc, clothes, food, bar, meds, tech, junk, netrunner, melee, dropoff, blackmarket, car</summary>
        public string Type { get; set; } = "guns";
        public string Name { get; set; } = "";
        public float X { get; set; }
        public float Y { get; set; }
        public float Z { get; set; }
    }

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

        /// <summary>
        /// Where brand-new characters arrive. New characters start in a holding room
        /// (the clean start skips the story), and the server moves them here the
        /// first time they connect. Returning characters stay where they saved.
        /// Null = leave new characters where the game put them.
        /// </summary>
        public StartPoint? Start { get; set; } = new();

        /// <summary>
        /// What a brand-new character is given, by the lifepath picked in the
        /// character creator (Corpo, Nomad or StreetKid). Given once per character,
        /// the first time they connect: whatever the clean start left them carrying
        /// (clothes, weapons, ammo, consumables) is taken away first, so everyone
        /// starts from the same place. Money comes from StartingBalance, not from here.
        /// A lifepath left out (or an empty list) gets nothing and keeps what it had.
        /// </summary>
        public Dictionary<string, List<KitItem>> StarterKits { get; set; } = new(StringComparer.OrdinalIgnoreCase)
        {
            ["Corpo"] = new()
            {
                new("Items.Q000_Corpo_FormalJacket"),
                new("Items.Q000_Corpo_FormalPants"),
                new("Items.Q000_Corpo_FormalShoes"),
                new("Items.Preset_Lexington_Default"),
                new("Ammo.HandgunAmmo", 100, false),
            },
            ["StreetKid"] = new()
            {
                new("Items.Q000_StreetKid_TShirt"),
                new("Items.Q000_StreetKid_Pants"),
                new("Items.Q000_StreetKid_Shoes"),
                new("Items.Preset_Unity_Default"),
                new("Ammo.HandgunAmmo", 100, false),
            },
            ["Nomad"] = new()
            {
                new("Items.Q000_Nomad_TShirt"),
                new("Items.Q000_Nomad_Pants"),
                new("Items.Q000_Nomad_Boots"),
                new("Items.Q000_Nomad_Vest"),
                new("Items.Preset_Nova_Default"),
                new("Ammo.HandgunAmmo", 100, false),
            },
        };

        /// <summary>
        /// Cyberware tiers, bought one after another at a ripperdoc. Each tier sets
        /// how much cyberware a character can carry and the best quality of implant
        /// they may install. Everyone starts at tier 1.
        /// </summary>
        public List<CyberwareTier> CyberwareTiers { get; set; } = new()
        {
            new() { Tier = 1, Capacity = 50, Price = 0, MaxQuality = "Common" },
            new() { Tier = 2, Capacity = 90, Price = 10_000, MaxQuality = "Uncommon" },
            new() { Tier = 3, Capacity = 140, Price = 30_000, MaxQuality = "Rare" },
            new() { Tier = 4, Capacity = 200, Price = 75_000, MaxQuality = "Epic" },
            new() { Tier = 5, Capacity = 280, Price = 150_000, MaxQuality = "Legendary" },
        };

        /// <summary>
        /// Icons everyone sees on the map from the start (the game only shows a shop
        /// once you've been near it). Stand at a shop, type /where in chat, and add
        /// it here with its type.
        /// </summary>
        public List<MapMarker> MapMarkers { get; set; } = new();

        /// <summary>
        /// Flatlining on the server: instead of the game's death screen (which
        /// reloads a save and drops you off the server), you wake up at the nearest
        /// hospital, healed, minus the bill. Stand at a clinic, type /where in chat,
        /// and add it under Hospitals. With none listed, you wake at Start.
        /// </summary>
        public Medical Medical { get; set; } = new();

        /// <summary>The car dealership: where it is and what it sells.</summary>
        public Dealership Dealership { get; set; } = new();

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
                    {
                        // Lifepath names are matched loosely whatever the file did.
                        loaded.StarterKits = new(loaded.StarterKits ?? new(), StringComparer.OrdinalIgnoreCase);
                        // Write it back so settings added in newer versions show up
                        // in the file with their defaults, ready to edit.
                        File.WriteAllText(path, JsonSerializer.Serialize(loaded, new JsonSerializerOptions { WriteIndented = true }));
                        return loaded;
                    }
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
