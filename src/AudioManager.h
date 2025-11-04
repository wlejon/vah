#pragma once

#include <miniaudio.h>
#include <string>
#include <unordered_map>
#include <memory>

/**
 * AudioManager - Main thread audio system manager
 *
 * THREADING: All methods must be called from the main thread only.
 * Lua threads communicate via Commands (LoadSound, PlaySound, etc.)
 *
 * This class owns:
 * - The miniaudio engine (ma_engine)
 * - All sound instances (ma_sound)
 * - Sound ID allocation
 */
class AudioManager {
public:
    AudioManager();
    ~AudioManager();

    // Initialize the audio engine (called on first use)
    bool Initialize();
    bool IsInitialized() const { return initialized_; }

    // Sound loading (returns sound_id or -1 on error, sets error message)
    int LoadSound(const std::string& file_path, std::string& out_error);

    // Unload a sound by ID
    void UnloadSound(int sound_id);

    // Playback control
    void PlaySound(int sound_id, float volume, float pan, bool loop, bool restart);
    void StopSound(int sound_id);
    void PauseSound(int sound_id);

    // Sound properties
    void SetVolume(int sound_id, float volume);
    void SetPan(int sound_id, float pan);
    void SetLooping(int sound_id, bool loop);
    void SetPosition(int sound_id, float seconds);
    void Rewind(int sound_id);

    // Query sound state
    bool IsPlaying(int sound_id) const;
    float GetVolume(int sound_id) const;
    float GetPan(int sound_id) const;
    bool IsLooping(int sound_id) const;
    float GetPosition(int sound_id) const;
    float GetLength(int sound_id) const;

    // Master volume
    void SetMasterVolume(float volume);
    float GetMasterVolume() const;

    // Stats
    int GetLoadedSoundCount() const { return static_cast<int>(sounds_.size()); }

private:
    struct SoundData {
        ma_sound sound;
        std::string file_path;
        bool loaded;

        SoundData() : loaded(false) {}
    };

    bool initialized_;
    ma_engine engine_;
    int next_sound_id_;
    std::unordered_map<int, std::unique_ptr<SoundData>> sounds_;

    // Helper to get sound or nullptr
    SoundData* GetSound(int sound_id);
    const SoundData* GetSound(int sound_id) const;
};
