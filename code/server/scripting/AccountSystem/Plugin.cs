using System.Text.RegularExpressions;
using CyberpunkSdk;
using CyberpunkSdk.Systems;

namespace AccountSystem
{
    /// <summary>
    /// Accounts and the login check.
    ///
    /// Players log in with Discord through the server launcher, which gets a
    /// session token from this plugin's web API, makes their mods match the
    /// modpack, and starts the game. Characters are named in the game's
    /// character creator, which reserves the name here (POST /characters);
    /// the name is stored in that save. When connecting, the game sends
    ///   username = the save's character name
    ///   token    = "&lt;session token&gt;:&lt;mod fingerprint&gt;"
    /// and Authenticate below decides whether they may join.
    /// </summary>
    public class Plugin : IWebApiHook
    {
        public static Plugin Instance { get; set; }

        internal Config Config { get; }
        internal AccountStore Store { get; }
        internal Modpack Modpack { get; }
        internal Discord Discord { get; }

        private readonly Logger _logger = new("Account");

        // Character names currently connected, by player id.
        private readonly object _onlineLock = new();
        private readonly Dictionary<ulong, string> _online = new();

        static Plugin()
        {
            Instance = new Plugin();
        }

        private Plugin()
        {
            var root = AppContext.BaseDirectory;
            Config = Config.Load(root, msg => _logger.Error(msg));

            NativeSqlite.Register();
            Store = new AccountStore(Resolve(root, Config.DatabaseFile));
            Modpack = new Modpack(Resolve(root, Config.ModpackFolder), Config);
            Discord = new Discord(Config, msg => _logger.Warn(msg));

            Admins.Instance.Load(root);

            Authentication.Authenticator = Authenticate;

            Server.PlayerSystem.PlayerJoinEvent += OnPlayerJoin;
            Server.PlayerSystem.PlayerLeftEvent += OnPlayerLeave;
            AppDomain.CurrentDomain.ProcessExit += (_, _) => Store.Dispose();

            var manifest = Modpack.Manifest;
            _logger.Info($"Modpack: {manifest.Entries.Count} files, fingerprint {manifest.Fingerprint[..12]}");
            if (!Config.RequireLogin)
                _logger.Warn("RequireLogin is off: anyone can join under any name. Use this only for testing.");
            else if (!Discord.Configured)
                _logger.Warn("Discord isn't set up in config/account.json, so nobody can log in yet.");
        }

        // ---------------------------------------------------------------- login check

        private AuthResult Authenticate(string username, string token)
        {
            if (!Config.RequireLogin)
                return AuthResult.Accepted;

            // "<session>:<fingerprint>"; the session token itself never contains ':'.
            var split = token.IndexOf(':');
            var sessionToken = split < 0 ? token : token[..split];
            var fingerprint = split < 0 ? "" : token[(split + 1)..];

            var session = Store.FindSession(sessionToken);
            if (session == null)
                return AuthResult.NotLoggedIn;
            if (session.ExpiresUtc < DateTime.UtcNow)
                return AuthResult.SessionExpired;

            var account = Store.Get(session.DiscordId);
            if (account == null)
                return AuthResult.NotLoggedIn;
            if (account.Banned)
                return AuthResult.Banned;

            var name = username.Trim();
            if (name.Length == 0)
                return AuthResult.NoCharacterName;

            var owner = Store.OwnerOf(name);
            if (owner != null && owner != account.DiscordId)
                return AuthResult.NameTaken;
            if (owner == null && CheckCharacterName(name) != null)
                return AuthResult.InvalidName;

            if (Config.EnforceModpack && !string.Equals(fingerprint, Modpack.Fingerprint, StringComparison.OrdinalIgnoreCase))
            {
                _logger.Warn($"{name} (Discord {account.DiscordName}) refused: mods don't match the modpack.");
                return AuthResult.ModsMismatch;
            }

            // One connection per Discord account, whichever character it plays.
            lock (_onlineLock)
            {
                if (_online.Values.Any(n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase)
                                            || Store.OwnerOf(n) == account.DiscordId))
                    return AuthResult.AlreadyOnline;
            }

