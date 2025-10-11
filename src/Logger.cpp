#include "Logger.h"
#include <filesystem>

std::shared_ptr<spdlog::logger> Logger::instance = nullptr;

namespace {
    struct LoggerInitializer {
        LoggerInitializer() {
            // Ensure logs directory exists
            std::filesystem::create_directories("logs");
            Logger::Initialize();
        }
        ~LoggerInitializer() {
            Logger::Shutdown();
        }
    };

    static LoggerInitializer loggerInitializer;
}