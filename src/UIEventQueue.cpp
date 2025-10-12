#include "UIEventQueue.h"

UIEventQueue::UIEventQueue() {
    // Create dummy node
    Node* dummy = new Node(UIEvent{});
    head_.store(dummy, std::memory_order_relaxed);
    tail_.store(dummy, std::memory_order_relaxed);
    cached_head_ = dummy;
}

UIEventQueue::~UIEventQueue() {
    // Clean up remaining nodes
    Node* node = head_.load(std::memory_order_relaxed);
    while (node) {
        Node* next = node->next.load(std::memory_order_relaxed);
        delete node;
        node = next;
    }
}

void UIEventQueue::Push(UIEvent&& event) {
    // Multi-producer (RmlUi thread)
    Node* new_node = new Node(std::move(event));

    // Use CAS loop to append to tail (lock-free)
    Node* prev_tail = tail_.load(std::memory_order_acquire);
    while (true) {
        Node* next = prev_tail->next.load(std::memory_order_acquire);

        if (next == nullptr) {
            // Try to link our node
            if (prev_tail->next.compare_exchange_weak(next, new_node,
                                                       std::memory_order_release,
                                                       std::memory_order_acquire)) {
                // Successfully linked, try to update tail
                tail_.compare_exchange_strong(prev_tail, new_node,
                                             std::memory_order_release,
                                             std::memory_order_relaxed);
                return;
            }
        } else {
            // Someone else added a node, help update tail
            tail_.compare_exchange_strong(prev_tail, next,
                                         std::memory_order_release,
                                         std::memory_order_relaxed);
        }

        // Retry with updated tail
        prev_tail = tail_.load(std::memory_order_acquire);
    }
}

std::vector<UIEvent> UIEventQueue::PopAll() {
    return PopAllInternal();
}

std::vector<UIEvent> UIEventQueue::PopAllInternal() {
    // Consumer (worker threads) only
    std::vector<UIEvent> events;

    Node* current = cached_head_;
    Node* next = current->next.load(std::memory_order_acquire);

    while (next) {
        // Move data out of node
        events.push_back(std::move(next->data));

        // Delete old head
        delete current;

        // Advance
        current = next;
        next = current->next.load(std::memory_order_acquire);
    }

    // Update cached head
    cached_head_ = current;
    head_.store(current, std::memory_order_relaxed);

    return events;
}

bool UIEventQueue::Empty() const {
    // Check if there's anything after the current head
    Node* current = head_.load(std::memory_order_acquire);
    return current->next.load(std::memory_order_acquire) == nullptr;
}
