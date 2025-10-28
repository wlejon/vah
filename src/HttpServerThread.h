#pragma once

#include <thread>
#include <atomic>
#include <memory>
#include <string>
#include <unordered_map>
#include <mutex>
#include <condition_variable>
#include <moodycamel/concurrentqueue.h>
#include "Commands.h"

// Forward declarations
namespace httplib { class Server; }

// HTTP response structure
struct HttpResponse {
    int request_id;
    int status_code;
    std::string content_type;
    std::string body;
    std::unordered_map<std::string, std::string> headers;
};

// Internal structure for tracking response timestamps
struct TimestampedResponse {
    HttpResponse response;
    std::chrono::steady_clock::time_point timestamp;
};

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

    // Get response queue (for Lua threads to send responses back)
    moodycamel::ConcurrentQueue<HttpResponse>* GetResponseQueue() { return &response_queue_; }

    // Set the target thread ID for MCP requests (which Lua thread handles MCP)
    void SetMcpHandlerThreadId(int thread_id) { mcp_handler_thread_id_ = thread_id; }

private:
    void ThreadMain();
    void SetupRoutes();
    HttpResponse WaitForResponse(int request_id);
    void CleanupStaleResponses();

    std::string host_;
    int port_;
    int mcp_handler_thread_id_;  // Which Lua thread handles MCP requests

    std::atomic<bool> should_stop_;
    std::unique_ptr<std::thread> thread_;
    std::unique_ptr<httplib::Server> server_;

    moodycamel::ConcurrentQueue<Command>* command_queue_;
    moodycamel::ConcurrentQueue<HttpResponse> response_queue_;

    // For routing responses back to waiting handlers
    std::atomic<int> next_request_id_;
    std::mutex pending_mutex_;
    std::condition_variable pending_cv_;
    std::unordered_map<int, TimestampedResponse> completed_responses_;
};
