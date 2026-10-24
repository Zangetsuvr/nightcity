#include "VoiceChat.h"

#include "App/Network/NetworkService.h"

#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>

#include <opus/opus.h>

namespace
{
// Keep at most this much of anyone's voice waiting to play (stops a lagging
// connection from building up an ever-longer delay).
constexpr size_t kMaxBuffered = VoiceChat::kSampleRate / 2;
// Start playing someone once this much has arrived (smooths network jitter).
constexpr size_t kPrimeAt = VoiceChat::kFrame * 3;

constexpr float kRangeMeters[] = {3.f, 15.f, 40.f};

void CaptureCallback(ma_device* apDevice, void*, const void* apInput, ma_uint32 aFrames)
{
    if (auto* pVoice = static_cast<VoiceChat*>(apDevice->pUserData); pVoice && apInput)
        pVoice->OnCapture(static_cast<const float*>(apInput), aFrames);
}

void PlaybackCallback(ma_device* apDevice, void* apOutput, const void*, ma_uint32 aFrames)
{
    auto* pOut = static_cast<float*>(apOutput);
    std::fill_n(pOut, aFrames * 2, 0.f);
    if (auto* pVoice = static_cast<VoiceChat*>(apDevice->pUserData))
        pVoice->OnPlayback(pOut, aFrames);
}
}

VoiceChat::VoiceChat() = default;

VoiceChat::~VoiceChat()
{
    Stop();
}

