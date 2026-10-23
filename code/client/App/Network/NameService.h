#pragma once

#include <memory>
#include <mutex>
#include <string>

// Character names, client side.
//
// - The character creator asks the server whether a name is free and reserves
//   it on Confirm. Requests run on a worker thread; scripts poll the result
//   every few frames (see Plugins/CharacterName.reds), so nothing blocks the game.
// - The name of the loaded save is kept here and sent when connecting.
class NameService
{
public:
    // Keep in sync with Plugins/CharacterName.reds.
    enum class Status : int32_t
    {
        Idle = 0,
        Checking = 1,
        Available = 2,
        Unavailable = 3, // taken, not allowed, or the account is full; see the message
        Reserving = 4,
        Reserved = 5,
        Error = 6,       // couldn't reach the server
    };

    static NameService& Get();

    bool HasSession() const;

    void RequestCheck(const std::string& aName);
    void RequestReserve(const std::string& aName);

    Status GetStatus() const;
    std::string GetStatusMessage() const;
    std::string GetStatusName() const; // the name the current status is about

    // Name of the character in the loaded save; sent when connecting.
    void SetCharacterName(const std::string& aName);
    std::string GetCharacterName() const;

    // Name confirmed in the character creator, waiting for the new game's save
    // to pick it up (the creator runs before that save exists).
    void SetPendingName(const std::string& aName);
    std::string TakePendingName();

private:
    struct State;

    NameService();
    void Start(const std::string& aName, bool aReserve);

    std::shared_ptr<State> m_state;
};