            // Normally the character creator reserved the name already. If it
            // couldn't (e.g. the server was unreachable then), it's claimed now,
            // last, so a refused login never takes a name.
            if (owner == null)
            {
                switch (Store.ClaimCharacter(account.DiscordId, name, Config.MaxCharactersPerAccount))
                {
                    case ClaimResult.Taken:
                        return AuthResult.NameTaken;
                    case ClaimResult.TooMany:
                        return AuthResult.TooManyCharacters;
                }
            }

            Store.MarkPlayed(name);
            _logger.Info($"{name} (Discord {account.DiscordName}) logged in.");
            return AuthResult.Accepted;
        }

        internal int OnlineCount
        {
            get { lock (_onlineLock) { return _online.Count; } }
        }

        /// <summary>The character this account is playing right now, if connected.</summary>
        internal string? OnlineCharacterOf(string discordId)
        {
            List<string> names;
            lock (_onlineLock) { names = _online.Values.ToList(); }
            return names.FirstOrDefault(n => Store.OwnerOf(n) == discordId);
        }

        /// <summary>Player limit and tags from the server's own config (server.json).</summary>
        internal int MaxPlayers()
        {
            try { return CyberpunkSdk.Internal.IConfig.Get().MaxPlayer; }
            catch { return 0; }
        }

        internal string ServerTags()
        {
            try { return CyberpunkSdk.Internal.IConfig.Get().Tags ?? ""; }
            catch { return ""; }
        }

        private void OnPlayerJoin(ulong id)
        {
            var name = Server.PlayerSystem.GetById(id)?.Username;
            if (name != null)
                lock (_onlineLock) { _online[id] = name; }
        }

        private void OnPlayerLeave(ulong id)
        {
            lock (_onlineLock) { _online.Remove(id); }
        }

        // ---------------------------------------------------------------- helpers for the web API

        /// <summary>The account behind a launcher's "Authorization: Bearer" token, if valid.</summary>
        internal Account? AccountForToken(string? authorizationHeader)
        {
            if (string.IsNullOrEmpty(authorizationHeader) || !authorizationHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                return null;

            var session = Store.FindSession(authorizationHeader["Bearer ".Length..].Trim());
            if (session == null || session.ExpiresUtc < DateTime.UtcNow)
                return null;

            var account = Store.Get(session.DiscordId);
            return account == null || account.Banned ? null : account;
        }

        private static readonly Regex NamePattern = new(@"^[A-Za-z][A-Za-z'\-. ]{1,22}[A-Za-z.]$", RegexOptions.CultureInvariant);
        private static readonly string[] ReservedNames = { "server", "admin", "moderator", "staff", "system", "player" };

        /// <summary>Null if the name is fine, otherwise why it isn't.</summary>
        internal static string? CheckCharacterName(string name)
        {
            if (name.Length < 3 || name.Length > 24)
                return "Names must be 3 to 24 characters.";
            if (!NamePattern.IsMatch(name) || name.Contains("  ") || name.Contains("--") || name.Contains("''"))
                return "Use letters, spaces, apostrophes, hyphens and periods, starting with a letter.";
            if (ReservedNames.Contains(name.ToLowerInvariant()))
                return "That name is reserved.";
            return null;
        }

        /// <summary>
        /// Whether this account may use this name. Ok is true if it's free or
        /// already theirs (Yours tells which); Message is what the player sees.
        /// </summary>
        internal (bool Ok, bool Yours, string Message) CheckNameFor(Account account, string name)
        {
            var problem = CheckCharacterName(name);
            if (problem != null)
                return (false, false, problem);

            var owner = Store.OwnerOf(name);
            if (owner == account.DiscordId)
                return (true, true, "This is one of your characters.");
            if (owner != null)
                return (false, false, "That name is taken.");

            var max = Math.Max(1, Config.MaxCharactersPerAccount);
            if (Store.PlayedCount(account.DiscordId) >= max)
                return (false, false, max == 1
                    ? "You already have a character on this server."
                    : $"You already have {max} characters, the most this server allows.");

            return (true, false, "Available");
        }

        private static string Resolve(string root, string path) =>
            Path.IsPathRooted(path) ? path : Path.Combine(root, path);

        public Func<PluginWebApiController> BuildController()
        {
            return () => new AccountController(this);
        }
    }
}