void VoiceChat::Start()
{
    if (m_running)
        return;
    m_running = true;

    int error = 0;
    m_encoder = opus_encoder_create(kSampleRate, 1, OPUS_APPLICATION_VOIP, &error);
    if (!m_encoder || error != OPUS_OK)
    {
        spdlog::error("[Voice] Opus encoder failed ({})", error);
        m_encoder = nullptr;
    }
    else
    {
        opus_encoder_ctl(m_encoder, OPUS_SET_BITRATE(24000));
        opus_encoder_ctl(m_encoder, OPUS_SET_COMPLEXITY(5));
        opus_encoder_ctl(m_encoder, OPUS_SET_INBAND_FEC(1));
        opus_encoder_ctl(m_encoder, OPUS_SET_PACKET_LOSS_PERC(10));
        opus_encoder_ctl(m_encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    }

    // Speakers: always, so you can hear others even without a microphone.
    {
        auto config = ma_device_config_init(ma_device_type_playback);
        config.playback.format = ma_format_f32;
        config.playback.channels = 2;
        config.sampleRate = kSampleRate;
        config.periodSizeInFrames = kFrame / 2;
        config.dataCallback = PlaybackCallback;
        config.pUserData = this;
        m_playback = std::make_unique<ma_device>();
        m_playbackOk = ma_device_init(nullptr, &config, m_playback.get()) == MA_SUCCESS
                    && ma_device_start(m_playback.get()) == MA_SUCCESS;
        if (!m_playbackOk)
            spdlog::error("[Voice] Couldn't open the speakers; you won't hear other players.");
    }

    // Microphone.
    if (m_encoder)
    {
        auto config = ma_device_config_init(ma_device_type_capture);
        config.capture.format = ma_format_f32;
        config.capture.channels = 1;
        config.sampleRate = kSampleRate;
        config.periodSizeInFrames = kFrame / 2;
        config.dataCallback = CaptureCallback;
        config.pUserData = this;
        m_capture = std::make_unique<ma_device>();
        m_captureOk = ma_device_init(nullptr, &config, m_capture.get()) == MA_SUCCESS
                   && ma_device_start(m_capture.get()) == MA_SUCCESS;
        if (!m_captureOk)
            spdlog::error("[Voice] Couldn't open a microphone; others won't hear you. Check Windows privacy settings for the microphone.");
    }

    spdlog::info("[Voice] Started (microphone {}, speakers {})", m_captureOk ? "on" : "off", m_playbackOk ? "on" : "off");
}

void VoiceChat::Stop()
{
    if (!m_running)
        return;
    m_running = false;
    m_talking = false;

    // Devices first, so no audio callback runs while the rest goes away.
    if (m_capture)
    {
        if (m_captureOk)
            ma_device_uninit(m_capture.get());
        m_capture.reset();
    }
    if (m_playback)
    {
        if (m_playbackOk)
            ma_device_uninit(m_playback.get());
        m_playback.reset();
    }
    m_captureOk = false;
    m_playbackOk = false;

    if (m_encoder)
    {
        opus_encoder_destroy(m_encoder);
        m_encoder = nullptr;
    }

    std::scoped_lock _(m_lock);
    m_captureBuffer.clear();
    m_outgoing.clear();
    ReleaseSpeakers();
}

void VoiceChat::ReleaseSpeakers()
{
    for (auto& [id, speaker] : m_speakers)
    {
        if (speaker.Decoder)
            opus_decoder_destroy(speaker.Decoder);
    }
    m_speakers.clear();
}

void VoiceChat::SetTalking(bool aTalking)
{
    m_talking = aTalking && m_captureOk;
}

void VoiceChat::SetRange(int32_t aRange)
{
    m_range = std::clamp(aRange, 0, 2);
}

// ---------------------------------------------------------------- microphone

void VoiceChat::OnCapture(const float* apSamples, uint32_t aCount)
{
    std::scoped_lock _(m_lock);
    if (!m_talking || !m_encoder)
    {
        m_captureBuffer.clear();
        return;
    }

    m_captureBuffer.insert(m_captureBuffer.end(), apSamples, apSamples + aCount);
    while (m_captureBuffer.size() >= kFrame)
    {
        std::vector<uint8_t> packet(600);
        const auto bytes = opus_encode_float(m_encoder, m_captureBuffer.data(), kFrame, packet.data(), static_cast<opus_int32>(packet.size()));
        m_captureBuffer.erase(m_captureBuffer.begin(), m_captureBuffer.begin() + kFrame);
        if (bytes > 0)
        {
            packet.resize(bytes);
            m_outgoing.push_back(std::move(packet));
            // Never pile up more than half a second if the game stalls.
            while (m_outgoing.size() > 25)
                m_outgoing.pop_front();
        }
    }
}

// ---------------------------------------------------------------- speakers

void VoiceChat::OnPlayback(float* apOut, uint32_t aFrames)
{
    std::scoped_lock _(m_lock);
    for (auto& [id, speaker] : m_speakers)
    {
        if (!speaker.Primed)
        {
            if (speaker.Pcm.size() < kPrimeAt)
                continue;
            speaker.Primed = true;
        }

        const uint32_t count = static_cast<uint32_t>(std::min<size_t>(aFrames, speaker.Pcm.size()));
        for (uint32_t i = 0; i < count; ++i)
        {
            const float s = speaker.Pcm.front();
            speaker.Pcm.pop_front();
            apOut[i * 2] += s * speaker.GainL;
            apOut[i * 2 + 1] += s * speaker.GainR;
        }
        // Ran dry: wait for a little more before carrying on.
        if (speaker.Pcm.empty())
            speaker.Primed = false;
    }

    for (uint32_t i = 0; i < aFrames * 2; ++i)
        apOut[i] = std::clamp(apOut[i], -1.f, 1.f);
}

void VoiceChat::HandleVoiceData(const PacketEvent<server::VoiceData>& aMessage)
{
    if (!m_running || !m_playbackOk)
        return;

    const auto& opus = aMessage.get_opus();
    if (opus.empty())
        return;

    std::scoped_lock _(m_lock);
    auto& speaker = m_speakers[aMessage.get_id()];
    if (!speaker.Decoder)
    {
        int error = 0;
        speaker.Decoder = opus_decoder_create(kSampleRate, 1, &error);
        if (!speaker.Decoder || error != OPUS_OK)
        {
            m_speakers.erase(aMessage.get_id());
            return;
        }
    }

    speaker.Range = std::min<uint32_t>(aMessage.get_range(), 2);
    speaker.LastHeard = std::chrono::steady_clock::now();

    float pcm[kFrame * 2];
    const uint32_t sequence = aMessage.get_sequence();

    // One frame lost on the way: let Opus rebuild it from this one.
    if (speaker.HasSequence && sequence == speaker.LastSequence + 2)
    {
        const int got = opus_decode_float(speaker.Decoder, opus.data(), static_cast<opus_int32>(opus.size()), pcm, kFrame, 1);
        if (got > 0)
            speaker.Pcm.insert(speaker.Pcm.end(), pcm, pcm + got);
    }
    // Old or repeated frame: drop it.
    if (speaker.HasSequence && static_cast<int32_t>(sequence - speaker.LastSequence) <= 0)
        return;

    const int got = opus_decode_float(speaker.Decoder, opus.data(), static_cast<opus_int32>(opus.size()), pcm, kFrame, 0);
    if (got > 0)
        speaker.Pcm.insert(speaker.Pcm.end(), pcm, pcm + got);

    speaker.LastSequence = sequence;
    speaker.HasSequence = true;

    while (speaker.Pcm.size() > kMaxBuffered)
        speaker.Pcm.pop_front();
}

std::vector<uint64_t> VoiceChat::GetSpeakingIds() const
{
    std::vector<uint64_t> ids;
    const auto now = std::chrono::steady_clock::now();
    std::scoped_lock _(m_lock);
    for (const auto& [id, speaker] : m_speakers)
    {
        if (now - speaker.LastHeard < std::chrono::milliseconds(300))
            ids.push_back(id);
    }
    return ids;
}

// ---------------------------------------------------------------- game thread

void VoiceChat::Tick(const std::function<bool(uint64_t, glm::vec3&)>& aPositionOf, bool aHasListener, const glm::vec3& aListener, const glm::quat& aFacing)
{
    if (!m_running)
        return;

    std::deque<std::vector<uint8_t>> outgoing;
    {
        std::scoped_lock _(m_lock);
        outgoing.swap(m_outgoing);
    }

    if (!outgoing.empty())
    {
        const auto pNetworkService = Core::Container::Get<NetworkService>();
        for (auto& packet : outgoing)
        {
            client::VoiceData message;
            Vector<uint8_t> bytes;
            bytes.assign(packet.begin(), packet.end());
            message.set_opus(bytes);
            message.set_range(static_cast<uint32_t>(m_range.load()));
            message.set_sequence(++m_sequence);
            pNetworkService->Send(message);
        }
    }

    // Where everyone heard recently is, relative to you.
    std::vector<uint64_t> ids;
    {
        std::scoped_lock _(m_lock);
        const auto now = std::chrono::steady_clock::now();
        for (auto it = m_speakers.begin(); it != m_speakers.end();)
        {
            // Quiet for a while: let the decoder go.
            if (now - it->second.LastHeard > std::chrono::seconds(30))
            {
                if (it->second.Decoder)
                    opus_decoder_destroy(it->second.Decoder);
                it = m_speakers.erase(it);
                continue;
            }
            ids.push_back(it->first);
            ++it;
        }
    }

    const glm::vec3 right = aFacing * glm::vec3(1.f, 0.f, 0.f);
    for (const auto id : ids)
    {
        float gainL = 0.f;
        float gainR = 0.f;
        glm::vec3 where;
        uint32_t range = 1;
        {
            std::scoped_lock _(m_lock);
            if (auto it = m_speakers.find(id); it != m_speakers.end())
                range = it->second.Range;
        }

        if (aHasListener && aPositionOf(id, where))
        {
            const glm::vec3 offset = where - aListener;
            const float distance = glm::length(offset);
            const float reach = kRangeMeters[std::min<uint32_t>(range, 2)];
            float volume = 1.f;
            if (distance > 1.f)
                volume = std::pow(std::clamp(1.f - (distance - 1.f) / std::max(reach - 1.f, 0.5f), 0.f, 1.f), 1.4f);

            // -1 fully left .. 1 fully right, softened so voices never vanish from one ear.
            float pan = distance > 0.5f ? glm::dot(offset / distance, right) : 0.f;
            pan = std::clamp(pan, -1.f, 1.f) * 0.8f;
            const float angle = (pan + 1.f) * 0.25f * glm::pi<float>();
            gainL = volume * std::cos(angle) * 1.414f;
            gainR = volume * std::sin(angle) * 1.414f;
        }

        std::scoped_lock _(m_lock);
        if (auto it = m_speakers.find(id); it != m_speakers.end())
        {
            it->second.GainL = std::min(gainL, 1.5f);
            it->second.GainR = std::min(gainR, 1.5f);
        }
    }
}
