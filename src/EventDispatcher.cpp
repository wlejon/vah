#include "EventDispatcher.h"
#include "Logger.h"

// All EventDispatcher methods run on the main thread only - no locking needed
// The concurrent queues themselves provide lock-free communication to Lua threads

moodycamel::ConcurrentQueue<UIEvent>* EventDispatcher::RegisterThread(int thread_id) {
    auto it = thread_queues_.find(thread_id);
    if (it != thread_queues_.end()) {
        return it->second.get();
    }

    auto queue = std::make_unique<moodycamel::ConcurrentQueue<UIEvent>>();
    auto* queue_ptr = queue.get();
    thread_queues_[thread_id] = std::move(queue);

    LOG_INFO("EventDispatcher: Registered thread {}", thread_id);
    return queue_ptr;
}

void EventDispatcher::UnregisterThread(int thread_id) {
    thread_queues_.erase(thread_id);

    // Clean up any documents owned by this thread
    for (auto it = document_to_thread_.begin(); it != document_to_thread_.end();) {
        if (it->second == thread_id) {
            it = document_to_thread_.erase(it);
        } else {
            ++it;
        }
    }

    // Clean up any global events owned by this thread
    for (auto it = global_events_.begin(); it != global_events_.end();) {
        if (it->second == thread_id) {
            it = global_events_.erase(it);
        } else {
            ++it;
        }
    }

    LOG_INFO("EventDispatcher: Unregistered thread {}", thread_id);
}

void EventDispatcher::RegisterDocument(const std::string& document_id, int thread_id) {
    document_to_thread_[document_id] = thread_id;
}

void EventDispatcher::UnregisterDocument(const std::string& document_id) {
    document_to_thread_.erase(document_id);
}

void EventDispatcher::RegisterGlobalEvent(const std::string& event_name, int thread_id) {
    auto it = global_events_.find(event_name);
    if (it != global_events_.end()) {
        LOG_ERROR("EventDispatcher: Global event '{}' already registered by thread {}, cannot register for thread {}. Registration ignored.",
                  event_name, it->second, thread_id);
        // Don't overwrite existing registration - first registration wins
        return;
    }

    global_events_[event_name] = thread_id;
    LOG_INFO("EventDispatcher: Global event '{}' registered to thread {}", event_name, thread_id);
}

void EventDispatcher::UnregisterGlobalEvent(const std::string& event_name) {
    global_events_.erase(event_name);
}

void EventDispatcher::DispatchEvent(const std::string& document_id, const std::string& event_name, const PayloadMap& payload) {
    // Find which thread owns this document
    auto doc_it = document_to_thread_.find(document_id);
    if (doc_it == document_to_thread_.end()) {
        LOG_WARN("EventDispatcher: No thread owns document '{}', event '{}' dropped", document_id, event_name);
        return;
    }

    int thread_id = doc_it->second;

    // Find the thread's queue
    auto queue_it = thread_queues_.find(thread_id);
    if (queue_it == thread_queues_.end()) {
        LOG_WARN("EventDispatcher: Thread {} not found for event '{}', event dropped", thread_id, event_name);
        return;
    }

    // Enqueue the event (lock-free queue handles thread-safety)
    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    queue_it->second->enqueue(std::move(event));
}

void EventDispatcher::DispatchToThread(int thread_id, const std::string& event_name, const PayloadMap& payload) {
    // Find the thread's queue
    auto queue_it = thread_queues_.find(thread_id);
    if (queue_it == thread_queues_.end()) {
        LOG_WARN("EventDispatcher: Thread {} not found for event '{}', event dropped", thread_id, event_name);
        return;
    }

    // Enqueue the event (lock-free queue handles thread-safety)
    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    queue_it->second->enqueue(std::move(event));
}

void EventDispatcher::DispatchGlobalEvent(const std::string& event_name, const PayloadMap& payload) {
    // Find which thread handles this global event
    auto it = global_events_.find(event_name);
    if (it == global_events_.end()) {
        LOG_WARN("EventDispatcher: No thread registered for global event '{}'", event_name);
        return;
    }

    int thread_id = it->second;

    // Find the thread's queue
    auto queue_it = thread_queues_.find(thread_id);
    if (queue_it == thread_queues_.end()) {
        LOG_WARN("EventDispatcher: Thread {} not found for global event '{}', event dropped", thread_id, event_name);
        return;
    }

    // Enqueue the event (lock-free queue handles thread-safety)
    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    queue_it->second->enqueue(std::move(event));
}

void EventDispatcher::BroadcastEvent(const std::string& event_name, const PayloadMap& payload) {
    // Send event to all registered threads
    for (const auto& [thread_id, queue] : thread_queues_) {
        UIEvent event;
        event.name = event_name;
        event.payload = payload;
        queue->enqueue(event);
    }

    LOG_INFO("EventDispatcher: Broadcast event '{}' to {} thread(s)", event_name, thread_queues_.size());
}

void EventDispatcher::MarkSystemReady(const std::string& system_name) {
    ready_systems_.insert(system_name);

    // Broadcast to all threads that this system is ready
    PayloadMap payload;
    payload["system"] = system_name;
    BroadcastEvent("system_ready", payload);

    LOG_INFO("EventDispatcher: System '{}' marked ready", system_name);
}

bool EventDispatcher::IsSystemReady(const std::string& system_name) const {
    return ready_systems_.find(system_name) != ready_systems_.end();
}
