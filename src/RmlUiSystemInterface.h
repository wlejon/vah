#pragma once

#include <RmlUi/Core/SystemInterface.h>
#include <chrono>
#include "Logger.h"

class RmlUiSystemInterface : public Rml::SystemInterface {
public:
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
};
