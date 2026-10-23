using System.Security.Cryptography;
using System.Text;
using CyberpunkSdk;
using EmbedIO;
using EmbedIO.Routing;

namespace AccountSystem;

// Request bodies are read with RequestJson (property names ignore case).
public class LoginRequest
{
    public string? Code { get; set; }
}

public class CharacterRequest
{
    public string? Name { get; set; }
}

public class BanRequest
{
    public string? Reason { get; set; }
}

public record InfoDto(
    string ServerName,
    string Description,
    string DiscordInvite,
    string DiscordImageKey,
    string Tags,
    int PlayersOnline,
    int MaxPlayers,
    bool LoginRequired,
    bool ModpackRequired,
    string DiscordClientId,
    string DiscordRedirectUri,
    string DiscordScopes,
    string ModpackFingerprint,
    int ModpackFiles,
    LauncherContent Launcher);

public record SessionDto(string Token, DateTime ExpiresUtc, string DiscordName, List<string> Characters, int MaxCharacters);

public record MeDto(string DiscordName, List<string> Characters, int MaxCharacters, string? OnlineAs);

/// <summary>Answer to a name check or reservation. Always sent with status 200, so the game can read it simply.</summary>
public record NameDto(bool Ok, string Message, string Name);

public record AccountDto(string DiscordId, string DiscordName, List<string> Characters, bool Banned, string? BanReason, DateTime CreatedUtc, DateTime LastLoginUtc);

/// <summary>
/// Served under /api/v1/plugins/account. The launcher uses:
///   GET  /info                  server name, Discord app id, modpack fingerprint
///   POST /login                 {"code": "..."} from Discord → session token
///   GET  /me                    (Bearer token) who you're logged in as and your characters
/// The game's character creator uses (Bearer token):
///   GET  /name-check?name=..    is this name free for me?        → {"ok", "message", "name"}
///   POST /characters            {"name": "..."} reserve it for me → {"ok", "message", "name"}
///   GET  /modpack               list of every mod file with its SHA-256
///   GET  /modpack/file?path=..  download one modpack file
/// Admins (X-Admin-Key header):
///   GET  /accounts
///   POST /accounts/{discordId}/ban    {"reason": "..."}
///   POST /accounts/{discordId}/unban
///   POST /modpack/reload        re-read the modpack folder after changing it
/// </summary>
internal class AccountController : PluginWebApiController
{
    private readonly Plugin _plugin;

    internal AccountController(Plugin plugin)
    {
        _plugin = plugin;
    }

    // ---------------------------------------------------------------- launcher

    [Route(HttpVerbs.Get, "/info")]
    public InfoDto Info()
    {
        var manifest = _plugin.Modpack.Manifest;
        return new InfoDto(
            _plugin.Config.ServerName,
            _plugin.Config.Description,
            _plugin.Config.DiscordInvite,
            _plugin.Config.DiscordImageKey,
            _plugin.ServerTags(),
            _plugin.OnlineCount,
            _plugin.MaxPlayers(),
            _plugin.Config.RequireLogin,
            _plugin.Config.EnforceModpack,
            _plugin.Config.DiscordClientId,
            _plugin.Config.DiscordRedirectUri,
            _plugin.Discord.Scopes,
            manifest.Fingerprint,
            manifest.Entries.Count,
            _plugin.Launcher.Get());
    }

    [Route(HttpVerbs.Post, "/login")]
    public async Task<SessionDto> Login()
    {
        if (!_plugin.Discord.Configured)
            throw HttpException.InternalServerError("Discord login isn't set up on this server yet.");

        var body = await RequestJson.ReadAsync<LoginRequest>(HttpContext);
        if (string.IsNullOrWhiteSpace(body?.Code))
            throw HttpException.BadRequest("Missing login code.");

        var (user, error) = await _plugin.Discord.ExchangeAsync(body.Code.Trim());
        if (user == null)
            throw HttpException.Forbidden(error ?? "Login failed.");

        var account = _plugin.Store.Upsert(user.Id, user.Name);
        if (account.Banned)
            throw HttpException.Forbidden("You are banned from this server" + (account.BanReason != null ? $": {account.BanReason}" : "."));

        var token = _plugin.Store.CreateSession(account.DiscordId, TimeSpan.FromHours(Math.Max(1, _plugin.Config.SessionHours)), out var expires);
        return new SessionDto(token, expires, account.DiscordName, _plugin.Store.CharactersOf(account.DiscordId), MaxCharacters);
    }

    [Route(HttpVerbs.Get, "/me")]
    public MeDto Me()
    {
        var account = RequireSession();
        return new MeDto(account.DiscordName, _plugin.Store.CharactersOf(account.DiscordId), MaxCharacters, _plugin.OnlineCharacterOf(account.DiscordId));
    }

