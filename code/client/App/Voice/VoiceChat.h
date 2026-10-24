#pragma once

#include <deque>
#include <functional>
#include <mutex>
#include <unordered_map>
#include <glm/gtc/constants.hpp>

struct ma_device;
struct OpusEncoder;
struct OpusDecoder;

// Proximity voice chat, inside the game like FiveM's.
//
// Microphone and speakers are opened directly with miniaudio (not through the
// game's audio engine). While push-to-talk is held, the microphone is cut into
// 20 ms frames, compressed with Opus and sent to the server, which passes them
// to players close enough to hear (server/native/Systems/VoiceSystem.cpp).
// Incoming voices are decoded, buffered a little to smooth out the network, and
// mixed into the speakers with volume and left/right set from where that
// player stands relative to you.
//
// Threads: the microphone and speaker callbacks run on miniaudio's audio
// threads; everything else (network, positions) on the game thread. The two
// meet only under m_lock.
class VoiceChat
{
public:
    static constexpr int kSampleRate = 48000;
    static constexpr int kFrame = 960; // 20 ms

    VoiceChat();
    ~VoiceChat();

    void Start();
    void Stop();

    // Game thread, every update: sends what the microphone produced and moves
    // each voice to where its player now is. aPositionOf finds a speaker's
    // character by server id; the listener is you.
    void Tick(const std::function<bool(uint64_t, glm::vec3&)>& aPositionOf, bool aHasListener, const glm::vec3& aListener, const glm::quat& aFacing);

    void HandleVoiceData(const PacketEvent<server::VoiceData>& aMessage);

    void SetTalking(bool aTalking);
    bool IsTalking() const { return m_talking; }
    void SetRange(int32_t aRange);
    int32_t GetRange() const { return m_range; }
    bool HasMicrophone() const { return m_captureOk; }
    // Server ids of players heard in the last moment (for "who's talking").
    std::vector<uint64_t> GetSpeakingIds() const;

    // Audio-thread entry points (miniaudio callbacks).
    void OnCapture(const float* apSamples, uint32_t aCount);
    void OnPlayback(float* apOut, uint32_t aFrames);

private:
    struct Speaker
    {
        OpusDecoder* Decoder{nullptr};
        std::deque<float> Pcm;
        bool Primed{false};
        float GainL{0.f};
        float GainR{0.f};
        uint32_t Range{1};
        uint32_t LastSequence{0};
        bool HasSequence{false};
        std::chrono::steady_clock::time_point LastHeard{};
    };

    void ReleaseSpeakers();

    mutable std::mutex m_lock;
    bool m_running{false};
    bool m_captureOk{false};
    bool m_playbackOk{false};
    std::unique_ptr<ma_device> m_capture;
    std::unique_ptr<ma_device> m_playback;
    OpusEncoder* m_encoder{nullptr};

    std::atomic<bool> m_talking{false};
    std::atomic<int32_t> m_range{1};
    uint32_t m_sequence{0};

    // Microphone side (filled on the audio thread, sent on the game thread).
    std::vector<float> m_captureBuffer;
    std::deque<std::vector<uint8_t>> m_outgoing;

    std::unordered_map<uint64_t, Speaker> m_speakers;
};
