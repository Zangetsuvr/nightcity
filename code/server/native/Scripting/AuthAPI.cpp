#include "AuthAPI.h"

#include <atomic>

static std::atomic<TAuthenticateCallback> s_authenticateCallback{nullptr};

void CyberpunkMP_SetAuthenticateCallback(TAuthenticateCallback aCallback)
{
    s_authenticateCallback = aCallback;
}

int32_t AuthAPI::Authenticate(const char* aUsername, const char* aToken)
{
    const auto callback = s_authenticateCallback.load();
    if (!callback)
        return kAccepted;

    return callback(aUsername ? aUsername : "", aToken ? aToken : "");
}

const char* AuthAPI::Describe(int32_t aResult)
{
    switch (aResult)
    {
    case kNotLoggedIn: return "Not logged in. Start the game from the server launcher.";
    case kSessionExpired: return "Your login has expired. Restart the game from the server launcher.";
    case kWrongName: return "This character belongs to a different account.";
    case kModsMismatch: return "Your mods don't match the server's modpack. Start the game from the server launcher to fix them.";
    case kBanned: return "You are banned from this server.";
    case kAlreadyOnline: return "This account is already connected.";
    case kServerError: return "The server couldn't check your login. Try again in a minute.";
    case kNameTaken: return "This character's name belongs to another player. Start a new game and pick another name.";
    case kInvalidName: return "This character's name isn't allowed on this server. Start a new game and pick another name.";
    case kTooManyCharacters: return "You already have the most characters this server allows. Load one of your existing characters.";
    case kNoCharacterName: return "This save has no character name. Start a new game from the launcher and name your character.";
    default: return "Connection refused.";
    }
}
