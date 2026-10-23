#pragma once

#include "ScriptingBase.h"

// Login check. The C# side (server loader) registers a callback the server
// calls for every connection attempt, after the protocol version check and
// before the player is created.
//
// The callback returns 0 to let the player in. Any other value refuses the
// connection; AuthAPI::Describe turns it into the message the player sees.
//
// This header is deliberately not passed to the C# binding generator: the
// loader calls CyberpunkMP_SetAuthenticateCallback directly with DllImport.

using TAuthenticateCallback = int32_t (*)(const char* aUsername, const char* aToken);

extern "C" TP_EXPORT void CyberpunkMP_SetAuthenticateCallback(TAuthenticateCallback aCallback);

namespace AuthAPI
{
// Keep in sync with AuthResult in code/server/scripting/CyberpunkSdk/Authentication.cs
enum Result : int32_t
{
    kAccepted = 0,
    kNotLoggedIn = 1,     // missing or unknown session token
    kSessionExpired = 2,  // token is valid but too old
    kWrongName = 3,       // token belongs to a different character name
    kModsMismatch = 4,    // mod fingerprint doesn't match the server's modpack
    kBanned = 5,
    kAlreadyOnline = 6,   // this account is already connected
    kServerError = 7,
    kNameTaken = 8,          // the save's character name belongs to another account
    kInvalidName = 9,        // the name breaks the naming rules
    kTooManyCharacters = 10, // the account already has its maximum characters
    kNoCharacterName = 11,   // the save was made without a character name
};

// 0 when no callback is registered, so a server without an account plugin
// behaves exactly as before.
int32_t Authenticate(const char* aUsername, const char* aToken);

const char* Describe(int32_t aResult);
}
