using System.Text.Json;

namespace CharacterSystem
{
    /// <summary>
    /// Every price on the server, in one file: config/prices.json.
    /// Edit it and restart the server. Created with defaults the first time.
    /// </summary>
    public class Prices
    {
        /// <summary>Multiplies every shop price in the game (gun shops, clothing, food, ripperdocs...). 1 = the game's own prices.</summary>
        public float ShopMultiplier { get; set; } = 1.0f;

        /// <summary>
        /// Extra multiplier per kind of item, on top of ShopMultiplier.
        /// Kinds: Weapon, Clothing, Cyberware, Consumable, Gadget, General, Part, WeaponMod.
        /// </summary>
        public Dictionary<string, float> CategoryMultipliers { get; set; } = new()
        {
            ["Weapon"] = 1.0f,
            ["Clothing"] = 1.0f,
            ["Cyberware"] = 1.0f,
            ["Consumable"] = 1.0f,
            ["Gadget"] = 1.0f,
            ["General"] = 1.0f,
            ["Part"] = 1.0f,
            ["WeaponMod"] = 1.0f,
        };

        /// <summary>
        /// A fixed price for one item, by its record name, e.g. "Items.Preset_Unity_Default": 2500.
        /// Overrides the multipliers for that item.
        /// </summary>
        public Dictionary<string, long> ItemPrices { get; set; } = new();

        /// <summary>What the dealership sells and for how much.</summary>
        public List<CarOffer> Cars { get; set; } = new Dealership().Cars;

        /// <summary>Cyberware tiers: capacity, best implant quality, and price.</summary>
        public List<CyberwareTier> CyberwareTiers { get; set; } = new Config().CyberwareTiers;

        public static Prices Load(string serverRoot, Config config, Action<string> logError)
        {
            var path = Path.Combine(serverRoot, "config", "prices.json");
            var options = new JsonSerializerOptions { WriteIndented = true };
            try
            {
                if (File.Exists(path))
                {
                    var loaded = JsonSerializer.Deserialize<Prices>(File.ReadAllText(path));
                    if (loaded != null)
                    {
                        // New settings show up in the file with their defaults.
                        File.WriteAllText(path, JsonSerializer.Serialize(loaded, options));
                        return loaded;
                    }
                }

                // First run: start from what character.json already had.
                var prices = new Prices
                {
                    Cars = config.Dealership.Cars,
                    CyberwareTiers = config.CyberwareTiers,
                };
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, JsonSerializer.Serialize(prices, options));
                return prices;
            }
            catch (Exception ex)
            {
                logError($"Could not read {path}, using defaults: {ex.Message}");
                return new Prices { Cars = config.Dealership.Cars, CyberwareTiers = config.CyberwareTiers };
            }
        }
    }
}
