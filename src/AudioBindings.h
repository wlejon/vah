#pragma once

#include <sol/sol.hpp>

/**
 * AudioBindings - Lua bindings for audio playback using miniaudio
 *
 * Provides game-oriented audio functionality:
 * - Load/unload sounds from files
 * - Play sounds with volume, pan, and looping control
 * - Stop and control playing sounds
 * - Master volume control
 *
 * The audio engine is automatically initialized on first use.
 */
namespace AudioBindings {
    void SetupBindings(sol::state& lua);
}
