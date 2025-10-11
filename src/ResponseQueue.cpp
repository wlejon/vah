#include "ResponseQueue.h"

ResponseQueue::ResponseQueue() {
    // Create dummy node
    Node* dummy = new Node(Response{0, sol::nil, ""});
    head_.store(dummy, std::memory_order_relaxed);
    tail_.store(dummy, std::memory_order_relaxed);
    cached_head_ = dummy;
}

ResponseQueue::~ResponseQueue() {
    // Clean up remaining nodes
    Node* node = head_.load(std::memory_order_relaxed);
    while (node) {
        Node* next = node->next.load(std::memory_order_relaxed);
        delete node;
        node = next;
    }
}

void ResponseQueue::Push(Response&& response) {
    // Producer (main thread) only
    Node* new_node = new Node(std::move(response));

    // Get current tail
    Node* prev_tail = tail_.load(std::memory_order_relaxed);

    // Link new node
    prev_tail->next.store(new_node, std::memory_order_release);

    // Update tail
    tail_.store(new_node, std::memory_order_relaxed);
}

std::vector<Response> ResponseQueue::PopAll() {
    // Consumer (lua thread) only
    std::vector<Response> responses;

    Node* current = cached_head_;
    Node* next = current->next.load(std::memory_order_acquire);

    while (next) {
        // Move data out of node
        responses.push_back(std::move(next->data));

        // Delete old head
        delete current;

        // Advance
        current = next;
        next = current->next.load(std::memory_order_acquire);
    }

    // Update cached head
    cached_head_ = current;
    head_.store(current, std::memory_order_relaxed);

    return responses;
}

bool ResponseQueue::Empty() const {
    // Check if there's anything after the current head
    Node* current = head_.load(std::memory_order_acquire);
    return current->next.load(std::memory_order_acquire) == nullptr;
}
