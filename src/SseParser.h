#pragma once

#include <string>
#include <functional>
#include <sol/sol.hpp>

class LuaThread;

class SseParser {
public:
    using EventCallback = std::function<void(std::string event, sol::object data)>;
    using ErrorCallback = std::function<void(std::string error)>;

    /**
     * Creates an SSE parser that processes Server-Sent Events from a raw byte stream.
     *
     * @param lua The Lua state for creating sol::objects
     * @param on_event Callback invoked when a complete event is parsed
     * @param on_error Optional callback invoked when parsing errors occur
     * @param thread Optional LuaThread pointer for cancellation support
     * @param max_buffer_size Maximum buffer size to prevent unbounded growth (default 10MB)
     */
    SseParser(
        sol::state_view lua,
        EventCallback on_event,
        ErrorCallback on_error = nullptr,
        LuaThread* thread = nullptr,
        size_t max_buffer_size = 10 * 1024 * 1024
    );

    /**
     * Processes a chunk of data from the HTTP stream.
     * Returns false if processing should stop (due to error, buffer overflow, or cancellation).
     * Returns true to continue streaming.
     */
    bool ProcessChunk(const char* data, size_t len);

private:
    sol::state_view lua_;
    EventCallback on_event_;
    ErrorCallback on_error_;
    LuaThread* thread_;
    size_t max_buffer_size_;

    std::string buffer_;
    std::string event_type_;
    std::string event_data_;

    void ProcessLine(const std::string& line);
    void EmitEvent();
};
