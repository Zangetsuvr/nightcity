#pragma once

#include <optional>
#include <string>

// The login the server launcher writes to session.json next to this plugin
// before starting the game.
struct Session
{
    std::string ApiUrl;       // e.g. "http://1.2.3.4:11778"
    std::string Token;        // "<session token>:<mod fingerprint>", sent when connecting
    std::string SessionToken; // just the session part, for the web API

    // Reads session.json; empty if the game wasn't started from the launcher.
    static std::optional<Session> Read();
};
