using System.Text.Json;

namespace AccountSystem
{
    /// <summary>
    /// Settings read from config/account.json next to the server. Created with
    /// these defaults on first start; fill in the Discord values before opening
    /// the server.
    /// </summary>
    public class Config
    {
        /// <summary>Refuse anyone who didn't log in through the launcher. Turn off only for local testing.</summary>
        public bool RequireLogin { get; set; } = true;

        /// <summary>Refuse anyone whose mods don't exactly match the modpack.</summary>
        public bool EnforceModpack { get; set; } = true;

        /// <summary>Shown in the launcher's server list and in Discord status.</summary>
        public string ServerName { get; set; } = "Night City Roleplay";

        /// <summary>One or two sentences shown under the name in the launcher.</summary>
        public string Description { get; set; } = "";

        /// <summary>
        /// Invite link to your Discord server (e.g. https://discord.gg/abc123). Shown in the
        /// launcher and as a "Join the Discord" button on players' Discord status.
        /// </summary>
        public string DiscordInvite { get; set; } = "";

        /// <summary>
        /// Name of the image uploaded under Rich Presence → Art Assets in the Discord
        /// Developer Portal, shown on players' Discord status. Empty = no image.
        /// </summary>
        public string DiscordImageKey { get; set; } = "logo";

        /// <summary>From the Discord Developer Portal (your application → OAuth2).</summary>
        public string DiscordClientId { get; set; } = "";

        /// <summary>Keep this secret. Never put it in the launcher.</summary>
        public string DiscordClientSecret { get; set; } = "";

        /// <summary>
        /// Must exactly match a redirect added in the Discord Developer Portal.
        /// The launcher listens on this address during login.
        /// </summary>
        public string DiscordRedirectUri { get; set; } = "http://127.0.0.1:53134/callback";

        /// <summary>
        /// Only members of this Discord server (guild) may log in. Empty = anyone
        /// with a Discord account. Right-click your server in Discord → Copy Server ID.
        /// </summary>
        public string RequiredGuildId { get; set; } = "";

        /// <summary>How many characters (names) one Discord account may have.</summary>
        public int MaxCharactersPerAccount { get; set; } = 1;

        /// <summary>How long a launcher login lasts before the player must log in again.</summary>
        public int SessionHours { get; set; } = 12;

        /// <summary>Accounts, character names and sessions. Relative to the server folder.</summary>
        public string DatabaseFile { get; set; } = "data/accounts.db";

        /// <summary>
        /// The modpack: a copy of every mod file players must have, laid out like
        /// the game folder (e.g. modpack/archive/pc/mod/..., modpack/red4ext/...).
        /// </summary>
        public string ModpackFolder { get; set; } = "data/modpack";

        /// <summary>
        /// Game folders that count as "mods". Every file in them must be in the
        /// modpack; anything else is set aside by the launcher and refused here.
        /// </summary>
        public List<string> ModRoots { get; set; } = new()
        {
            "archive/pc/mod",
            "bin/x64/plugins",
            "red4ext",
            "r6/scripts",
            "r6/tweaks",
            "r6/config/redsUserHints",
            "mods",
        };

        /// <summary>
        /// Single files that mod loaders and injectors use. If a player has one
        /// that isn't in the modpack, it's set aside too.
        /// </summary>
        public List<string> ModFiles { get; set; } = new()
        {
            "bin/x64/version.dll",
            "bin/x64/winmm.dll",
            "bin/x64/d3d11.dll",
            "bin/x64/dxgi.dll",
            "bin/x64/dinput8.dll",
            "bin/x64/global.ini",
            // redscript (the script compiler that replaces the game's own)
            "engine/tools/scc.exe",
            "engine/tools/scc_lib.dll",
            "engine/config/base/scripts.ini",
            "r6/config/cybercmd/scc.toml",
            // Input Loader
            "engine/config/platform/pc/input_loader.ini",
            "r6/cache/inputContexts.xml",
            "r6/cache/inputUserMappings.xml",
        };

        // Entries every server needs for the multiplayer mod's own requirements.
        // Added to older account.json files that were written before they existed.
        private static readonly string[] RequiredRoots = { "r6/config/redsUserHints" };
        private static readonly string[] RequiredFiles =
        {
            "engine/tools/scc.exe",
            "engine/tools/scc_lib.dll",
            "engine/config/base/scripts.ini",
            "r6/config/cybercmd/scc.toml",
            "engine/config/platform/pc/input_loader.ini",
            "r6/cache/inputContexts.xml",
            "r6/cache/inputUserMappings.xml",
        };

        private void AddRequiredEntries()
        {
            foreach (var root in RequiredRoots)
                if (!ModRoots.Contains(root, StringComparer.OrdinalIgnoreCase))
                    ModRoots.Add(root);
            foreach (var file in RequiredFiles)
                if (!ModFiles.Contains(file, StringComparer.OrdinalIgnoreCase))
                    ModFiles.Add(file);
        }

        /// <summary>
        /// Files mods create while running (logs, settings, caches). Ignored on
        /// both sides. "*" matches within a folder, "**" across folders.
        /// Keep this short: an ignored file could hide anything.
        /// </summary>
        public List<string> Ignore { get; set; } = new()
        {
            "**/*.log",
            "**/logs/**",
            "**/*.sqlite3",
            "bin/x64/plugins/cyber_engine_tweaks/**/*.json",
            "bin/x64/plugins/cyber_engine_tweaks/*.ini",
            "red4ext/plugins/CyberpunkMP/session.json",
            "red4ext/plugins/CyberpunkMP/Rpc/**",
        };

        /// <summary>Secret for admin endpoints (X-Admin-Key header). Empty = admin endpoints off.</summary>
        public string AdminKey { get; set; } = "";

        public static Config Load(string serverRoot, Action<string> logError)
        {
            var dir = Path.Combine(serverRoot, "config");
            var path = Path.Combine(dir, "account.json");
            try
            {
                Directory.CreateDirectory(dir);
                if (File.Exists(path))
                {
                    var loaded = JsonSerializer.Deserialize<Config>(File.ReadAllText(path));
                    if (loaded != null)
                    {
                        loaded.AddRequiredEntries();
                        return loaded;
                    }
                }

                var defaults = new Config();
                File.WriteAllText(path, JsonSerializer.Serialize(defaults, new JsonSerializerOptions { WriteIndented = true }));
                return defaults;
            }
            catch (Exception ex)
            {
                // A broken config must not open the server to everyone: keep the
                // safe defaults (login and modpack required).
                logError($"Could not read {path}, using safe defaults: {ex.Message}");
                return new Config();
            }
        }
    }
}
