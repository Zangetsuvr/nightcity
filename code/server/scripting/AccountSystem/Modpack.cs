using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace AccountSystem
{
    public record ModpackFile(string Path, string Sha256, long Size);

    /// <summary>What the launcher downloads to know exactly which mod files are allowed.</summary>
    public record ModpackManifest(
        string Fingerprint,
        List<string> Roots,
        List<string> Files,
        List<string> Ignore,
        List<ModpackFile> Entries);

    /// <summary>
    /// The server's modpack: every mod file players must have, with hashes.
    ///
    /// FINGERPRINT RULE (the launcher implements the same rule in
    /// code/launcher/electron/modpack.js; change both together):
    ///   1. Paths use "/" and are compared in lower case.
    ///   2. Take every mod file (under a mod root, or one of the single mod
    ///      files) that isn't ignored.
    ///   3. Sort by lower-cased path, ordinal.
    ///   4. For each, append  lowercase(path) + "\n" + sha256hex + "\n".
    ///   5. The fingerprint is the SHA-256 (lower-case hex) of that UTF-8 text.
    /// </summary>
    public class Modpack
    {
        private readonly string _folder;
        private readonly Config _config;
        private readonly List<Regex> _ignore;
        private readonly object _lock = new();

        private ModpackManifest _manifest;
        private Dictionary<string, ModpackFile> _byPath = new();

        public Modpack(string folder, Config config)
        {
            _folder = Path.GetFullPath(folder);
            _config = config;
            _ignore = config.Ignore.Select(GlobToRegex).ToList();
            Directory.CreateDirectory(_folder);
            _manifest = Scan();
        }

        public ModpackManifest Manifest
        {
            get { lock (_lock) { return _manifest; } }
        }

        public string Fingerprint => Manifest.Fingerprint;

        /// <summary>Re-reads the modpack folder (after an admin changed it).</summary>
        public ModpackManifest Reload()
        {
            var next = Scan();
            lock (_lock) { _manifest = next; }
            return next;
        }

        /// <summary>
        /// Full path of a modpack file, or null if that path isn't in the
        /// manifest. Only listed files are ever served, so a request can't
        /// reach anything else on the server.
        /// </summary>
        public string? FileFor(string path)
        {
            var key = Normalize(path).ToLowerInvariant();
            lock (_lock)
            {
                if (!_byPath.TryGetValue(key, out var entry))
                    return null;
                return Path.Combine(_folder, entry.Path.Replace('/', Path.DirectorySeparatorChar));
            }
        }

        private ModpackManifest Scan()
        {
            var entries = new List<ModpackFile>();
            foreach (var file in Directory.EnumerateFiles(_folder, "*", SearchOption.AllDirectories))
            {
                var rel = Normalize(Path.GetRelativePath(_folder, file));
                if (!IsModPath(rel, _config.ModRoots, _config.ModFiles) || IsIgnored(rel))
                    continue;

                using var stream = File.OpenRead(file);
                var hash = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
                entries.Add(new ModpackFile(rel, hash, new FileInfo(file).Length));
            }

            entries.Sort((a, b) => string.CompareOrdinal(a.Path.ToLowerInvariant(), b.Path.ToLowerInvariant()));

            var byPath = entries.ToDictionary(e => e.Path.ToLowerInvariant());
            lock (_lock) { _byPath = byPath; }

            return new ModpackManifest(
                ComputeFingerprint(entries.Select(e => (e.Path, e.Sha256))),
                _config.ModRoots.ToList(),
                _config.ModFiles.ToList(),
                _config.Ignore.ToList(),
                entries);
        }

        // ---------------------------------------------------------------- shared rules

        public static string Normalize(string path) => path.Replace('\\', '/').Trim('/');

        public static bool IsModPath(string path, IEnumerable<string> roots, IEnumerable<string> files)
        {
            var p = Normalize(path).ToLowerInvariant();
            foreach (var root in roots)
            {
                var r = Normalize(root).ToLowerInvariant();
                if (p.StartsWith(r + "/", StringComparison.Ordinal))
                    return true;
            }
            return files.Any(f => Normalize(f).ToLowerInvariant() == p);
        }

        public bool IsIgnored(string path)
        {
            var p = Normalize(path).ToLowerInvariant();
            return _ignore.Any(r => r.IsMatch(p));
        }

        public static string ComputeFingerprint(IEnumerable<(string Path, string Sha256)> files)
        {
            var sorted = files
                .Select(f => (Path: Normalize(f.Path).ToLowerInvariant(), Hash: f.Sha256.ToLowerInvariant()))
                .OrderBy(f => f.Path, StringComparer.Ordinal);

            var text = new StringBuilder();
            foreach (var (path, hash) in sorted)
                text.Append(path).Append('\n').Append(hash).Append('\n');

            return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text.ToString()))).ToLowerInvariant();
        }

        /// <summary>
        /// "**" matches any number of folders (including none), "*" anything
        /// within one folder, "?" one character. Matching is case-insensitive.
        /// </summary>
        public static Regex GlobToRegex(string glob)
        {
            var g = Normalize(glob).ToLowerInvariant();
            var sb = new StringBuilder("^");
            for (var i = 0; i < g.Length; i++)
            {
                var c = g[i];
                if (c == '*' && i + 1 < g.Length && g[i + 1] == '*')
                {
                    // "**/" = any folders (or none); a trailing "**" = anything.
                    if (i + 2 < g.Length && g[i + 2] == '/')
                    {
                        sb.Append("(?:.*/)?");
                        i += 2;
                    }
                    else
                    {
                        sb.Append(".*");
                        i += 1;
                    }
                }
                else if (c == '*')
                    sb.Append("[^/]*");
                else if (c == '?')
                    sb.Append("[^/]");
                else
                    sb.Append(Regex.Escape(c.ToString()));
            }
            sb.Append('$');
            return new Regex(sb.ToString(), RegexOptions.CultureInvariant);
        }
    }
}
