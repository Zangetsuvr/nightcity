namespace CharacterSystem
{
    /// <summary>
    /// Street Cred levels. Reaching level L takes 50 * L * (L - 1) total XP:
    /// level 2 at 100, 3 at 300, 5 at 1,000, 10 at 4,500, 50 at 122,500.
    /// </summary>
    public static class Leveling
    {
        public const string StreetCred = "Street Cred";

        public static long XpForLevel(int level) => level <= 1 ? 0 : 50L * level * (level - 1);

        public static int LevelForXp(long xp, int maxLevel)
        {
            var level = 1;
            while (level < maxLevel && xp >= XpForLevel(level + 1))
                level++;
            return level;
        }

        /// <summary>Total XP needed for the next level, or the current XP if already at max.</summary>
        public static long NextLevelXp(long xp, int maxLevel)
        {
            var level = LevelForXp(xp, maxLevel);
            return level >= maxLevel ? xp : XpForLevel(level + 1);
        }
    }
}
