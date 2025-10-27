#include "HttpBindings.h"
#include "Logger.h"
#include "JsonBindings.h"
#include "LuaThread.h"
#include <httplib.h>
#include <sstream>
#include <regex>

namespace HttpBindings {

// URL parsing helper
struct URLParts {
    std::string scheme;
    std::string host;
    int port;
    std::string path;
};

URLParts ParseURL(const std::string& url) {
    URLParts parts;

    // Simple regex for URL parsing
    std::regex url_regex(R"(^(https?):\/\/([^:\/]+)(?::(\d+))?(\/.*)?$)");
    std::smatch matches;

    if (std::regex_match(url, matches, url_regex)) {
        parts.scheme = matches[1].str();
        parts.host = matches[2].str();
        parts.port = matches[3].matched ? std::stoi(matches[3].str()) :
                     (parts.scheme == "https" ? 443 : 80);
        parts.path = matches[4].matched ? matches[4].str() : "/";
    } else {
        throw std::runtime_error("Invalid URL format");
    }

    return parts;
}

// Parse SSE stream and invoke Lua callback for each event
bool ParseSSEStream(
    const std::string& host,
    int port,
    const std::string& path,
    const httplib::Headers& headers,
    sol::function on_event,
    sol::optional<sol::function> on_error,
    LuaThread* thread)
{
    httplib::Client client(host, port);
    client.set_connection_timeout(30);
    client.set_read_timeout(300);  // 5 minutes for long streams

    std::string event_type;
    std::string event_data;
    std::string buffer;

    auto res = client.Get(path, headers,
        [&](const char* data, size_t len) {
            // Check if thread is stopping (abort the stream)
            if (thread && thread->ShouldStop()) {
                return false;
            }

            buffer.append(data, len);

            // Process complete lines
            size_t pos;
            while ((pos = buffer.find('\n')) != std::string::npos) {
                std::string line = buffer.substr(0, pos);
                buffer = buffer.substr(pos + 1);

                // Remove \r if present
                if (!line.empty() && line.back() == '\r') {
                    line.pop_back();
                }

                if (line.empty()) {
                    // Empty line marks end of event
                    if (!event_data.empty()) {
                        try {
                            sol::state_view lua(on_event.lua_state());

                            // Try to parse as JSON
                            sol::object lua_data = sol::nil;
                            try {
                                auto json_obj = nlohmann::json::parse(event_data);
                                lua_data = JsonBindings::JsonToLua(lua, json_obj);
                            } catch (...) {
                                // If not JSON, pass as string
                                lua_data = sol::make_object(lua, event_data);
                            }

                            // Call Lua callback with event type and data
                            std::string evt = event_type.empty() ? "message" : event_type;
                            on_event(evt, lua_data);
                        }
                        catch (const std::exception& e) {
                            if (on_error) {
                                (*on_error)(std::string("Parse error: ") + e.what());
                            }
                            return false; // Stop streaming
                        }
                    }
                    event_type.clear();
                    event_data.clear();
                }
                else if (line.find("event: ") == 0) {
                    event_type = line.substr(7);
                }
                else if (line.find("data: ") == 0) {
                    if (!event_data.empty()) {
                        event_data += "\n";
                    }
                    event_data += line.substr(6);
                }
                // Ignore other SSE fields (id, retry, etc.)
            }

            return true; // Continue streaming
        });

    if (!res) {
        if (on_error) {
            (*on_error)("HTTP request failed: " + httplib::to_string(res.error()));
        }
        return false;
    }

    if (res->status != 200) {
        if (on_error) {
            (*on_error)("HTTP error: " + std::to_string(res->status));
        }
        return false;
    }

    return true;
}

// GET request
std::tuple<sol::object, std::string> Get(
    sol::this_state s,
    const std::string& url,
    sol::optional<sol::table> config)
{
    sol::state_view lua(s);

    try {
        auto url_parts = ParseURL(url);

        // Parse config
        httplib::Headers headers;
        int timeout = 30;
        sol::optional<sol::function> on_event;
        sol::optional<sol::function> on_error;

        if (config) {
            // Parse headers
            if (auto h = config->get<sol::optional<sol::table>>("headers")) {
                for (const auto& pair : h.value()) {
                    sol::object key = pair.first;
                    sol::object value = pair.second;
                    if (key.is<std::string>() && value.is<std::string>()) {
                        headers.emplace(
                            key.as<std::string>(),
                            value.as<std::string>()
                        );
                    }
                }
            }

            // Parse timeout
            if (auto t = config->get<sol::optional<int>>("timeout")) {
                timeout = t.value();
            }

            // Check for streaming
            on_event = config->get<sol::optional<sol::function>>("on_event");
            on_error = config->get<sol::optional<sol::function>>("on_error");
        }

        // Streaming mode
        if (on_event) {
            // Get LuaThread pointer for cancellation support
            void* ptr = lua.registry()["__luathread_ptr"];
            LuaThread* thread = static_cast<LuaThread*>(ptr);

            bool success = ParseSSEStream(
                url_parts.host,
                url_parts.port,
                url_parts.path,
                headers,
                on_event.value(),
                on_error,
                thread
            );

            if (success) {
                return {sol::nil, ""};
            } else {
                return {sol::nil, "Streaming request failed"};
            }
        }

        // Non-streaming mode
        httplib::Client client(url_parts.host, url_parts.port);
        client.set_connection_timeout(timeout);

        auto res = client.Get(url_parts.path, headers);

        if (!res) {
            return {sol::nil, "HTTP request failed: " + httplib::to_string(res.error())};
        }

        // Build response table
        auto response = lua.create_table();
        response["body"] = res->body;
        response["status"] = res->status;

        auto resp_headers = lua.create_table();
        for (const auto& [k, v] : res->headers) {
            resp_headers[k] = v;
        }
        response["headers"] = resp_headers;

        return {response, ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error: ") + e.what()};
    }
}

// POST request
std::tuple<sol::object, std::string> Post(
    sol::this_state s,
    const std::string& url,
    sol::optional<sol::table> config)
{
    sol::state_view lua(s);

    try {
        auto url_parts = ParseURL(url);

        // Parse config
        httplib::Headers headers;
        std::string body;
        std::string content_type = "application/json";
        int timeout = 30;
        sol::optional<sol::function> on_event;
        sol::optional<sol::function> on_error;

        if (config) {
            // Parse headers
            if (auto h = config->get<sol::optional<sol::table>>("headers")) {
                for (const auto& pair : h.value()) {
                    sol::object key = pair.first;
                    sol::object value = pair.second;
                    if (key.is<std::string>() && value.is<std::string>()) {
                        headers.emplace(
                            key.as<std::string>(),
                            value.as<std::string>()
                        );
                    }
                }
            }

            // Parse body
            if (auto b = config->get<sol::optional<std::string>>("body")) {
                body = b.value();
            }

            // Parse timeout
            if (auto t = config->get<sol::optional<int>>("timeout")) {
                timeout = t.value();
            }

            // Check for streaming
            on_event = config->get<sol::optional<sol::function>>("on_event");
            on_error = config->get<sol::optional<sol::function>>("on_error");
        }

        // Streaming mode
        if (on_event) {
            // Get LuaThread pointer for cancellation support
            void* ptr = lua.registry()["__luathread_ptr"];
            LuaThread* thread = static_cast<LuaThread*>(ptr);

            httplib::Client client(url_parts.host, url_parts.port);
            client.set_connection_timeout(30);
            client.set_read_timeout(timeout);

            std::string event_type;
            std::string event_data;
            std::string buffer;

            auto res = client.Post(url_parts.path, headers, body, content_type,
                [&](const char* data, size_t len) {
                    // Check if thread is stopping (abort the stream)
                    if (thread && thread->ShouldStop()) {
                        return false;
                    }

                    buffer.append(data, len);

                    // Process complete lines
                    size_t pos;
                    while ((pos = buffer.find('\n')) != std::string::npos) {
                        std::string line = buffer.substr(0, pos);
                        buffer = buffer.substr(pos + 1);

                        // Remove \r if present
                        if (!line.empty() && line.back() == '\r') {
                            line.pop_back();
                        }

                        if (line.empty()) {
                            // Empty line marks end of event
                            if (!event_data.empty()) {
                                try {
                                    sol::state_view lua(on_event.value().lua_state());

                                    // Try to parse as JSON
                                    sol::object lua_data = sol::nil;
                                    try {
                                        auto json_obj = nlohmann::json::parse(event_data);
                                        lua_data = JsonBindings::JsonToLua(lua, json_obj);
                                    } catch (...) {
                                        // If not JSON, pass as string
                                        lua_data = sol::make_object(lua, event_data);
                                    }

                                    // Call Lua callback with event type and data
                                    std::string evt = event_type.empty() ? "message" : event_type;
                                    on_event.value()(evt, lua_data);
                                }
                                catch (const std::exception& e) {
                                    if (on_error) {
                                        (*on_error)(std::string("Parse error: ") + e.what());
                                    }
                                    return false; // Stop streaming
                                }
                            }
                            event_type.clear();
                            event_data.clear();
                        }
                        else if (line.find("event: ") == 0) {
                            event_type = line.substr(7);
                        }
                        else if (line.find("data: ") == 0) {
                            if (!event_data.empty()) {
                                event_data += "\n";
                            }
                            event_data += line.substr(6);
                        }
                        // Ignore other SSE fields (id, retry, etc.)
                    }

                    return true; // Continue streaming
                });

            if (!res) {
                if (on_error) {
                    (*on_error)("HTTP request failed: " + httplib::to_string(res.error()));
                }
                return {sol::nil, "Streaming request failed"};
            }

            if (res->status != 200) {
                if (on_error) {
                    (*on_error)("HTTP error: " + std::to_string(res->status));
                }
                return {sol::nil, "HTTP error: " + std::to_string(res->status)};
            }

            return {sol::nil, ""};
        }

        // Non-streaming mode
        httplib::Client client(url_parts.host, url_parts.port);
        client.set_connection_timeout(timeout);

        auto res = client.Post(url_parts.path, headers, body, content_type);

        if (!res) {
            return {sol::nil, "HTTP request failed: " + httplib::to_string(res.error())};
        }

        // Build response table
        auto response = lua.create_table();
        response["body"] = res->body;
        response["status"] = res->status;

        auto resp_headers = lua.create_table();
        for (const auto& [k, v] : res->headers) {
            resp_headers[k] = v;
        }
        response["headers"] = resp_headers;

        return {response, ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error: ") + e.what()};
    }
}

// HTTP Server wrapper
class HttpServer {
public:
    HttpServer() : server_(std::make_unique<httplib::Server>()), lua_thread_(nullptr) {}

    void SetRoute(const std::string& method, const std::string& pattern, sol::function handler) {
        LOG_INFO("Registering route: {} {}", method, pattern);

        // Store handler (keep it alive)
        handlers_.push_back(handler);

        auto cpp_handler = [handler](const httplib::Request& req, httplib::Response& res) {
            try {
                sol::state_view lua(handler.lua_state());

                // Build request table
                auto req_table = lua.create_table();
                req_table["method"] = req.method;
                req_table["path"] = req.path;
                req_table["body"] = req.body;

                auto headers_table = lua.create_table();
                for (const auto& [k, v] : req.headers) {
                    headers_table[k] = v;
                }
                req_table["headers"] = headers_table;

                auto params_table = lua.create_table();
                for (const auto& [k, v] : req.params) {
                    params_table[k] = v;
                }
                req_table["params"] = params_table;

                // Call Lua handler
                auto result = handler(req_table);

                // Parse result
                if (result.valid()) {
                    sol::table res_table = result;

                    // Set status
                    if (auto status = res_table.get<sol::optional<int>>("status")) {
                        res.status = status.value();
                    } else {
                        res.status = 200;
                    }

                    // Set body
                    if (auto body = res_table.get<sol::optional<std::string>>("body")) {
                        res.set_content(body.value(), "text/plain");
                    }

                    // Set headers
                    if (auto headers = res_table.get<sol::optional<sol::table>>("headers")) {
                        for (const auto& pair : headers.value()) {
                            sol::object key = pair.first;
                            sol::object value = pair.second;
                            if (key.is<std::string>() && value.is<std::string>()) {
                                res.set_header(key.as<std::string>(), value.as<std::string>());
                            }
                        }
                    }

                    // Check for SSE stream
                    // Since server.listen() blocks on the LuaThread, we're on the correct thread
                    // and can safely call Lua functions
                    if (auto stream = res_table.get<sol::optional<sol::function>>("stream")) {
                        res.set_content_provider(
                            "text/event-stream",
                            [stream = stream.value()](size_t offset, httplib::DataSink& sink) {
                                try {
                                    // Call Lua stream function with a send callback
                                    // This is safe because we're on the LuaThread (server blocks on it)
                                    sol::state_view lua(stream.lua_state());

                                    auto send_fn = [&sink](const std::string& event, const std::string& data) {
                                        std::ostringstream oss;
                                        if (!event.empty()) {
                                            oss << "event: " << event << "\n";
                                        }
                                        oss << "data: " << data << "\n\n";
                                        std::string msg = oss.str();
                                        return sink.write(msg.c_str(), msg.size());
                                    };

                                    stream(send_fn);
                                    return true;
                                }
                                catch (const std::exception& e) {
                                    LOG_ERROR("Stream error: {}", e.what());
                                    return false;
                                }
                            }
                        );
                    }
                }
            }
            catch (const std::exception& e) {
                LOG_ERROR("Handler error: {}", e.what());
                res.status = 500;
                res.set_content("Internal server error", "text/plain");
            }
        };

        if (method == "GET") {
            server_->Get(pattern, cpp_handler);
        } else if (method == "POST") {
            server_->Post(pattern, cpp_handler);
        }
    }

    std::tuple<bool, std::string> Listen(sol::this_state s, const std::string& host, int port) {
        LOG_INFO("Starting HTTP server on {}:{}", host, port);

        // Get LuaThread pointer from Lua registry (lock-free)
        sol::state_view lua(s);
        void* ptr = lua.registry()["__luathread_ptr"];
        lua_thread_ = static_cast<LuaThread*>(ptr);

        if (lua_thread_) {
            // Register this server with the thread (lock-free atomic store)
            lua_thread_->SetActiveHttpServer(server_.get());
        }

        // Listen blocks on this thread (the LuaThread)
        // This is intentional - the server runs on the Lua thread
        bool success = server_->listen(host, port);

        // Unregister when listen returns (lock-free atomic store)
        if (lua_thread_) {
            lua_thread_->ClearActiveHttpServer();
        }

        if (!success) {
            LOG_ERROR("Failed to start server");
            return {false, "Failed to start server"};
        }

        return {true, ""};
    }

    void Stop() {
        if (server_) {
            server_->stop();
        }
    }

    bool IsRunning() const {
        return server_ && server_->is_running();
    }

    ~HttpServer() {
        Stop();
    }

private:
    std::unique_ptr<httplib::Server> server_;
    std::vector<sol::function> handlers_;  // Keep handlers alive
    LuaThread* lua_thread_;  // Non-owning pointer to register/unregister with
};

void SetupBindings(sol::state& lua, LuaThread* thread) {
    // Store LuaThread pointer in registry for lock-free access (used by HttpServer::Listen)
    lua.registry()["__luathread_ptr"] = sol::make_light(thread);

    // Client functions
    auto http_table = lua.create_table();
    http_table["get"] = Get;
    http_table["post"] = Post;
    lua["http"] = http_table;

    // Server class
    lua.new_usertype<HttpServer>("HttpServer",
        sol::constructors<HttpServer()>(),
        "route", &HttpServer::SetRoute,
        "listen", &HttpServer::Listen,
        "stop", &HttpServer::Stop,
        "is_running", &HttpServer::IsRunning
    );
}

} // namespace HttpBindings
