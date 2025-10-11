#pragma once

#include <memory>
#include <vector>
#include <string>
#include <atomic>
#include "LuaThread.h"

class CommandQueue;
template<typename T> class Seqlock;
struct InputState;

class ThreadManager {
public:
    ThreadManager(CommandQueue* command_queue, Seqlock<InputState>* input_seqlock);
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
    void EnsureCapacity(int thread_id);

    std::atomic<int> next_thread_id_;
    CommandQueue* command_queue_;
    Seqlock<InputState>* input_seqlock_;

    // Lock-free thread storage: array of atomic pointers indexed by thread_id
    // Note: We use raw pointers with atomic operations for lock-free access
    std::atomic<std::atomic<LuaThread*>*> threads_;
    std::atomic<size_t> capacity_;
};
