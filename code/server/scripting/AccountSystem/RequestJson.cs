using System.Text.Json;
using EmbedIO;

namespace AccountSystem;

/// <summary>
/// Reads a JSON request body. EmbedIO's own reader matches property names
/// case-sensitively, so {"code": ...} would never fill "Code"; this one ignores
/// case. Returns null for an empty or malformed body.
/// </summary>
internal static class RequestJson
{
    private static readonly JsonSerializerOptions Options = new() { PropertyNameCaseInsensitive = true };

    public static async Task<T?> ReadAsync<T>(IHttpContext context) where T : class
    {
        var text = await context.GetRequestBodyAsStringAsync();
        if (string.IsNullOrWhiteSpace(text))
            return null;
        try
        {
            return JsonSerializer.Deserialize<T>(text, Options);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
