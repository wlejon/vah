#include "ThreadManager.h"
#include "CommandQueue.h"
#include "ResponseQueue.h"
#include "Seqlock.h"
#include "InputState.h"
#include "Logger.h"
#include <fstream>

ThreadManager::ThreadManager(CommandQueue* command_queue, Seqlock<InputState>* input_seqlock)
    : next_thread_id_(1)
    , command_queue_(command_queue)
    , input_seqlock_(input_seqlock)
{
}

ThreadManager::~ThreadManager() {
    StopAll();
}

int ThreadManager::SpawnThread(const std::string& script_path) {
    std::lock_guard<std::mutex> lock(mutex_);

    int thread_id = next_thread_id_++;
    auto thread = std::make_unique<LuaThread>(thread_id, script_path, command_queue_, input_seqlock_);
    thread->Start();

    threads_[thread_id] = std::move(thread);

    LOG_INFO("ThreadManager: Spawned thread {} for script '{}'", thread_id, script_path);
    return thread_id;
}

int ThreadManager::SpawnThread(const std::string& script_path, int parent_thread_id, int parent_request_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    int thread_id = next_thread_id_++;
    auto thread = std::make_unique<LuaThread>(thread_id, script_path, command_queue_, input_seqlock_);

    // Set parent information
    if (parent_thread_id != 0) {
        thread->SetParent(parent_thread_id, parent_request_id);
    }

    thread->Start();

    threads_[thread_id] = std::move(thread);

    LOG_INFO("ThreadManager: Spawned thread {} for script '{}' (parent: {})", thread_id, script_path, parent_thread_id);
    return thread_id;
}

void ThreadManager::StopThread(int thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        it->second->Stop();
        it->second->Join();
        threads_.erase(it);
        LOG_INFO("ThreadManager: Stopped thread {}", thread_id);
    }
}

void ThreadManager::StopAll() {
    std::lock_guard<std::mutex> lock(mutex_);

    LOG_INFO("ThreadManager: Stopping all {} threads", threads_.size());

    for (auto& [id, thread] : threads_) {
        thread->Stop();
    }

    for (auto& [id, thread] : threads_) {
        thread->Join();
    }

    threads_.clear();
}

void ThreadManager::PauseThread(int thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        it->second->Pause();
        LOG_INFO("ThreadManager: Paused thread {}", thread_id);
    }
}

void ThreadManager::ResumeThread(int thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        it->second->Resume();
        LOG_INFO("ThreadManager: Resumed thread {}", thread_id);
    }
}

void ThreadManager::PauseAll() {
    std::lock_guard<std::mutex> lock(mutex_);

    LOG_INFO("ThreadManager: Pausing all threads");
    for (auto& [id, thread] : threads_) {
        thread->Pause();
    }
}

void ThreadManager::ResumeAll() {
    std::lock_guard<std::mutex> lock(mutex_);

    LOG_INFO("ThreadManager: Resuming all threads");
    for (auto& [id, thread] : threads_) {
        thread->Resume();
    }
}

void ThreadManager::SaveThread(int thread_id, const std::string& save_path) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        // Pause thread before saving
        bool was_running = it->second->IsRunning();
        if (was_running) {
            it->second->Pause();
        }

        // Call lua save hook
        sol::object save_data = it->second->CallSaveHook();

        // TODO: Serialize save_data to file at save_path
        // For now, just log
        LOG_INFO("ThreadManager: Saved thread {} to '{}'", thread_id, save_path);

        // Resume if it was running
        if (was_running) {
            it->second->Resume();
        }
    }
}

void ThreadManager::LoadThread(int thread_id, const std::string& load_path) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        // TODO: Deserialize save_data from file at load_path
        // For now, just log
        LOG_INFO("ThreadManager: Loaded thread {} from '{}'", thread_id, load_path);

        // Call lua load hook with deserialized data
        // it->second->CallLoadHook(save_data);
    }
}

bool ThreadManager::HasThread(int thread_id) const {
    std::lock_guard<std::mutex> lock(mutex_);
    return threads_.find(thread_id) != threads_.end();
}

LuaThread::State ThreadManager::GetThreadState(int thread_id) const {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        return it->second->GetState();
    }
    return LuaThread::State::Stopped;
}

std::string ThreadManager::GetThreadError(int thread_id) const {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        return it->second->GetError();
    }
    return "";
}

size_t ThreadManager::GetThreadCount() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return threads_.size();
}

std::vector<int> ThreadManager::GetAllThreadIds() const {
    std::lock_guard<std::mutex> lock(mutex_);

    std::vector<int> ids;
    ids.reserve(threads_.size());
    for (const auto& [id, _] : threads_) {
        ids.push_back(id);
    }
    return ids;
}

ResponseQueue* ThreadManager::GetThreadResponseQueue(int thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = threads_.find(thread_id);
    if (it != threads_.end()) {
        return it->second->GetResponseQueue();
    }
    return nullptr;
}
