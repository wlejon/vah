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
    , capacity_(1024)
{
    // Allocate initial array of atomic pointers
    size_t initial_capacity = capacity_.load(std::memory_order_relaxed);
    std::atomic<LuaThread*>* array = new std::atomic<LuaThread*>[initial_capacity];

    // Initialize all pointers to nullptr
    for (size_t i = 0; i < initial_capacity; ++i) {
        array[i].store(nullptr, std::memory_order_relaxed);
    }

    threads_.store(array, std::memory_order_release);
}

ThreadManager::~ThreadManager() {
    StopAll();

    // Clean up the array
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    delete[] array;
}

LuaThread* ThreadManager::GetThread(int thread_id) const {
    if (thread_id < 0 || static_cast<size_t>(thread_id) >= capacity_.load(std::memory_order_acquire)) {
        return nullptr;
    }
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    return array[thread_id].load(std::memory_order_acquire);
}

void ThreadManager::EnsureCapacity(int thread_id) {
    size_t required_capacity = static_cast<size_t>(thread_id) + 1;
    size_t current_capacity = capacity_.load(std::memory_order_acquire);

    while (required_capacity > current_capacity) {
        // Calculate new capacity (double the size)
        size_t new_capacity = current_capacity * 2;
        if (new_capacity < required_capacity) {
            new_capacity = required_capacity;
        }

        // Allocate new array
        std::atomic<LuaThread*>* new_array = new std::atomic<LuaThread*>[new_capacity];

        // Get current array
        std::atomic<LuaThread*>* old_array = threads_.load(std::memory_order_acquire);

        // Copy existing pointers from old array
        for (size_t i = 0; i < current_capacity; ++i) {
            new_array[i].store(old_array[i].load(std::memory_order_acquire), std::memory_order_relaxed);
        }

        // Initialize new slots to nullptr
        for (size_t i = current_capacity; i < new_capacity; ++i) {
            new_array[i].store(nullptr, std::memory_order_relaxed);
        }

        // Try to atomically swap the array pointer
        if (threads_.compare_exchange_strong(old_array, new_array,
                                            std::memory_order_release,
                                            std::memory_order_acquire)) {
            // Update capacity
            capacity_.store(new_capacity, std::memory_order_release);

            // We successfully swapped, old_array can be deleted
            // Note: In a production system, you'd want to use hazard pointers or
            // epoch-based reclamation to safely delete the old array
            delete[] old_array;
            break;
        } else {
            // Another thread beat us to it, delete our new array and retry
            delete[] new_array;
            current_capacity = capacity_.load(std::memory_order_acquire);
        }
    }
}

int ThreadManager::SpawnThread(const std::string& script_path) {
    // Atomically get next thread ID
    int thread_id = next_thread_id_.fetch_add(1, std::memory_order_relaxed);

    // Ensure we have capacity
    EnsureCapacity(thread_id);

    // Create and start the thread
    auto thread = new LuaThread(thread_id, script_path, command_queue_, input_seqlock_);
    thread->Start();

    // Store the thread pointer atomically
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    array[thread_id].store(thread, std::memory_order_release);

    LOG_INFO("ThreadManager: Spawned thread {} for script '{}'", thread_id, script_path);
    return thread_id;
}

int ThreadManager::SpawnThread(const std::string& script_path, int parent_thread_id, int parent_request_id) {
    // Atomically get next thread ID
    int thread_id = next_thread_id_.fetch_add(1, std::memory_order_relaxed);

    // Ensure we have capacity
    EnsureCapacity(thread_id);

    // Create the thread
    auto thread = new LuaThread(thread_id, script_path, command_queue_, input_seqlock_);

    // Set parent information
    if (parent_thread_id != 0) {
        thread->SetParent(parent_thread_id, parent_request_id);
    }

    thread->Start();

    // Store the thread pointer atomically
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    array[thread_id].store(thread, std::memory_order_release);

    LOG_INFO("ThreadManager: Spawned thread {} for script '{}' (parent: {})", thread_id, script_path, parent_thread_id);
    return thread_id;
}

