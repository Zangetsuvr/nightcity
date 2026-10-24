#include "VoiceSystem.h"

#include "GameServer.h"
#include "PlayerManager.h"
#include "Components/PlayerComponent.h"
#include "Components/MovementComponent.h"

namespace
{
// How far each talking range carries, in meters. Listeners a bit past the edge
// still get the frames so voices fade out instead of cutting off.
constexpr float kRanges[] = {3.f, 15.f, 40.f};
constexpr float kMargin = 1.25f;
// A 20 ms Opus voice frame is well under this; anything bigger isn't voice.
constexpr size_t kMaxFrameBytes = 1000;
}

VoiceSystem::VoiceSystem(gsl::not_null<World*> apWorld)
    : m_pWorld(apWorld)
{
    GServer->RegisterHandler<&VoiceSystem::HandleVoiceData>(this);
}

void VoiceSystem::HandleVoiceData(const PacketEvent<client::VoiceData>& aMessage)
{
    const auto& opus = aMessage.get_opus();
    if (opus.empty() || opus.size() > kMaxFrameBytes)
        return;

    auto* pPlayerManager = m_pWorld->get<PlayerManager>();
    const auto speaker = pPlayerManager->GetByConnectionId(aMessage.ConnectionId);
    if (!speaker || !speaker.has<PlayerComponent>())
        return;

    const auto* pSpeaker = speaker.get<PlayerComponent>();
    const auto puppet = pSpeaker->Puppet;
    if (!puppet.is_alive() || !puppet.has<MovementComponent>())
        return;

    const auto range = std::min<uint32_t>(aMessage.get_range(), 2);
    const float reach = kRanges[range] * kMargin;
    const glm::vec3 origin = puppet.get<MovementComponent>()->Position;

    server::VoiceData out;
    out.set_id(puppet.id());
    out.set_opus(opus);
    out.set_range(range);
    out.set_sequence(aMessage.get_sequence());

    m_pWorld->each(
        [&](flecs::entity player, const PlayerComponent& aListener)
        {
            if (player == speaker || !aListener.Puppet.is_alive() || !aListener.Puppet.has<MovementComponent>())
                return;

            const glm::vec3 where = aListener.Puppet.get<MovementComponent>()->Position;
            if (glm::distance(origin, where) > reach)
                return;

            GServer->Send(aListener.Connection, out);
        });
}
