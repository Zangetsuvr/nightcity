namespace CharacterSystem.Store
{
    /// <summary>
    /// Everything we keep about a character between sessions.
    /// Saved as one JSON file per character.
    /// </summary>
    public class CharacterRecord
    {
        public int Version { get; set; } = 1;

        /// <summary>Lower-cased username; also the file name.</summary>
        public string Key { get; set; } = "";

        /// <summary>Username as the player typed it, for display.</summary>
        public string DisplayName { get; set; } = "";

        public long Balance { get; set; }

        /// <summary>Experience per track, e.g. "Street Cred", "Taxi Driver".</summary>
        public Dictionary<string, long> Xp { get; set; } = new();

        public string? Job { get; set; }

        public DateTime FirstSeenUtc { get; set; }
        public DateTime LastSeenUtc { get; set; }
        public long PlaySeconds { get; set; }

        /// <summary>A frozen wallet can't earn, spend or transfer until an admin unfreezes it.</summary>
        public bool Frozen { get; set; }
        public string? FrozenReason { get; set; }

        /// <summary>Set once the character has been moved to the start point after creation.</summary>
        public bool SpawnedBefore { get; set; }

        /// <summary>Set once the character has been given its lifepath's starter kit.</summary>
        public bool StarterKitGranted { get; set; }

        /// <summary>Lifepath picked in the character creator (Corpo, Nomad, StreetKid), once known.</summary>
        public string? Lifepath { get; set; }

        /// <summary>Cyberware tier bought at a ripperdoc (see CyberwareTiers in character.json).</summary>
        public int CyberwareTier { get; set; } = 1;

        /// <summary>Cars bought at the dealership (vehicle records).</summary>
        public List<string> OwnedVehicles { get; set; } = new();

        public long GetXp(string track) => Xp.TryGetValue(track, out var v) ? v : 0;
    }

    /// <summary>One line in the money log. Every change to a balance writes one.</summary>
    public record LedgerEntry(
        DateTime TimeUtc,
        string Character,
        long Amount,
        long BalanceAfter,
        string Reason,
        string? Counterparty);
}
