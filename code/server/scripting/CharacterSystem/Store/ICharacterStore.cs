using System.Text;

namespace CharacterSystem.Store
{
    /// <summary>
    /// Where characters and the money log are kept (SqliteCharacterStore).
    /// Kept as an interface so the rest of the plugin doesn't depend on how
    /// saving works.
    ///
    /// Characters only work on characters loaded with LoadOrCreate. Changes go
    /// through Modify / ModifyPair: the change function runs on the current
    /// record and returns false to cancel. A cancelled or failed save leaves
    /// the character exactly as it was.
    /// </summary>
    public interface ICharacterStore
    {
        /// <summary>Loads (or creates) a character for an online player and keeps it loaded.</summary>
        CharacterRecord LoadOrCreate(string username, long startingBalance, out bool created);

        bool Modify(string key, Func<CharacterRecord, bool> change);

        /// <summary>Changes two loaded characters together: both or neither.</summary>
        bool ModifyPair(string keyA, string keyB, Func<CharacterRecord, CharacterRecord, bool> change);

        /// <summary>Reads from a loaded character; default(T) if it isn't loaded.</summary>
        T? Read<T>(string key, Func<CharacterRecord, T> read);

        /// <summary>Changes a character whether or not it's loaded here (admin use).</summary>
        bool ModifyOffline(string username, Func<CharacterRecord, bool> change);

        /// <summary>Writes any pending changes.</summary>
        void Flush();

        /// <summary>The player left: save and release the character.</summary>
        void Unload(string key);

        /// <summary>A copy of one character, loaded or not; null if unknown.</summary>
        CharacterRecord? Snapshot(string username);

        List<CharacterRecord> ListAll();

        void AppendLedger(LedgerEntry entry);
    }

    public static class CharacterKeys
    {
        /// <summary>
        /// Turns a username into a safe, unique key (also used as a file name).
        /// Simple names are just lower-cased; anything else is hex-encoded with a
        /// "~" prefix, which simple names can't contain, so two different names
        /// can never share a character.
        /// </summary>
        public static string Normalize(string username)
        {
            var lower = username.Trim().ToLowerInvariant();
            if (lower.Length > 0 && lower.Length <= 64 && lower.All(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-'))
                return lower;

            return "~" + Convert.ToHexString(Encoding.UTF8.GetBytes(lower)).ToLowerInvariant();
        }
    }
}
