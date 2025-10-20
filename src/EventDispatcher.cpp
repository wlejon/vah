#include "EventDispatcher.h"
#include "Logger.h"
#include <cassert>

moodycamel::ConcurrentQueue<UIEvent>* EventDispatcher::RegisterThread(int thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);

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
    std::lock_guard<std::mutex> lock(mutex_);

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
    std::lock_guard<std::mutex> lock(mutex_);
    document_to_thread_[document_id] = thread_id;
    LOG_DEBUG("EventDispatcher: Document '{}' owned by thread {}", document_id, thread_id);
}

void EventDispatcher::UnregisterDocument(const std::string& document_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    document_to_thread_.erase(document_id);
}

void EventDispatcher::RegisterGlobalEvent(const std::string& event_name, int thread_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = global_events_.find(event_name);
    if (it != global_events_.end()) {
        LOG_ERROR("EventDispatcher: Global event '{}' already registered by thread {}, cannot register for thread {}",
                  event_name, it->second, thread_id);
        assert(false && "Global event already registered by another thread");
        return;
    }

    global_events_[event_name] = thread_id;
    LOG_INFO("EventDispatcher: Global event '{}' registered to thread {}", event_name, thread_id);
}

void EventDispatcher::UnregisterGlobalEvent(const std::string& event_name) {
    std::lock_guard<std::mutex> lock(mutex_);
    global_events_.erase(event_name);
}

void EventDispatcher::DispatchEvent(const std::string& document_id, const std::string& event_name, const PayloadMap& payload) {
    std::lock_guard<std::mutex> lock(mutex_);

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

    // Enqueue the event
    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    queue_it->second->enqueue(std::move(event));

    LOG_DEBUG("EventDispatcher: Dispatched event '{}' from document '{}' to thread {}", event_name, document_id, thread_id);
}

void EventDispatcher::DispatchGlobalEvent(const std::string& event_name, const PayloadMap& payload) {
    std::lock_guard<std::mutex> lock(mutex_);

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

    // Enqueue the event
    UIEvent event;
    event.name = event_name;
    event.payload = payload;
    queue_it->second->enqueue(std::move(event));

    LOG_DEBUG("EventDispatcher: Dispatched global event '{}' to thread {}", event_name, thread_id);
}
