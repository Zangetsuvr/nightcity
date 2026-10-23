using System.Text.Json;
using CyberpunkSdk.Systems;

namespace AccountSystem
{
    public class LauncherNews
    {
        public string Title { get; set; } = "";
        public string Date { get; set; } = "";
        public string Body { get; set; } = "";
    }

    public class LauncherLink
    {
        public string Label { get; set; } = "";
        public string Url { get; set; } = "";
    }

    public class LauncherMaintenance
    {
        /// <summary>Shows the banner.</summary>
        public bool Active { get; set; }

        public string Message { get; set; } = "The city is closed for maintenance. Check back soon.";

        /// <summary>Also greys out "Enter Night City" in the launcher (admins too).</summary>
        public bool BlockPlay { get; set; } = true;
    }

    /// <summary>
    /// config/launcher.json: what the launcher shows on this server's page.
    /// Read again whenever the file changes, so edits show up in everyone's
    /// launcher within about 15 seconds, with no restart and no launcher update.
    /// </summary>
    public class LauncherContent
    {
        /// <summary>A short line under the server's description. Empty = none.</summary>
        public string Motd { get; set; } = "";

        public LauncherMaintenance Maintenance { get; set; } = new();

        /// <summary>Newest first.</summary>
        public List<LauncherNews> News { get; set; } = new()
        {
            new() { Title = "Welcome to Night City", Date = DateTime.UtcNow.ToString("yyyy-MM-dd"), Body = "Edit config/launcher.json on the server to change this." },
        };

        public List<string> Rules { get; set; } = new()
        {
            "Stay in character.",
            "No random killing.",
        };

        /// <summary>Buttons on the server page. Only https:// links are shown.</summary>
        public List<LauncherLink> Links { get; set; } = new();
    }

    internal sealed class LauncherContentFile
    {
        private readonly string _path;
        private readonly Logger _logger = new("Launcher");
        private readonly object _lock = new();
        private LauncherContent _content = new();
        private DateTime _stamp = DateTime.MinValue;

        public LauncherContentFile(string serverRoot)
        {
            _path = Path.Combine(serverRoot, "config", "launcher.json");
            if (!File.Exists(_path))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                File.WriteAllText(_path, JsonSerializer.Serialize(new LauncherContent(), new JsonSerializerOptions { WriteIndented = true }));
            }
        }

        public LauncherContent Get()
        {
            lock (_lock)
            {
                try
                {
                    var stamp = File.GetLastWriteTimeUtc(_path);
                    if (stamp != _stamp)
                    {
                        _content = JsonSerializer.Deserialize<LauncherContent>(File.ReadAllText(_path), new JsonSerializerOptions { ReadCommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true, PropertyNameCaseInsensitive = true }) ?? new LauncherContent();
                        _content.Links = _content.Links.Where(l => l.Url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)).ToList();
                        _stamp = stamp;
                    }
                }
                catch (Exception ex)
                {
                    // Keep showing the last good version while the file is being fixed.
                    _logger.Error($"Could not read {_path}: {ex.Message}");
                    _stamp = DateTime.MinValue;
                }
                return _content;
            }
        }
    }
}
