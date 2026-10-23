using System.Security.Cryptography;
using System.Text;
using CharacterSystem.Store;
using CyberpunkSdk;
using EmbedIO;
using EmbedIO.Routing;

namespace CharacterSystem;

public record CharacterDto(
    string Name,
    bool Online,
    long Balance,
    int Level,
    long StreetCred,
    Dictionary<string, long> Xp,
    string? Job,
    DateTime FirstSeenUtc,
    DateTime LastSeenUtc,
    long PlaySeconds,
    bool Frozen,
    string? FrozenReason);

// Request bodies are read by EmbedIO's JSON reader, which needs plain classes
// with settable properties (records with constructors don't work there).
public class AdjustRequest
{
    public long Amount { get; set; }
    public string? Reason { get; set; }
}

public record AdjustResult(string Name, long Balance);

public class FreezeRequest
{
    public string? Reason { get; set; }
}

/// <summary>
/// Admin endpoints, served by the server under /api/v1/plugins/character:
///   GET  /                      every character
///   GET  /{name}                one character
///   POST /{name}/balance        {"amount": 500, "reason": "event prize"}  (needs X-Admin-Key)
///   POST /{name}/freeze         {"reason": "..."}  lock their money          (needs X-Admin-Key)
///   POST /{name}/unfreeze       {"reason": "..."}                            (needs X-Admin-Key)
///   GET  /security/flags        recent suspicious events, newest first        (needs X-Admin-Key)
/// </summary>
internal class CharacterController : PluginWebApiController
{
    private readonly Plugin _plugin;

    internal CharacterController(Plugin plugin)
    {
        _plugin = plugin;
    }

    [Route(HttpVerbs.Get, "/")]
    public List<CharacterDto> List()
    {
        return Store().ListAll().Select(ToDto).ToList();
    }

    [Route(HttpVerbs.Get, "/{name}")]
    public CharacterDto Get(string name)
    {
        var record = Store().Snapshot(name);
        if (record == null)
            throw HttpException.NotFound($"No character named '{name}'.");
        return ToDto(record);
    }

    [Route(HttpVerbs.Post, "/{name}/balance")]
    public async Task<AdjustResult> Adjust(string name)
    {
        RequireAdminKey();

        var body = await RequestJson.ReadAsync<AdjustRequest>(HttpContext);
        if (body == null || body.Amount == 0)
            throw HttpException.BadRequest("Send a non-zero \"amount\".");

        var reason = string.IsNullOrWhiteSpace(body.Reason) ? "no reason given" : body.Reason.Trim();
        if (!_plugin.Characters.AdminAdjust(name, body.Amount, reason, out var after))
            throw HttpException.BadRequest("Change refused: unknown character, or the balance would go below 0 or above the limit.");

        return new AdjustResult(name, after);
    }

    [Route(HttpVerbs.Post, "/{name}/freeze")]
    public async Task<CharacterDto> Freeze(string name) => await SetFrozen(name, true);

    [Route(HttpVerbs.Post, "/{name}/unfreeze")]
    public async Task<CharacterDto> Unfreeze(string name) => await SetFrozen(name, false);

    [Route(HttpVerbs.Get, "/security/flags")]
    public List<SecurityFlag> Flags()
    {
        RequireAdminKey();
        return _plugin.Characters.Security.RecentFlags();
    }

    private async Task<CharacterDto> SetFrozen(string name, bool frozen)
    {
        RequireAdminKey();

        FreezeRequest? body = null;
        try { body = await RequestJson.ReadAsync<FreezeRequest>(HttpContext); }
        catch { /* a missing body is fine */ }

        var reason = string.IsNullOrWhiteSpace(body?.Reason) ? "no reason given" : body!.Reason!.Trim();
        if (!_plugin.Characters.SetFrozen(name, frozen, "Admin: " + reason))
            throw HttpException.NotFound($"No character named '{name}'.");

        return Get(name);
    }

    private void RequireAdminKey()
    {
        var expected = _plugin.Config.AdminKey;
        if (string.IsNullOrEmpty(expected))
            throw HttpException.Forbidden("Balance changes are off. Set AdminKey in config/character.json to turn them on.");

        var given = HttpContext.Request.Headers["X-Admin-Key"] ?? "";
        var a = Encoding.UTF8.GetBytes(given);
        var b = Encoding.UTF8.GetBytes(expected);
        if (!CryptographicOperations.FixedTimeEquals(a, b))
            throw HttpException.Unauthorized("Wrong or missing X-Admin-Key.");
    }

    private ICharacterStore Store() => _plugin.Characters.Store;

    private CharacterDto ToDto(CharacterRecord r)
    {
        var cred = r.GetXp(Leveling.StreetCred);
        return new CharacterDto(
            r.DisplayName,
            _plugin.Characters.IsOnline(r.DisplayName),
            r.Balance,
            Leveling.LevelForXp(cred, _plugin.Config.MaxLevel),
            cred,
            new Dictionary<string, long>(r.Xp),
            r.Job,
            r.FirstSeenUtc,
            r.LastSeenUtc,
            r.PlaySeconds,
            r.Frozen,
            r.FrozenReason);
    }
}
