#pragma once

#include <thread>
#include <atomic>
#include <memory>
#include <string>
#include <functional>
#include <unordered_map>
#include <sol/sol.hpp>

class CommandQueue;
class ResponseQueue;
template<typename T> class Seqlock;
struct InputState;

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
              CommandQueue* command_queue,
              Seqlock<InputState>* input_seqlock);
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

    // Getters
    int GetId() const { return id_; }
    State GetState() const { return state_.load(); }
    bool IsRunning() const { return state_.load() == State::Running; }
    std::string GetError() const { return error_message_; }
    std::string GetScriptPath() const { return script_path_; }

    // Parent/child tracking
    void SetParent(int parent_id, int parent_request_id);
    bool HasParent() const { return parent_thread_id_ != 0; }
    int GetParentId() const { return parent_thread_id_; }
    int GetParentRequestId() const { return parent_request_id_; }

    // Response queue access (for main thread to push responses)
    ResponseQueue* GetResponseQueue() { return response_queue_.get(); }

    // Wait for thread to finish
    void Join();

private:
    void ThreadMain();
    void SetupLuaBindings();
    void ProcessResponses();
    void ProcessInputEvents();

    int id_;
    std::string script_path_;
    std::atomic<State> state_;
    std::atomic<bool> should_stop_;
    std::atomic<bool> is_paused_;

    std::unique_ptr<std::thread> thread_;
    std::unique_ptr<sol::state> lua_;

    CommandQueue* command_queue_;
    Seqlock<InputState>* input_seqlock_;
    std::unique_ptr<ResponseQueue> response_queue_;

    // Request tracking
    struct PendingRequest {
        int request_id;
        sol::function callback;
        std::string operation;
    };
    std::unordered_map<int, PendingRequest> pending_requests_;
    int next_request_id_;

    // Parent tracking (for child threads)
    int parent_thread_id_;
    int parent_request_id_;

    // Event registration
    std::unordered_map<std::string, sol::function> event_handlers_;

    // Input event callbacks
    sol::function on_mouse_button_;  // (button, x, y, pressed)
    sol::function on_mouse_move_;    // (x, y, dx, dy)
    sol::function on_key_;           // (key, pressed)

    std::string error_message_;
};
