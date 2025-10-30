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


void HttpServerThread::SetupRoutes() {
    // POST /mcp - Handle MCP requests
    server_->Post("/mcp", [this](const httplib::Request& req, httplib::Response& res) {
        int request_id = next_request_id_++;

        LOG_INFO("HTTP: Received POST /mcp (request_id={})", request_id);

        // Create promise for response (promise-in-command pattern)
        auto promise = std::make_shared<std::promise<Commands::HttpResponse>>();
        auto future = promise->get_future();

        // Send command to MCP handler thread
        Commands::HttpRequest cmd;
        cmd.request_id = request_id;
        cmd.method = "POST";
        cmd.path = "/mcp";
        cmd.body = req.body;
        cmd.target_thread_id = mcp_handler_thread_id_;
        cmd.promise = promise;

        // Copy headers
        for (const auto& [key, value] : req.headers) {
            cmd.headers[key] = value;
        }

        command_queue_->enqueue(std::move(cmd));

        // Block waiting for Lua thread to set promise (synchronous)
        Commands::HttpResponse http_response = future.get();

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

        // Create promise for response (promise-in-command pattern)
        auto promise = std::make_shared<std::promise<Commands::HttpResponse>>();
        auto future = promise->get_future();

        // Send command to MCP handler thread
        Commands::HttpRequest cmd;
        cmd.request_id = request_id;
        cmd.method = "GET";
        cmd.path = "/mcp";
        cmd.body = req.body;
        cmd.target_thread_id = mcp_handler_thread_id_;
        cmd.promise = promise;

        // Copy headers
        for (const auto& [key, value] : req.headers) {
            cmd.headers[key] = value;
        }

        command_queue_->enqueue(std::move(cmd));

        // Block waiting for Lua thread to set promise (synchronous)
        Commands::HttpResponse http_response = future.get();

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

        // Create promise for response (promise-in-command pattern)
        auto promise = std::make_shared<std::promise<Commands::HttpResponse>>();
        auto future = promise->get_future();

        // Send command to MCP handler thread
        Commands::HttpRequest cmd;
        cmd.request_id = request_id;
        cmd.method = "DELETE";
        cmd.path = "/mcp";
        cmd.body = req.body;
        cmd.target_thread_id = mcp_handler_thread_id_;
        cmd.promise = promise;

        // Copy headers
        for (const auto& [key, value] : req.headers) {
            cmd.headers[key] = value;
        }

        command_queue_->enqueue(std::move(cmd));

        // Block waiting for Lua thread to set promise (synchronous)
        Commands::HttpResponse http_response = future.get();

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
