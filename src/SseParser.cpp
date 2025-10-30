#include "SseParser.h"
#include "JsonBindings.h"
#include "LuaThread.h"
#include <nlohmann/json.hpp>

SseParser::SseParser(
    sol::state_view lua,
    EventCallback on_event,
    ErrorCallback on_error,
    LuaThread* thread,
    size_t max_buffer_size)
    : lua_(lua)
    , on_event_(std::move(on_event))
    , on_error_(std::move(on_error))
    , thread_(thread)
    , max_buffer_size_(max_buffer_size)
{
}

bool SseParser::ProcessChunk(const char* data, size_t len) {
    // Check if thread is stopping (abort the stream)
    if (thread_ && thread_->ShouldStop()) {
        return false;
    }

    // Check buffer size to prevent unbounded memory growth
    if (buffer_.size() + len > max_buffer_size_) {
        if (on_error_) {
            on_error_("Buffer size exceeded maximum limit (10MB)");
        }
        return false;
    }

    buffer_.append(data, len);

    // Process complete lines
    size_t pos;
    while ((pos = buffer_.find('\n')) != std::string::npos) {
        std::string line = buffer_.substr(0, pos);
        buffer_ = buffer_.substr(pos + 1);

        // Remove \r if present
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }

        try {
            ProcessLine(line);
        }
        catch (const std::exception& e) {
            if (on_error_) {
                on_error_(std::string("Parse error: ") + e.what());
            }
            return false; // Stop streaming on parse error
        }
    }

    return true; // Continue streaming
}

void SseParser::ProcessLine(const std::string& line) {
    if (line.empty()) {
        // Empty line marks end of event
        if (!event_data_.empty()) {
            EmitEvent();
        }
        event_type_.clear();
        event_data_.clear();
    }
    else if (line.find("event: ") == 0) {
        event_type_ = line.substr(7);
    }
    else if (line.find("data: ") == 0) {
        if (!event_data_.empty()) {
            event_data_ += "\n";
        }
        event_data_ += line.substr(6);
    }
    // Ignore other SSE fields (id, retry, etc.)
}

void SseParser::EmitEvent() {
    // Try to parse as JSON
    sol::object lua_data = sol::nil;
    try {
        auto json_obj = nlohmann::json::parse(event_data_);
        lua_data = JsonBindings::JsonToLua(lua_, json_obj);
    } catch (...) {
        // If not JSON, pass as string
        lua_data = sol::make_object(lua_, event_data_);
    }

    // Call Lua callback with event type and data
    // This may throw if the Lua callback fails - exception propagates to ProcessChunk
    std::string evt = event_type_.empty() ? "message" : event_type_;
    on_event_(evt, lua_data);
}
