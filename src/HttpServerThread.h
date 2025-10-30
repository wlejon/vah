#pragma once

#include <thread>
#include <atomic>
#include <memory>
#include <string>
#include <moodycamel/concurrentqueue.h>
#include "Commands.h"

// Forward declarations
namespace httplib { class Server; }

class HttpServerThread {
public:
    HttpServerThread(const std::string& host, int port,
                     moodycamel::ConcurrentQueue<Command>* command_queue);
    ~HttpServerThread();

    // Start the HTTP server thread
    void Start();

    // Stop the HTTP server thread
    void Stop();

    // Wait for thread to finish
    void Join();

    // Set the target thread ID for MCP requests (which Lua thread handles MCP)
    void SetMcpHandlerThreadId(int thread_id) { mcp_handler_thread_id_ = thread_id; }

private:
    void ThreadMain();
    void SetupRoutes();

    std::string host_;
    int port_;
    int mcp_handler_thread_id_;  // Which Lua thread handles MCP requests

    std::atomic<bool> should_stop_;
    std::unique_ptr<std::thread> thread_;
    std::unique_ptr<httplib::Server> server_;

    moodycamel::ConcurrentQueue<Command>* command_queue_;
    std::atomic<int> next_request_id_;
};
