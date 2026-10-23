namespace CyberpunkSdk
{
    /// <summary>
    /// Why a login was refused. Keep in sync with AuthAPI::Result in
    /// code/server/native/Scripting/AuthAPI.h, which turns these into the
    /// message the player sees.
    /// </summary>
    public enum AuthResult
    {
        Accepted = 0,
        NotLoggedIn = 1,
        SessionExpired = 2,
        WrongName = 3,
        ModsMismatch = 4,
        Banned = 5,
        AlreadyOnline = 6,
        ServerError = 7,
        NameTaken = 8,
        InvalidName = 9,
        TooManyCharacters = 10,
        NoCharacterName = 11,
    }

    /// <summary>
    /// Decides whether a connecting player may join. Set by an account plugin;
    /// when nothing is set, everyone is let in (the original behaviour).
    /// Called on the server's main thread for every connection attempt.
    /// </summary>
    public delegate AuthResult Authenticator(string username, string token);

    public static class Authentication
    {
        public static Authenticator? Authenticator { get; set; }
    }
}
