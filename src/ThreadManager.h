#pragma once

#include <memory>
#include <vector>
#include <string>
#include "LuaThread.h"

class CommandQueue;
class UIEventQueue;
class DataStore;

class ThreadManager {
public:
    ThreadManager(CommandQueue* command_queue, UIEventQueue* ui_event_queue, DataStore* data_store);
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
    class ResponseQueue* GetThreadResponseQueue(int thread_id);

private:
    LuaThread* GetThread(int thread_id) const;

    CommandQueue* command_queue_;
    UIEventQueue* ui_event_queue_;
    DataStore* data_store_;

    std::vector<std::unique_ptr<LuaThread>> threads_;
};
