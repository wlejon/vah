#pragma once

#include <RmlUi/Core/SystemInterface.h>
#include <SDL2/SDL.h>
#include <chrono>
#include <unordered_map>
#include "Logger.h"

class RmlUiSystemInterface : public Rml::SystemInterface {
public:
    RmlUiSystemInterface() {
        // Create SDL cursor map
        cursor_map_[""] = SDL_SYSTEM_CURSOR_ARROW;  // Default
        cursor_map_["arrow"] = SDL_SYSTEM_CURSOR_ARROW;
        cursor_map_["pointer"] = SDL_SYSTEM_CURSOR_HAND;
        cursor_map_["text"] = SDL_SYSTEM_CURSOR_IBEAM;
        cursor_map_["move"] = SDL_SYSTEM_CURSOR_SIZEALL;
        cursor_map_["resize"] = SDL_SYSTEM_CURSOR_SIZENWSE;
        cursor_map_["wait"] = SDL_SYSTEM_CURSOR_WAIT;
        cursor_map_["crosshair"] = SDL_SYSTEM_CURSOR_CROSSHAIR;
        cursor_map_["progress"] = SDL_SYSTEM_CURSOR_WAITARROW;

        current_cursor_ = nullptr;
    }

    ~RmlUiSystemInterface() {
        if (current_cursor_) {
            SDL_FreeCursor(current_cursor_);
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

        // Find the SDL cursor type
        auto it = cursor_map_.find(cursor_name);
        SDL_SystemCursor sdl_cursor_type = (it != cursor_map_.end())
            ? it->second
            : SDL_SYSTEM_CURSOR_ARROW;

        // Free the old cursor if it exists
        if (current_cursor_) {
            SDL_FreeCursor(current_cursor_);
        }

        // Create and set the new cursor
        current_cursor_ = SDL_CreateSystemCursor(sdl_cursor_type);
        SDL_SetCursor(current_cursor_);
        current_cursor_name_ = cursor_name;
    }

private:
    std::unordered_map<Rml::String, SDL_SystemCursor> cursor_map_;
    SDL_Cursor* current_cursor_;
    Rml::String current_cursor_name_;
};
