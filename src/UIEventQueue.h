#pragma once

#include "InputState.h"
#include <atomic>
#include <vector>

// Lock-free queue
class UIEventQueue {
public:
    UIEventQueue();
    ~UIEventQueue();

    void Push(UIEvent&& event);
    std::vector<UIEvent> PopAll();
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
