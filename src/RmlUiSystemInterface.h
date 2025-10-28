#pragma once

#include <RmlUi/Core/SystemInterface.h>
#include <SDL2/SDL.h>
#include <chrono>
#include <unordered_map>
#include "Logger.h"

class RmlUiSystemInterface : public Rml::SystemInterface {
public:
    RmlUiSystemInterface() {
        // Create SDL cursor type map
        cursor_type_map_[""] = SDL_SYSTEM_CURSOR_ARROW;  // Default
        cursor_type_map_["arrow"] = SDL_SYSTEM_CURSOR_ARROW;
        cursor_type_map_["pointer"] = SDL_SYSTEM_CURSOR_HAND;
        cursor_type_map_["text"] = SDL_SYSTEM_CURSOR_IBEAM;
        cursor_type_map_["move"] = SDL_SYSTEM_CURSOR_SIZEALL;
        cursor_type_map_["resize"] = SDL_SYSTEM_CURSOR_SIZENWSE;
        cursor_type_map_["wait"] = SDL_SYSTEM_CURSOR_WAIT;
        cursor_type_map_["crosshair"] = SDL_SYSTEM_CURSOR_CROSSHAIR;
        cursor_type_map_["progress"] = SDL_SYSTEM_CURSOR_WAITARROW;

        current_cursor_name_ = "";
    }

    ~RmlUiSystemInterface() {
        // Free all cached cursors
        for (auto& [name, cursor] : cursor_cache_) {
            if (cursor) {
                SDL_FreeCursor(cursor);
            }
        }
    }

    bool LogMessage(Rml::Log::Type type, const Rml::String& message) override {
        // Log to our file logger
        switch (type) {
            case Rml::Log::LT_ERROR:
                LOG_ERROR("[RmlUi] {}", message);
                break;
            case Rml::Log::LT_WARNING:
                LOG_WARN("[RmlUi] {}", message);
                break;
            case Rml::Log::LT_INFO:
                LOG_INFO("[RmlUi] {}", message);
                break;
            case Rml::Log::LT_DEBUG:
                LOG_DEBUG("[RmlUi] {}", message);
                break;
            default:
                LOG_INFO("[RmlUi] {}", message);
                break;
        }

        // Return true to continue execution (false would break into debugger)
        return true;
    }

    double GetElapsedTime() override {
        static auto start = std::chrono::high_resolution_clock::now();
        auto now = std::chrono::high_resolution_clock::now();
        return std::chrono::duration<double>(now - start).count();
    }

    void SetMouseCursor(const Rml::String& cursor_name) override {
        // Only change cursor if it's different from the current one
        if (cursor_name == current_cursor_name_) {
            return;
        }

        // Check if cursor is already cached
        auto cache_it = cursor_cache_.find(cursor_name);
        SDL_Cursor* cursor = nullptr;

        if (cache_it != cursor_cache_.end()) {
            // Use cached cursor
            cursor = cache_it->second;
        } else {
            // Find the SDL cursor type
            auto type_it = cursor_type_map_.find(cursor_name);
            SDL_SystemCursor sdl_cursor_type = (type_it != cursor_type_map_.end())
                ? type_it->second
                : SDL_SYSTEM_CURSOR_ARROW;

            // Create and cache the new cursor
            cursor = SDL_CreateSystemCursor(sdl_cursor_type);
            cursor_cache_[cursor_name] = cursor;
        }

        // Set the cursor
        SDL_SetCursor(cursor);
        current_cursor_name_ = cursor_name;
    }

private:
    std::unordered_map<Rml::String, SDL_SystemCursor> cursor_type_map_;
    std::unordered_map<Rml::String, SDL_Cursor*> cursor_cache_;
    Rml::String current_cursor_name_;
};