void ThreadManager::StopThread(int thread_id) {
    // Atomically swap out the thread pointer
    LuaThread* thread = nullptr;
    if (thread_id >= 0 && static_cast<size_t>(thread_id) < capacity_.load(std::memory_order_acquire)) {
        std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
        thread = array[thread_id].exchange(nullptr, std::memory_order_acq_rel);
    }

    if (thread != nullptr) {
        thread->Stop();
        thread->Join();
        delete thread;
        LOG_INFO("ThreadManager: Stopped thread {}", thread_id);
    }
}

void ThreadManager::StopAll() {
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    size_t cap = capacity_.load(std::memory_order_acquire);
    size_t thread_count = 0;

    // First pass: stop all threads
    for (size_t i = 0; i < cap; ++i) {
        LuaThread* thread = array[i].load(std::memory_order_acquire);
        if (thread != nullptr) {
            thread->Stop();
            ++thread_count;
        }
    }

    LOG_INFO("ThreadManager: Stopping all {} threads", thread_count);

    // Second pass: join and delete all threads
    for (size_t i = 0; i < cap; ++i) {
        LuaThread* thread = array[i].exchange(nullptr, std::memory_order_acq_rel);
        if (thread != nullptr) {
            thread->Join();
            delete thread;
        }
    }
}

void ThreadManager::PauseThread(int thread_id) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        thread->Pause();
        LOG_INFO("ThreadManager: Paused thread {}", thread_id);
    }
}

void ThreadManager::ResumeThread(int thread_id) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        thread->Resume();
        LOG_INFO("ThreadManager: Resumed thread {}", thread_id);
    }
}

void ThreadManager::PauseAll() {
    LOG_INFO("ThreadManager: Pausing all threads");

    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    size_t cap = capacity_.load(std::memory_order_acquire);

    for (size_t i = 0; i < cap; ++i) {
        LuaThread* thread = array[i].load(std::memory_order_acquire);
        if (thread != nullptr) {
            thread->Pause();
        }
    }
}

void ThreadManager::ResumeAll() {
    LOG_INFO("ThreadManager: Resuming all threads");

    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    size_t cap = capacity_.load(std::memory_order_acquire);

    for (size_t i = 0; i < cap; ++i) {
        LuaThread* thread = array[i].load(std::memory_order_acquire);
        if (thread != nullptr) {
            thread->Resume();
        }
    }
}

void ThreadManager::SaveThread(int thread_id, const std::string& save_path) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        // Pause thread before saving
        bool was_running = thread->IsRunning();
        if (was_running) {
            thread->Pause();
        }

        // Call lua save hook
        sol::object save_data = thread->CallSaveHook();

        // TODO: Serialize save_data to file at save_path
        // For now, just log
        LOG_INFO("ThreadManager: Saved thread {} to '{}'", thread_id, save_path);

        // Resume if it was running
        if (was_running) {
            thread->Resume();
        }
    }
}

void ThreadManager::LoadThread(int thread_id, const std::string& load_path) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        // TODO: Deserialize save_data from file at load_path
        // For now, just log
        LOG_INFO("ThreadManager: Loaded thread {} from '{}'", thread_id, load_path);

        // Call lua load hook with deserialized data
        // thread->CallLoadHook(save_data);
    }
}

bool ThreadManager::HasThread(int thread_id) const {
    return GetThread(thread_id) != nullptr;
}

LuaThread::State ThreadManager::GetThreadState(int thread_id) const {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        return thread->GetState();
    }
    return LuaThread::State::Stopped;
}

std::string ThreadManager::GetThreadError(int thread_id) const {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        return thread->GetError();
    }
    return "";
}

size_t ThreadManager::GetThreadCount() const {
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    size_t cap = capacity_.load(std::memory_order_acquire);
    size_t count = 0;

    for (size_t i = 0; i < cap; ++i) {
        if (array[i].load(std::memory_order_acquire) != nullptr) {
            ++count;
        }
    }
    return count;
}

std::vector<int> ThreadManager::GetAllThreadIds() const {
    std::atomic<LuaThread*>* array = threads_.load(std::memory_order_acquire);
    size_t cap = capacity_.load(std::memory_order_acquire);
    std::vector<int> ids;

    for (size_t i = 0; i < cap; ++i) {
        if (array[i].load(std::memory_order_acquire) != nullptr) {
            ids.push_back(static_cast<int>(i));
        }
    }
    return ids;
}

ResponseQueue* ThreadManager::GetThreadResponseQueue(int thread_id) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        return thread->GetResponseQueue();
    }
    return nullptr;
}
