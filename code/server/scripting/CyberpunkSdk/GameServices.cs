namespace CyberpunkSdk
{
    /// <summary>
    /// Server-side money. Every payout, purchase and transfer goes through here,
    /// so the server - not the player's game - decides how much money anyone has.
    /// </summary>
    public interface IEconomy
    {
        /// <summary>Current balance of an online player, or 0 if they are not loaded.</summary>
        long GetBalance(ulong playerId);

        /// <summary>Adds money. Returns false if the player isn't loaded or the amount is invalid.</summary>
        bool Credit(ulong playerId, long amount, string reason);

        /// <summary>Removes money. Returns false (and changes nothing) if they can't afford it.</summary>
        bool Debit(ulong playerId, long amount, string reason);

        /// <summary>Moves money between two online players in one step. Returns false if it can't happen.</summary>
        bool Transfer(ulong fromPlayerId, ulong toPlayerId, long amount, string reason);
    }

    /// <summary>
    /// Saved progress that survives restarts: experience and the player's current job.
    /// </summary>
    public interface IProgression
    {
        /// <summary>Adds experience to a track ("Street Cred", a job name, ...).</summary>
        void AddXp(ulong playerId, string track, long amount, string reason);

        long GetXp(ulong playerId, string track);

        /// <summary>The job the player had when they last left, or null.</summary>
        string? GetSavedJob(ulong playerId);

        void SetSavedJob(ulong playerId, string? job);
    }

    /// <summary>
    /// Lets plugins use each other without referencing each other's assemblies.
    /// CharacterSystem fills these in when it loads; other plugins should treat
    /// null as "not installed" and carry on.
    /// </summary>
    public static class GameServices
    {
        public static IEconomy? Economy { get; set; }
        public static IProgression? Progression { get; set; }
    }
}
