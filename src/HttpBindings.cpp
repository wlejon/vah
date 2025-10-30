#include "HttpBindings.h"
#include "Logger.h"
#include "JsonBindings.h"
#include "LuaThread.h"
#include "SseParser.h"
#include <httplib.h>
#include <sstream>
#include <regex>

namespace HttpBindings {

// HTTP timeout constants
constexpr int DEFAULT_CONNECTION_TIMEOUT = 30;  // 30 seconds
constexpr int DEFAULT_READ_TIMEOUT = 30;         // 30 seconds
constexpr int STREAMING_READ_TIMEOUT = 300;      // 5 minutes for long streams

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

        // Check for HTTPS support
        if (parts.scheme == "https") {
            #ifndef CPPHTTPLIB_OPENSSL_SUPPORT
                throw std::runtime_error("HTTPS not supported in this build (OpenSSL support required)");
            #endif
        }
    } else {
        throw std::runtime_error("Invalid URL format");
    }

    return parts;
}

// Parse SSE stream and invoke Lua callback for each event
bool ParseSSEStream(
    const std::string& scheme,
    const std::string& host,
    int port,
    const std::string& path,
    const httplib::Headers& headers,
    sol::function on_event,
    sol::optional<sol::function> on_error,
    LuaThread* thread)
{
    // Create appropriate client based on scheme
    std::unique_ptr<httplib::Client> client;
    #ifdef CPPHTTPLIB_OPENSSL_SUPPORT
        if (scheme == "https") {
            client = std::make_unique<httplib::SSLClient>(host, port);
        } else {
            client = std::make_unique<httplib::Client>(host, port);
        }
    #else
        client = std::make_unique<httplib::Client>(host, port);
    #endif

    client->set_connection_timeout(DEFAULT_CONNECTION_TIMEOUT);
    client->set_read_timeout(STREAMING_READ_TIMEOUT);

    // Create SSE parser with callbacks
    sol::state_view lua(on_event.lua_state());
    SseParser::ErrorCallback error_callback = nullptr;
    if (on_error) {
        error_callback = [on_error](const std::string& error) {
            (*on_error)(error);
        };
    }

    SseParser parser(
        lua,
        [on_event](std::string event, sol::object data) {
            on_event(event, data);
        },
        error_callback,
        thread
    );

    auto res = client->Get(path, headers,
        [&parser](const char* data, size_t len) {
            return parser.ProcessChunk(data, len);
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
        int timeout = DEFAULT_READ_TIMEOUT;
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
                url_parts.scheme,
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
        std::unique_ptr<httplib::Client> client;
        #ifdef CPPHTTPLIB_OPENSSL_SUPPORT
            if (url_parts.scheme == "https") {
                client = std::make_unique<httplib::SSLClient>(url_parts.host, url_parts.port);
            } else {
                client = std::make_unique<httplib::Client>(url_parts.host, url_parts.port);
            }
        #else
            client = std::make_unique<httplib::Client>(url_parts.host, url_parts.port);
        #endif
        client->set_connection_timeout(timeout);

        auto res = client->Get(url_parts.path, headers);

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
        int timeout = DEFAULT_READ_TIMEOUT;
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

            // Create appropriate client based on scheme
            std::unique_ptr<httplib::Client> client;
            #ifdef CPPHTTPLIB_OPENSSL_SUPPORT
                if (url_parts.scheme == "https") {
                    client = std::make_unique<httplib::SSLClient>(url_parts.host, url_parts.port);
                } else {
                    client = std::make_unique<httplib::Client>(url_parts.host, url_parts.port);
                }
            #else
                client = std::make_unique<httplib::Client>(url_parts.host, url_parts.port);
            #endif
            client->set_connection_timeout(DEFAULT_CONNECTION_TIMEOUT);
            client->set_read_timeout(timeout);

            // Create SSE parser with callbacks
            SseParser::ErrorCallback error_callback = nullptr;
            if (on_error) {
                error_callback = [on_error](const std::string& error) {
                    (*on_error)(error);
                };
            }

            SseParser parser(
                lua,
                [on_event](std::string event, sol::object data) {
                    (*on_event)(event, data);
                },
                error_callback,
                thread
            );

            auto res = client->Post(url_parts.path, headers, body, content_type,
                [&parser](const char* data, size_t len) {
                    return parser.ProcessChunk(data, len);
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
        std::unique_ptr<httplib::Client> client;
        #ifdef CPPHTTPLIB_OPENSSL_SUPPORT
            if (url_parts.scheme == "https") {
                client = std::make_unique<httplib::SSLClient>(url_parts.host, url_parts.port);
            } else {
                client = std::make_unique<httplib::Client>(url_parts.host, url_parts.port);
            }
        #else
            client = std::make_unique<httplib::Client>(url_parts.host, url_parts.port);
        #endif
        client->set_connection_timeout(timeout);

        auto res = client->Post(url_parts.path, headers, body, content_type);

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
        } else if (method == "PUT") {
            server_->Put(pattern, cpp_handler);
        } else if (method == "DELETE") {
            server_->Delete(pattern, cpp_handler);
        } else if (method == "PATCH") {
            server_->Patch(pattern, cpp_handler);
        } else if (method == "OPTIONS") {
            server_->Options(pattern, cpp_handler);
        } else {
            LOG_ERROR("Unsupported HTTP method: {}", method);
            throw std::runtime_error("Unsupported HTTP method: " + method);
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
