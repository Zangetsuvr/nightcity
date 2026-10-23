using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

namespace CharacterSystem.Store
{
    /// <summary>
    /// SQLite itself is a native library (e_sqlite3.dll / libe_sqlite3.so) that
    /// ships inside this plugin's folder under runtimes/&lt;platform&gt;/native/.
    /// The server only looks for native libraries next to itself, so this points
    /// it at the plugin's copy. Call Register() before the first database use.
    /// </summary>
    internal static class NativeSqlite
    {
        private static bool _registered;

        public static void Register()
        {
            if (_registered)
                return;
            _registered = true;

            var pluginDir = Path.GetDirectoryName(typeof(NativeSqlite).Assembly.Location) ?? AppContext.BaseDirectory;
            AssemblyLoadContext.Default.ResolvingUnmanagedDll += (Assembly _, string name) =>
            {
                if (!name.Contains("e_sqlite3", StringComparison.OrdinalIgnoreCase))
                    return IntPtr.Zero;

                foreach (var candidate in Candidates(pluginDir))
                {
                    if (File.Exists(candidate) && NativeLibrary.TryLoad(candidate, out var handle))
                        return handle;
                }
                return IntPtr.Zero;
            };
        }

        private static IEnumerable<string> Candidates(string pluginDir)
        {
            string os, file;
            if (OperatingSystem.IsWindows()) { os = "win"; file = "e_sqlite3.dll"; }
            else if (OperatingSystem.IsMacOS()) { os = "osx"; file = "libe_sqlite3.dylib"; }
            else { os = "linux"; file = "libe_sqlite3.so"; }

            var arch = RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(); // x64, arm64, ...

            yield return Path.Combine(pluginDir, "runtimes", $"{os}-{arch}", "native", file);
            yield return Path.Combine(pluginDir, file);
        }
    }
}
