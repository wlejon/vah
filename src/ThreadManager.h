#pragma once

#include <memory>
#include <vector>
#include <string>
#include <moodycamel/concurrentqueue.h>
#include "LuaThread.h"
#include "Commands.h"
#include "InputState.h"

class DataStore;
class EventDispatcher;

class CommandProcessor;

class ThreadManager {
public:
    ThreadManager(moodycamel::ConcurrentQueue<Command>* command_queue,
                  EventDispatcher* event_dispatcher,
                  DataStore* data_store);

    void SetEventDispatcher(EventDispatcher* event_dispatcher) { event_dispatcher_ = event_dispatcher; }
    void SetCommandProcessor(CommandProcessor* command_processor) { command_processor_ = command_processor; }
    ~ThreadManager();

    // Thread lifecycle
    int SpawnThread(const std::string& script_path);
    int SpawnThread(const std::string& script_path, int parent_thread_id, int parent_request_id);
    void StopThread(int thread_id);
    void StopAll();

    // Thread control
    void PauseThread(int thread_id);
    void ResumeThread(int thread_id);
    void PauseAll();
    void ResumeAll();

    // Save/Load
    void SaveThread(int thread_id, const std::string& save_path);
    void LoadThread(int thread_id, const std::string& load_path);

    // Queries
    bool HasThread(int thread_id) const;
    LuaThread::State GetThreadState(int thread_id) const;
    std::string GetThreadError(int thread_id) const;
    size_t GetThreadCount() const;

    // Get all thread IDs
    std::vector<int> GetAllThreadIds() const;

    // Get thread's response queue (for sending responses)
    moodycamel::ConcurrentQueue<Response>* GetThreadResponseQueue(int thread_id);

    // Query thread information (for MCP API)
    struct ThreadInfo {
        int thread_id;
        std::string script_path;
        std::string status;  // "running", "paused", "stopped", "error"
        double uptime;       // seconds since thread started
    };

    ThreadInfo GetThreadInfo(int thread_id) const;
    std::vector<ThreadInfo> GetAllThreadInfo() const;

    // Get thread pointer (needed for CommandProcessor to signal semaphore)
    LuaThread* GetThread(int thread_id) const;

private:

    moodycamel::ConcurrentQueue<Command>* command_queue_;
    EventDispatcher* event_dispatcher_;
    DataStore* data_store_;
    CommandProcessor* command_processor_ = nullptr;

    std::vector<std::unique_ptr<LuaThread>> threads_;
};
