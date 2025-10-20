#pragma once

#include <memory>
#include <vector>
#include <string>
#include <moodycamel/concurrentqueue.h>
#include "LuaThread.h"
#include "Commands.h"
#include "InputState.h"

class DataStore;
class NotificationFeed;
class EventDispatcher;

class ThreadManager {
public:
    ThreadManager(moodycamel::ConcurrentQueue<Command>* command_queue,
                  EventDispatcher* event_dispatcher,
                  DataStore* data_store,
                  NotificationFeed* notification_feed);
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

private:
    LuaThread* GetThread(int thread_id) const;

    moodycamel::ConcurrentQueue<Command>* command_queue_;
    EventDispatcher* event_dispatcher_;
    DataStore* data_store_;
    NotificationFeed* notification_feed_;

    std::vector<std::unique_ptr<LuaThread>> threads_;
};
