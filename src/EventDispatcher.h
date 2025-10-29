#pragma once

#include "Commands.h"
#include <moodycamel/concurrentqueue.h>
#include <unordered_map>
#include <unordered_set>
#include <string>

// EventDispatcher manages event routing between threads
// IMPORTANT: All methods are called from the main thread only (no locking needed)
// - Registration/dispatch happens on main thread via CommandProcessor
// - Event queues themselves are lock-free concurrent queues
class EventDispatcher {
public:
    EventDispatcher() = default;
    ~EventDispatcher() = default;

    // Register a thread and get its event queue (main thread only)
    moodycamel::ConcurrentQueue<UIEvent>* RegisterThread(int thread_id);

    // Unregister a thread (main thread only)
    void UnregisterThread(int thread_id);

    // Track which thread owns which document (main thread only)
    void RegisterDocument(const std::string& document_id, int thread_id);
    void UnregisterDocument(const std::string& document_id);

    // Register a global event handler (main thread only, asserts uniqueness)
    void RegisterGlobalEvent(const std::string& event_name, int thread_id);
    void UnregisterGlobalEvent(const std::string& event_name);

    // Dispatch a thread-local event (main thread only, goes to document's owner thread)
    void DispatchEvent(const std::string& document_id, const std::string& event_name, const PayloadMap& payload);

    // Dispatch an event directly to a specific thread (main thread only)
    void DispatchToThread(int thread_id, const std::string& event_name, const PayloadMap& payload);

    // Dispatch a global event (main thread only, goes to registered global handler)
    void DispatchGlobalEvent(const std::string& event_name, const PayloadMap& payload);

    // Broadcast an event to all threads (main thread only)
    void BroadcastEvent(const std::string& event_name, const PayloadMap& payload);

    // System readiness tracking (main thread only)
    void MarkSystemReady(const std::string& system_name);
    bool IsSystemReady(const std::string& system_name) const;
    const std::unordered_set<std::string>& GetReadySystems() const { return ready_systems_; }

private:
    // Per-thread event queues (lock-free queues, modified only on main thread)
    std::unordered_map<int, std::unique_ptr<moodycamel::ConcurrentQueue<UIEvent>>> thread_queues_;

    // Document ID -> Thread ID mapping (modified only on main thread)
    std::unordered_map<std::string, int> document_to_thread_;

    // Global event name -> Thread ID mapping (modified only on main thread)
    std::unordered_map<std::string, int> global_events_;

    // System readiness tracking (modified only on main thread)
    std::unordered_set<std::string> ready_systems_;
};
