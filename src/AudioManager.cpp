#include "AudioManager.h"
#include "Logger.h"

AudioManager::AudioManager()
    : initialized_(false)
    , next_sound_id_(1)
{
}

AudioManager::~AudioManager() {
    // Cleanup all sounds
    sounds_.clear();

    if (initialized_) {
        ma_engine_uninit(&engine_);
        LOG_INFO("Audio engine uninitialized");
    }
}

bool AudioManager::Initialize() {
    if (initialized_) return true;

    ma_result result = ma_engine_init(nullptr, &engine_);
    if (result != MA_SUCCESS) {
        LOG_ERROR("Failed to initialize audio engine: {}", static_cast<int>(result));
        return false;
    }

    initialized_ = true;
    LOG_INFO("Audio engine initialized successfully");
    return true;
}

int AudioManager::LoadSound(const std::string& file_path, std::string& out_error) {
    if (!initialized_ && !Initialize()) {
        out_error = "Failed to initialize audio engine";
        return -1;
    }

    // Allocate new sound ID
    int sound_id = next_sound_id_++;

    // Create sound data
    auto sound_data = std::make_unique<SoundData>();
    sound_data->file_path = file_path;

    ma_result result = ma_sound_init_from_file(&engine_, file_path.c_str(),
                                                MA_SOUND_FLAG_DECODE,
                                                nullptr, nullptr, &sound_data->sound);
    if (result != MA_SUCCESS) {
        out_error = "Failed to load sound '" + file_path + "': " + std::to_string(static_cast<int>(result));
        LOG_ERROR("{}", out_error);
        return -1;
    }

    sound_data->loaded = true;
    sounds_[sound_id] = std::move(sound_data);

    LOG_INFO("Sound loaded: {} (id={})", file_path, sound_id);
    return sound_id;
}

void AudioManager::UnloadSound(int sound_id) {
    auto it = sounds_.find(sound_id);
    if (it == sounds_.end()) {
        LOG_WARN("Attempted to unload non-existent sound id={}", sound_id);
        return;
    }

    if (it->second->loaded) {
        ma_sound_uninit(&it->second->sound);
        LOG_INFO("Sound unloaded: {} (id={})", it->second->file_path, sound_id);
    }

    sounds_.erase(it);
}

void AudioManager::PlaySound(int sound_id, float volume, float pan, bool loop, bool restart) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;

    // Apply settings
    ma_sound_set_volume(&sound->sound, volume);
    ma_sound_set_pan(&sound->sound, pan);
    ma_sound_set_looping(&sound->sound, loop ? MA_TRUE : MA_FALSE);

    if (restart) {
        ma_sound_seek_to_pcm_frame(&sound->sound, 0);
    }

    ma_sound_start(&sound->sound);
}

void AudioManager::StopSound(int sound_id) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;
    ma_sound_stop(&sound->sound);
}

void AudioManager::PauseSound(int sound_id) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;
    ma_sound_stop(&sound->sound);
}

void AudioManager::SetVolume(int sound_id, float volume) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;
    ma_sound_set_volume(&sound->sound, volume);
}

void AudioManager::SetPan(int sound_id, float pan) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;
    ma_sound_set_pan(&sound->sound, pan);
}

void AudioManager::SetLooping(int sound_id, bool loop) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;
    ma_sound_set_looping(&sound->sound, loop ? MA_TRUE : MA_FALSE);
}

void AudioManager::SetPosition(int sound_id, float seconds) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;

    ma_uint32 sample_rate = ma_engine_get_sample_rate(&engine_);
    ma_uint64 frame = static_cast<ma_uint64>(seconds * sample_rate);
    ma_sound_seek_to_pcm_frame(&sound->sound, frame);
}

void AudioManager::Rewind(int sound_id) {
    SoundData* sound = GetSound(sound_id);
    if (!sound) return;
    ma_sound_seek_to_pcm_frame(&sound->sound, 0);
}

bool AudioManager::IsPlaying(int sound_id) const {
    const SoundData* sound = GetSound(sound_id);
    if (!sound) return false;
    return ma_sound_is_playing(&sound->sound) == MA_TRUE;
}

float AudioManager::GetVolume(int sound_id) const {
    const SoundData* sound = GetSound(sound_id);
    if (!sound) return 0.0f;
    return ma_sound_get_volume(&sound->sound);
}

float AudioManager::GetPan(int sound_id) const {
    const SoundData* sound = GetSound(sound_id);
    if (!sound) return 0.0f;
    return ma_sound_get_pan(&sound->sound);
}

bool AudioManager::IsLooping(int sound_id) const {
    const SoundData* sound = GetSound(sound_id);
    if (!sound) return false;
    return ma_sound_is_looping(&sound->sound) == MA_TRUE;
}

float AudioManager::GetPosition(int sound_id) const {
    const SoundData* sound = GetSound(sound_id);
    if (!sound || !initialized_) return 0.0f;

    ma_uint32 sample_rate = ma_engine_get_sample_rate(&engine_);
    ma_uint64 cursor;
    ma_sound_get_cursor_in_pcm_frames(&sound->sound, &cursor);
    return static_cast<float>(cursor) / static_cast<float>(sample_rate);
}

float AudioManager::GetLength(int sound_id) const {
    const SoundData* sound = GetSound(sound_id);
    if (!sound || !initialized_) return 0.0f;

    ma_uint32 sample_rate = ma_engine_get_sample_rate(&engine_);
    ma_uint64 length;
    ma_sound_get_length_in_pcm_frames(&sound->sound, &length);
    return static_cast<float>(length) / static_cast<float>(sample_rate);
}

void AudioManager::SetMasterVolume(float volume) {
    if (!initialized_) return;
    ma_engine_set_volume(&engine_, volume);
}

float AudioManager::GetMasterVolume() const {
    if (!initialized_) return 1.0f;
    return ma_engine_get_volume(const_cast<ma_engine*>(&engine_));
}

AudioManager::SoundData* AudioManager::GetSound(int sound_id) {
    auto it = sounds_.find(sound_id);
    if (it == sounds_.end()) {
        LOG_WARN("Sound id={} not found", sound_id);
        return nullptr;
    }
    return it->second.get();
}

const AudioManager::SoundData* AudioManager::GetSound(int sound_id) const {
    auto it = sounds_.find(sound_id);
    if (it == sounds_.end()) {
        return nullptr;
    }
    return it->second.get();
}
