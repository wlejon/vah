#pragma once

#include "InputState.h"
#include <atomic>
#include <vector>

// Lock-free multi-producer (RmlUi thread) single-consumer (worker threads) queue
class UIEventQueue {
public:
    UIEventQueue();
    ~UIEventQueue();

    // Thread-safe push (called from RmlUi thread via RmlUiBridge)
    void Push(UIEvent&& event);

    // Drain all pending events (called from worker threads only)
    std::vector<UIEvent> PopAll();

    // Check if queue is empty
    bool Empty() const;

private:
    struct Node {
        UIEvent data;
        std::atomic<Node*> next;

        Node(UIEvent&& event) : data(std::move(event)), next(nullptr) {}
    };

    std::vector<UIEvent> PopAllInternal();

    std::atomic<Node*> head_;  // Consumer reads from head
    std::atomic<Node*> tail_;  // Producers write to tail
    Node* cached_head_;        // Consumer's cached head pointer
};
