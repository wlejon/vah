#include "AudioBindings.h"
#include "Logger.h"
#include "Commands.h"
#include "LuaThread.h"
#include "LuaConversions.h"

namespace AudioBindings {

// Sound handle - stores sound_id and thread reference
// All operations send commands to main thread
class Sound {
public:
    Sound(int sound_id, LuaThread* thread)
        : sound_id_(sound_id)
        , thread_(thread)
    {
    }

    int GetSoundId() const { return sound_id_; }
    LuaThread* GetThread() const { return thread_; }

private:
    int sound_id_;
    LuaThread* thread_;
};

// Load a sound from file (blocking - uses promise)
std::tuple<sol::object, std::string> LoadSound(sol::this_state s, const std::string& file_path) {
    sol::state_view lua(s);

    // Get LuaThread pointer from registry
    void* ptr = lua.registry()["__luathread_ptr"];
    LuaThread* thread = static_cast<LuaThread*>(ptr);

    if (!thread) {
        return {sol::nil, "No thread context available"};
    }

    try {
        // Create promise for blocking call
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        // Create command
        Commands::LoadSound cmd;
        cmd.requesting_thread_id = thread->GetId();
        cmd.request_id = thread->AllocateRequestId();
        cmd.file_path = file_path;
        cmd.promise = promise;

        // Enqueue command
        thread->EnqueueCommand(std::move(cmd));

        // Block until main thread responds
        PayloadMap response = future.get();

        // Extract sound_id and error
        int64_t sound_id_int = std::get<int64_t>(response.at("sound_id"));
        std::string error = std::get<std::string>(response.at("error"));

        if (sound_id_int < 0) {
            return {sol::nil, error};
        }

        // Create Sound handle
        auto sound = std::make_shared<Sound>(static_cast<int>(sound_id_int), thread);
        return {sol::make_object(lua, sound), ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error loading sound: ") + e.what()};
    }
}

// Unload a sound (fire and forget)
void UnloadSound(std::shared_ptr<Sound> sound) {
    if (!sound) return;

    Commands::UnloadSound cmd;
    cmd.sound_id = sound->GetSoundId();
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Play a sound with optional configuration (fire and forget)
std::tuple<bool, std::string> PlaySound(std::shared_ptr<Sound> sound, sol::optional<sol::table> config) {
    if (!sound) {
        return {false, "Invalid sound"};
    }

    try {
        Commands::PlaySound cmd;
        cmd.sound_id = sound->GetSoundId();
        cmd.volume = 1.0f;
        cmd.pan = 0.0f;
        cmd.loop = false;
        cmd.restart = false;

        // Apply configuration
        if (config) {
            sol::table cfg = config.value();

            if (auto volume = cfg.get<sol::optional<float>>("volume")) {
                cmd.volume = volume.value();
            }

            if (auto pan = cfg.get<sol::optional<float>>("pan")) {
                cmd.pan = pan.value();
            }

            if (auto loop = cfg.get<sol::optional<bool>>("loop")) {
                cmd.loop = loop.value();
            }

            if (auto restart = cfg.get<sol::optional<bool>>("restart")) {
                cmd.restart = restart.value();
            }
        }

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        return {true, ""};
    }
    catch (const std::exception& e) {
        return {false, std::string("Error playing sound: ") + e.what()};
    }
}

// Stop a sound (fire and forget)
void StopSound(std::shared_ptr<Sound> sound) {
    if (!sound) return;

    Commands::StopSound cmd;
    cmd.sound_id = sound->GetSoundId();
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Pause a sound (fire and forget)
void PauseSound(std::shared_ptr<Sound> sound) {
    if (!sound) return;

    Commands::PauseSound cmd;
    cmd.sound_id = sound->GetSoundId();
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Set sound volume (fire and forget)
void SetSoundVolume(std::shared_ptr<Sound> sound, float volume) {
    if (!sound) return;

    Commands::SetSoundVolume cmd;
    cmd.sound_id = sound->GetSoundId();
    cmd.volume = volume;
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Set sound pan (fire and forget)
void SetSoundPan(std::shared_ptr<Sound> sound, float pan) {
    if (!sound) return;

    Commands::SetSoundPan cmd;
    cmd.sound_id = sound->GetSoundId();
    cmd.pan = pan;
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Set sound looping (fire and forget)
void SetSoundLooping(std::shared_ptr<Sound> sound, bool loop) {
    if (!sound) return;

    Commands::SetSoundLooping cmd;
    cmd.sound_id = sound->GetSoundId();
    cmd.loop = loop;
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Set sound position (fire and forget)
void SetSoundPosition(std::shared_ptr<Sound> sound, float seconds) {
    if (!sound) return;

    Commands::SetSoundPosition cmd;
    cmd.sound_id = sound->GetSoundId();
    cmd.seconds = seconds;
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Rewind sound (fire and forget)
void RewindSound(std::shared_ptr<Sound> sound) {
    if (!sound) return;

    Commands::RewindSound cmd;
    cmd.sound_id = sound->GetSoundId();
    sound->GetThread()->EnqueueCommand(std::move(cmd));
}

// Query sound info (blocking - uses promise)
sol::table QuerySoundInfo(sol::this_state s, std::shared_ptr<Sound> sound) {
    sol::state_view lua(s);

    if (!sound) {
        return lua.create_table();
    }

    try {
        // Create promise for blocking call
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        // Create command
        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        // Enqueue command
        sound->GetThread()->EnqueueCommand(std::move(cmd));

        // Block until main thread responds
        PayloadMap response = future.get();

        // Convert response to Lua table
        return LuaConversions::PayloadMapToTable(lua, response);
    }
    catch (const std::exception& e) {
        LOG_ERROR("Error querying sound info: {}", e.what());
        return lua.create_table();
    }
}

// Individual query functions (each queries separately for simplicity)
bool IsSoundPlaying(std::shared_ptr<Sound> sound) {
    if (!sound) return false;

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        PayloadMap response = future.get();
        return std::get<bool>(response.at("is_playing"));
    } catch (...) {
        return false;
    }
}

float GetSoundVolume(std::shared_ptr<Sound> sound) {
    if (!sound) return 0.0f;

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        PayloadMap response = future.get();
        return static_cast<float>(std::get<double>(response.at("volume")));
    } catch (...) {
        return 0.0f;
    }
}

float GetSoundPan(std::shared_ptr<Sound> sound) {
    if (!sound) return 0.0f;

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        PayloadMap response = future.get();
        return static_cast<float>(std::get<double>(response.at("pan")));
    } catch (...) {
        return 0.0f;
    }
}

bool IsSoundLooping(std::shared_ptr<Sound> sound) {
    if (!sound) return false;

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        PayloadMap response = future.get();
        return std::get<bool>(response.at("looping"));
    } catch (...) {
        return false;
    }
}

float GetSoundPosition(std::shared_ptr<Sound> sound) {
    if (!sound) return 0.0f;

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        PayloadMap response = future.get();
        return static_cast<float>(std::get<double>(response.at("position")));
    } catch (...) {
        return 0.0f;
    }
}

float GetSoundLength(std::shared_ptr<Sound> sound) {
    if (!sound) return 0.0f;

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QuerySoundInfo cmd;
        cmd.requesting_thread_id = sound->GetThread()->GetId();
        cmd.request_id = sound->GetThread()->AllocateRequestId();
        cmd.sound_id = sound->GetSoundId();
        cmd.promise = promise;

        sound->GetThread()->EnqueueCommand(std::move(cmd));
        PayloadMap response = future.get();
        return static_cast<float>(std::get<double>(response.at("length")));
    } catch (...) {
        return 0.0f;
    }
}

// Set master volume (fire and forget)
void SetMasterVolume(sol::this_state s, float volume) {
    sol::state_view lua(s);

    // Get LuaThread pointer from registry
    void* ptr = lua.registry()["__luathread_ptr"];
    LuaThread* thread = static_cast<LuaThread*>(ptr);

    if (!thread) return;

    Commands::SetMasterVolume cmd;
    cmd.volume = volume;
    thread->EnqueueCommand(std::move(cmd));
}

// Get master volume (blocking - uses promise)
float GetMasterVolume(sol::this_state s) {
    sol::state_view lua(s);

    // Get LuaThread pointer from registry
    void* ptr = lua.registry()["__luathread_ptr"];
    LuaThread* thread = static_cast<LuaThread*>(ptr);

    if (!thread) return 1.0f;

    try {
        // Create promise for blocking call
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        // Create command
        Commands::QueryMasterVolume cmd;
        cmd.requesting_thread_id = thread->GetId();
        cmd.request_id = thread->AllocateRequestId();
        cmd.promise = promise;

        // Enqueue command
        thread->EnqueueCommand(std::move(cmd));

        // Block until main thread responds
        PayloadMap response = future.get();

        return static_cast<float>(std::get<double>(response.at("volume")));
    }
    catch (const std::exception& e) {
        LOG_ERROR("Error querying master volume: {}", e.what());
        return 1.0f;
    }
}

void SetupBindings(sol::state& lua) {
    // Register Sound usertype
    lua.new_usertype<Sound>("Sound",
        sol::no_constructor,
        "play", &PlaySound,
        "stop", &StopSound,
        "pause", &PauseSound,
        "is_playing", &IsSoundPlaying,
        "set_volume", &SetSoundVolume,
        "get_volume", &GetSoundVolume,
        "set_pan", &SetSoundPan,
        "get_pan", &GetSoundPan,
        "set_looping", &SetSoundLooping,
        "is_looping", &IsSoundLooping,
        "rewind", &RewindSound,
        "get_length", &GetSoundLength,
        "get_position", &GetSoundPosition,
        "set_position", &SetSoundPosition,
        "get_info", &QuerySoundInfo,
        "unload", &UnloadSound
    );

    // Register audio table with functions
    auto audio_table = lua.create_table();

    audio_table["load"] = LoadSound;
    audio_table["play"] = PlaySound;
    audio_table["stop"] = StopSound;
    audio_table["pause"] = PauseSound;
    audio_table["is_playing"] = IsSoundPlaying;
    audio_table["set_volume"] = SetSoundVolume;
    audio_table["get_volume"] = GetSoundVolume;
    audio_table["set_pan"] = SetSoundPan;
    audio_table["get_pan"] = GetSoundPan;
    audio_table["set_looping"] = SetSoundLooping;
    audio_table["is_looping"] = IsSoundLooping;
    audio_table["rewind"] = RewindSound;
    audio_table["get_length"] = GetSoundLength;
    audio_table["get_position"] = GetSoundPosition;
    audio_table["set_position"] = SetSoundPosition;
    audio_table["get_info"] = QuerySoundInfo;
    audio_table["unload"] = UnloadSound;
    audio_table["set_master_volume"] = SetMasterVolume;
    audio_table["get_master_volume"] = GetMasterVolume;

    lua["audio"] = audio_table;

    LOG_INFO("Audio bindings registered (command-based)");
}

} // namespace AudioBindings
