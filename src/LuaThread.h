#pragma once

#include <thread>
#include <atomic>
#include <memory>
#include <string>
#include <functional>
#include <unordered_map>
#include <unordered_set>
#include <sol/sol.hpp>
#include <moodycamel/concurrentqueue.h>
#include "Commands.h"
#include "InputState.h"

// Forward declarations
namespace httplib { class Server; }
class DataStore;

class LuaThread {
public:
    enum class State {
        Starting,
        Running,
        Paused,
        Stopping,
        Stopped,
        Error
    };

    LuaThread(int id, const std::string& script_path,
              moodycamel::ConcurrentQueue<Command>* command_queue,
              moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue,
              DataStore* data_store);
    ~LuaThread();

    // Start the thread (non-blocking)
    void Start();

    // Request thread to stop
    void Stop();

    // Pause/Resume
    void Pause();
    void Resume();

    // Save/Load hooks
    sol::object CallSaveHook();
    void CallLoadHook(const sol::object& data);
    void LoadFromLuaFile(const std::string& file_path);

    // Getters
    int GetId() const { return id_; }
    State GetState() const { return state_.load(std::memory_order_acquire); }
    bool IsRunning() const { return state_.load(std::memory_order_acquire) == State::Running; }
    bool ShouldStop() const { return should_stop_.load(std::memory_order_acquire); }
    std::string GetError() const { return error_message_; }
    std::string GetScriptPath() const { return script_path_; }
    double GetUptime() const;  // Returns uptime in seconds

    // Parent/child tracking
    void SetParent(int parent_id, int parent_request_id);
    bool HasParent() const { return parent_thread_id_ != 0; }
    int GetParentId() const { return parent_thread_id_; }
    int GetParentRequestId() const { return parent_request_id_; }

    // Response queue access (for main thread to push responses)
    moodycamel::ConcurrentQueue<Response>* GetResponseQueue() { return response_queue_.get(); }

    // HTTP server management (for stopping blocking server on shutdown)
    void SetActiveHttpServer(httplib::Server* server);
    void ClearActiveHttpServer();

    // Wait for thread to finish
    void Join();

private:
    void ThreadMain();
    void SetupLuaBindings();
    void ProcessResponses();

    int id_;
    std::string script_path_;
    std::atomic<State> state_;
    std::atomic<bool> should_stop_;
    std::atomic<bool> is_paused_;
    std::chrono::steady_clock::time_point start_time_;

    std::unique_ptr<std::thread> thread_;
    std::unique_ptr<sol::state> lua_;

    moodycamel::ConcurrentQueue<Command>* command_queue_;
    moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue_;
    DataStore* data_store_;
    std::unique_ptr<moodycamel::ConcurrentQueue<Response>> response_queue_;

    struct PendingRequest {
        uint64_t request_id;
        sol::function callback;
        std::string operation;
    };
    std::unordered_map<uint64_t, PendingRequest> pending_requests_;
    uint64_t next_request_id_;

    int parent_thread_id_;
    int parent_request_id_;

    std::unordered_map<std::string, sol::function> event_handlers_;

    std::string error_message_;

    // Active HTTP server (if any) for this thread - used to stop blocking listen() during shutdown
    // Using mutex instead of atomic to safely handle server pointer lifecycle
    std::mutex http_server_mutex_;
    httplib::Server* active_http_server_;
};
