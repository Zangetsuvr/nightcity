#pragma once

struct World;

// Proximity voice. Each player's game sends 20 ms Opus frames while they hold
// push-to-talk; the server passes each frame on to the players close enough to
// hear it (whisper / normal / shout range). Nothing is stored or decoded here.
struct VoiceSystem
{
    VoiceSystem(gsl::not_null<World*> apWorld);

protected:
    void HandleVoiceData(const PacketEvent<client::VoiceData>& aMessage);

private:
    gsl::not_null<World*> m_pWorld;
};
