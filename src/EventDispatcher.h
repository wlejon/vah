#pragma once

#include "Commands.h"
#include <moodycamel/concurrentqueue.h>
#include <unordered_map>
#include <mutex>
#include <string>

class EventDispatcher {
public:
    EventDispatcher() = default;
    ~EventDispatcher() = default;

    // Register a thread and get its event queue
    moodycamel::ConcurrentQueue<UIEvent>* RegisterThread(int thread_id);

    // Unregister a thread
    void UnregisterThread(int thread_id);

    // Track which thread owns which document
    void RegisterDocument(const std::string& document_id, int thread_id);
    void UnregisterDocument(const std::string& document_id);

    // Register a global event handler (asserts uniqueness)
    void RegisterGlobalEvent(const std::string& event_name, int thread_id);
    void UnregisterGlobalEvent(const std::string& event_name);

    // Dispatch a thread-local event (goes to document's owner thread)
    void DispatchEvent(const std::string& document_id, const std::string& event_name, const PayloadMap& payload);

    // Dispatch a global event (goes to registered global handler)
    void DispatchGlobalEvent(const std::string& event_name, const PayloadMap& payload);

private:
    std::mutex mutex_;

    // Per-thread event queues
    std::unordered_map<int, std::unique_ptr<moodycamel::ConcurrentQueue<UIEvent>>> thread_queues_;

    // Document ID -> Thread ID mapping
    std::unordered_map<std::string, int> document_to_thread_;

    // Global event name -> Thread ID mapping
    std::unordered_map<std::string, int> global_events_;
};
