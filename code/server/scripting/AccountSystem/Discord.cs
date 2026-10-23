using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AccountSystem
{
    public record DiscordUser(string Id, string Name);

    /// <summary>
    /// Discord login, server side. The launcher opens Discord's login page and
    /// gets back a one-time code; the server swaps that code for the player's
    /// Discord identity using the client secret, which never leaves the server.
    /// </summary>
    public class Discord
    {
        private const string Api = "https://discord.com/api/v10";
        private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

        private readonly Config _config;
        private readonly Action<string> _log;

        public Discord(Config config, Action<string> log)
        {
            _config = config;
            _log = log;
        }

        public bool Configured =>
            !string.IsNullOrWhiteSpace(_config.DiscordClientId) && !string.IsNullOrWhiteSpace(_config.DiscordClientSecret);

        /// <summary>OAuth scopes the launcher should ask for.</summary>
        public string Scopes => string.IsNullOrWhiteSpace(_config.RequiredGuildId) ? "identify" : "identify guilds";

        /// <summary>
        /// Swaps a login code for the Discord user. Returns null with a reason if
        /// the code is bad or the user isn't allowed (not in the required server).
        /// </summary>
        public async Task<(DiscordUser? User, string? Error)> ExchangeAsync(string code)
        {
            using var form = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = _config.DiscordClientId,
                ["client_secret"] = _config.DiscordClientSecret,
                ["grant_type"] = "authorization_code",
                ["code"] = code,
                ["redirect_uri"] = _config.DiscordRedirectUri,
            });

            HttpResponseMessage tokenResponse;
            try
            {
                tokenResponse = await Http.PostAsync($"{Api}/oauth2/token", form);
            }
            catch (Exception e)
            {
                _log($"Discord login: couldn't reach Discord: {e.Message}");
                return (null, "The server couldn't reach Discord. Please try again in a minute.");
            }

            using var _ = tokenResponse;
            if (!tokenResponse.IsSuccessStatusCode)
            {
                // Discord explains what's wrong here, e.g. "invalid_client" (wrong
                // client ID/secret) or "invalid_grant" (redirect URI mismatch or an
                // old code). Only the server log sees it; it never contains the secret.
                var detail = await tokenResponse.Content.ReadAsStringAsync();
                _log($"Discord login refused ({(int)tokenResponse.StatusCode}): {detail}");
                return (null, "Discord didn't accept the login. Please try again.");
            }

            var token = JsonSerializer.Deserialize<TokenResponse>(await tokenResponse.Content.ReadAsStringAsync());
            if (string.IsNullOrEmpty(token?.AccessToken))
                return (null, "Discord didn't return a login. Please try again.");

            var me = await GetAsync<UserResponse>("/users/@me", token.AccessToken);
            if (me == null || string.IsNullOrEmpty(me.Id))
            {
                _log("Discord login: couldn't read the user's account (/users/@me).");
                return (null, "Couldn't read your Discord account.");
            }

            if (!string.IsNullOrWhiteSpace(_config.RequiredGuildId))
            {
                var guilds = await GetAsync<List<GuildResponse>>("/users/@me/guilds", token.AccessToken);
                if (guilds == null || !guilds.Any(g => g.Id == _config.RequiredGuildId))
                {
                    _log($"Discord login: {me.Username ?? me.Id} isn't in the required Discord server{(guilds == null ? " (couldn't read their servers)" : "")}.");
                    return (null, "Join our Discord server first, then log in again.");
                }
            }

            var name = string.IsNullOrWhiteSpace(me.GlobalName) ? me.Username ?? me.Id : me.GlobalName;
            return (new DiscordUser(me.Id, name), null);
        }

        private static async Task<T?> GetAsync<T>(string path, string accessToken)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, Api + path);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode)
                return default;
            return JsonSerializer.Deserialize<T>(await response.Content.ReadAsStringAsync());
        }

        private class TokenResponse
        {
            [JsonPropertyName("access_token")] public string? AccessToken { get; set; }
        }

        private class UserResponse
        {
            [JsonPropertyName("id")] public string Id { get; set; } = "";
            [JsonPropertyName("username")] public string? Username { get; set; }
            [JsonPropertyName("global_name")] public string? GlobalName { get; set; }
        }

        private class GuildResponse
        {
            [JsonPropertyName("id")] public string Id { get; set; } = "";
        }
    }
}