    [Route(HttpVerbs.Get, "/name-check")]
    public NameDto CheckName()
    {
        var name = (HttpContext.GetRequestQueryData()["name"] ?? "").Trim();
        var account = _plugin.AccountForToken(HttpContext.Request.Headers["Authorization"]);
        if (account == null)
            return new NameDto(false, "Not logged in. Start the game from the server launcher.", name);

        var (ok, _, message) = _plugin.CheckNameFor(account, name);
        return new NameDto(ok, message, name);
    }

    [Route(HttpVerbs.Post, "/characters")]
    public async Task<NameDto> ReserveName()
    {
        CharacterRequest? body = null;
        try { body = await RequestJson.ReadAsync<CharacterRequest>(HttpContext); }
        catch { /* treated as an empty name below */ }
        var name = (body?.Name ?? "").Trim();

        var account = _plugin.AccountForToken(HttpContext.Request.Headers["Authorization"]);
        if (account == null)
            return new NameDto(false, "Not logged in. Start the game from the server launcher.", name);

        var (ok, yours, message) = _plugin.CheckNameFor(account, name);
        if (!ok)
            return new NameDto(false, message, name);
        if (yours)
            return new NameDto(true, "Reserved for you.", name);

        return _plugin.Store.ClaimCharacter(account.DiscordId, name, _plugin.Config.MaxCharactersPerAccount) switch
        {
            ClaimResult.Claimed or ClaimResult.AlreadyYours => new NameDto(true, "Reserved for you.", name),
            ClaimResult.TooMany => new NameDto(false, "You already have the most characters this server allows.", name),
            _ => new NameDto(false, "That name was just taken.", name),
        };
    }

    private int MaxCharacters => Math.Max(1, _plugin.Config.MaxCharactersPerAccount);

    [Route(HttpVerbs.Get, "/modpack")]
    public ModpackManifest Manifest() => _plugin.Modpack.Manifest;

    [Route(HttpVerbs.Get, "/modpack/file")]
    public async Task DownloadFile()
    {
        var path = HttpContext.GetRequestQueryData()["path"] ?? "";
        var full = _plugin.Modpack.FileFor(path);
        if (full == null || !File.Exists(full))
            throw HttpException.NotFound("Not part of the modpack.");

        HttpContext.Response.ContentType = "application/octet-stream";
        HttpContext.Response.ContentLength64 = new FileInfo(full).Length;
        await using var source = File.OpenRead(full);
        // No compression: the length is announced up front, and a compressed
        // body wouldn't match it, so the launcher would see the download cut off.
        await using var target = HttpContext.OpenResponseStream(buffered: false, preferCompression: false);
        await source.CopyToAsync(target);
    }

    // ---------------------------------------------------------------- admin

    [Route(HttpVerbs.Get, "/accounts")]
    public List<AccountDto> Accounts()
    {
        RequireAdminKey();
        return _plugin.Store.All()
            .Select(a => new AccountDto(a.DiscordId, a.DiscordName, _plugin.Store.CharactersOf(a.DiscordId), a.Banned, a.BanReason, a.CreatedUtc, a.LastLoginUtc))
            .ToList();
    }

    [Route(HttpVerbs.Post, "/accounts/{discordId}/ban")]
    public async Task<AccountDto> Ban(string discordId) => await SetBanned(discordId, true);

    [Route(HttpVerbs.Post, "/accounts/{discordId}/unban")]
    public async Task<AccountDto> Unban(string discordId) => await SetBanned(discordId, false);

    [Route(HttpVerbs.Post, "/modpack/reload")]
    public object ReloadModpack()
    {
        RequireAdminKey();
        var manifest = _plugin.Modpack.Reload();
        return new { files = manifest.Entries.Count, fingerprint = manifest.Fingerprint };
    }

    private async Task<AccountDto> SetBanned(string discordId, bool banned)
    {
        RequireAdminKey();

        BanRequest? body = null;
        try { body = await RequestJson.ReadAsync<BanRequest>(HttpContext); }
        catch { /* a missing body is fine */ }

        if (!_plugin.Store.SetBanned(discordId, banned, body?.Reason?.Trim()))
            throw HttpException.NotFound("No account with that Discord ID.");

        var a = _plugin.Store.Get(discordId)!;
        return new AccountDto(a.DiscordId, a.DiscordName, _plugin.Store.CharactersOf(a.DiscordId), a.Banned, a.BanReason, a.CreatedUtc, a.LastLoginUtc);
    }

    // ---------------------------------------------------------------- checks

    private Account RequireSession()
    {
        var account = _plugin.AccountForToken(HttpContext.Request.Headers["Authorization"]);
        if (account == null)
            throw HttpException.Unauthorized("Not logged in, or your login expired.");
        return account;
    }

    private void RequireAdminKey()
    {
        var expected = _plugin.Config.AdminKey;
        if (string.IsNullOrEmpty(expected))
            throw HttpException.Forbidden("Admin endpoints are off. Set AdminKey in config/account.json.");

        var given = HttpContext.Request.Headers["X-Admin-Key"] ?? "";
        if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(given), Encoding.UTF8.GetBytes(expected)))
            throw HttpException.Unauthorized("Wrong or missing X-Admin-Key.");
    }
}
