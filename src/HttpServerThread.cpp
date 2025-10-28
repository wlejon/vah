#include "HttpServerThread.h"
#include "Logger.h"
#include <httplib.h>

HttpServerThread::HttpServerThread(const std::string& host, int port,
                                   moodycamel::ConcurrentQueue<Command>* command_queue)
    : host_(host)
    , port_(port)
    , mcp_handler_thread_id_(3)  // Default to thread 3 for MCP server
    , should_stop_(false)
    , command_queue_(command_queue)
    , next_request_id_(1)
{
}

HttpServerThread::~HttpServerThread() {
    Stop();
    Join();
}

void HttpServerThread::Start() {
    thread_ = std::make_unique<std::thread>(&HttpServerThread::ThreadMain, this);
}

void HttpServerThread::Stop() {
    should_stop_ = true;
    if (server_) {
        server_->stop();
    }
}

void HttpServerThread::Join() {
    if (thread_ && thread_->joinable()) {
        thread_->join();
    }
}

HttpResponse HttpServerThread::WaitForResponse(int request_id) {
    // 30 second timeout to prevent DoS from slow/unresponsive Lua handlers
    constexpr auto timeout_duration = std::chrono::seconds(30);
    auto start_time = std::chrono::steady_clock::now();
    auto last_cleanup = start_time;

    // Poll response queue and wait for our response
    while (!should_stop_) {
        // Check if timeout elapsed
        auto now = std::chrono::steady_clock::now();
        auto elapsed = now - start_time;
        if (elapsed >= timeout_duration) {
            LOG_ERROR("HTTP request {} timed out after 30 seconds", request_id);
            return {request_id, 504, "application/json", R"({"error": "Gateway Timeout"})"};
        }

        // Periodic cleanup of stale responses (every 5 seconds)
        if (now - last_cleanup >= std::chrono::seconds(5)) {
            CleanupStaleResponses();
            last_cleanup = now;
        }

        // Check completed responses
        {
            std::lock_guard<std::mutex> lock(pending_mutex_);
            auto it = completed_responses_.find(request_id);
            if (it != completed_responses_.end()) {
                HttpResponse response = std::move(it->second.response);
                completed_responses_.erase(it);
                return response;
            }
        }

        // Process any responses from queue
        HttpResponse incoming_response;
        while (response_queue_.try_dequeue(incoming_response)) {
            std::lock_guard<std::mutex> lock(pending_mutex_);
            TimestampedResponse timestamped;
            timestamped.response = std::move(incoming_response);
            timestamped.timestamp = std::chrono::steady_clock::now();
            completed_responses_[timestamped.response.request_id] = std::move(timestamped);
            pending_cv_.notify_all();
        }

        // Brief wait before retry
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    // Server shutdown
    return {request_id, 503, "application/json", R"({"error": "Service Unavailable"})"};
}

void HttpServerThread::CleanupStaleResponses() {
    // Remove responses older than 60 seconds (twice the timeout)
    constexpr auto max_age = std::chrono::seconds(60);
    auto now = std::chrono::steady_clock::now();

    std::lock_guard<std::mutex> lock(pending_mutex_);
    for (auto it = completed_responses_.begin(); it != completed_responses_.end(); ) {
        if (now - it->second.timestamp >= max_age) {
            LOG_WARN("Cleaning up stale HTTP response for request {}", it->first);
            it = completed_responses_.erase(it);
        } else {
            ++it;
        }
    }
}

void HttpServerThread::SetupRoutes() {
    // POST /mcp - Handle MCP requests
    server_->Post("/mcp", [this](const httplib::Request& req, httplib::Response& res) {
        int request_id = next_request_id_++;

        LOG_INFO("HTTP: Received POST /mcp (request_id={})", request_id);

        // Send command to MCP handler thread
        Commands::HttpRequest cmd;
        cmd.request_id = request_id;
        cmd.method = "POST";
        cmd.path = "/mcp";
        cmd.body = req.body;
        cmd.target_thread_id = mcp_handler_thread_id_;

        // Copy headers
        for (const auto& [key, value] : req.headers) {
            cmd.headers[key] = value;
        }

        command_queue_->enqueue(std::move(cmd));

        // Wait for response
        HttpResponse http_response = WaitForResponse(request_id);

        // Return HTTP response
        res.status = http_response.status_code;
        res.set_content(http_response.body, http_response.content_type);

        // Set custom headers
        for (const auto& [key, value] : http_response.headers) {
            res.set_header(key, value);
        }
    });

    // GET /mcp - Handle health checks and SSE streams
    server_->Get("/mcp", [this](const httplib::Request& req, httplib::Response& res) {
        int request_id = next_request_id_++;

        LOG_INFO("HTTP: Received GET /mcp (request_id={})", request_id);

        // Send command to MCP handler thread
        Commands::HttpRequest cmd;
        cmd.request_id = request_id;
        cmd.method = "GET";
        cmd.path = "/mcp";
        cmd.body = req.body;
        cmd.target_thread_id = mcp_handler_thread_id_;

        // Copy headers
        for (const auto& [key, value] : req.headers) {
            cmd.headers[key] = value;
        }

        command_queue_->enqueue(std::move(cmd));

        // Wait for response
        HttpResponse http_response = WaitForResponse(request_id);

        // Return HTTP response
        res.status = http_response.status_code;
        res.set_content(http_response.body, http_response.content_type);

        // Set custom headers
        for (const auto& [key, value] : http_response.headers) {
            res.set_header(key, value);
        }
    });

    // DELETE /mcp - Handle session termination
    server_->Delete("/mcp", [this](const httplib::Request& req, httplib::Response& res) {
        int request_id = next_request_id_++;

        LOG_INFO("HTTP: Received DELETE /mcp (request_id={})", request_id);

        // Send command to MCP handler thread
        Commands::HttpRequest cmd;
        cmd.request_id = request_id;
        cmd.method = "DELETE";
        cmd.path = "/mcp";
        cmd.body = req.body;
        cmd.target_thread_id = mcp_handler_thread_id_;

        // Copy headers
        for (const auto& [key, value] : req.headers) {
            cmd.headers[key] = value;
        }

        command_queue_->enqueue(std::move(cmd));

        // Wait for response
        HttpResponse http_response = WaitForResponse(request_id);

        // Return HTTP response
        res.status = http_response.status_code;
        res.set_content(http_response.body, http_response.content_type);

        // Set custom headers
        for (const auto& [key, value] : http_response.headers) {
            res.set_header(key, value);
        }
    });
}

void HttpServerThread::ThreadMain() {
    LOG_INFO("HTTP server thread starting on {}:{}", host_, port_);

    server_ = std::make_unique<httplib::Server>();

    // Setup routes
    SetupRoutes();

    // Start listening (this blocks until Stop() is called)
    LOG_INFO("HTTP server listening on {}:{}", host_, port_);

    if (!server_->listen(host_, port_)) {
        LOG_ERROR("HTTP server failed to start on {}:{}", host_, port_);
    }

    LOG_INFO("HTTP server thread stopped");
}
