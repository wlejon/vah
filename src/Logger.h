#pragma once
#include <spdlog/spdlog.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <memory>
#include <fstream>
#include <filesystem>

class Logger {
private:
    static std::shared_ptr<spdlog::logger> instance;

public:
    static void Initialize() {
        if (!instance) {
            try {
                // Ensure logs directory exists
                std::filesystem::create_directories("logs");

                // Truncate the log file from previous run
                std::ofstream("logs/log.txt", std::ios::trunc).close();

                // Create a rotating file logger using configuration constants
                instance = spdlog::rotating_logger_mt("vah_logger", "logs/log.txt", 1024 * 1024 * 5, 3);
                instance->set_level(spdlog::level::debug);
                instance->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
                instance->flush_on(spdlog::level::debug);
            }
            catch (const spdlog::spdlog_ex&) {
                // If logging fails, silently continue without crashing
            }
        }
    }

    static std::shared_ptr<spdlog::logger> Get() {
        if (!instance) {
            Initialize();
        }
        return instance;
    }

    static void Shutdown() {
        if (instance) {
            instance->flush();
            instance.reset();
        }
        spdlog::shutdown();
    }
};

#define LOG_DEBUG(...) if (Logger::Get()) Logger::Get()->debug(__VA_ARGS__)
#define LOG_INFO(...) if (Logger::Get()) Logger::Get()->info(__VA_ARGS__)
#define LOG_WARN(...) if (Logger::Get()) Logger::Get()->warn(__VA_ARGS__)
#define LOG_ERROR(...) if (Logger::Get()) Logger::Get()->error(__VA_ARGS__)
#define LOG_CRITICAL(...) if (Logger::Get()) Logger::Get()->critical(__VA_ARGS__)