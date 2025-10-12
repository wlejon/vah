#pragma once

#include <string>
#include <vector>
#include <atomic>
#include <memory>
#include <optional>
#include <sol/sol.hpp>
#include "InputState.h"  // For PayloadMap

// Response sent from main thread to lua thread
struct Response {
    int request_id;
    sol::object data;        // Lua object (table, string, number, etc.) or nil
    std::string error;       // Empty if success
    std::optional<PayloadMap> payload_data;  // Alternative to sol::object for cross-thread data

    Response(int id, sol::object d, const std::string& e = "")
        : request_id(id), data(std::move(d)), error(e), payload_data(std::nullopt) {}

    Response(int id, sol::object d, const std::string& e, PayloadMap&& payload)
        : request_id(id), data(std::move(d)), error(e), payload_data(std::move(payload)) {}
};

// Lock-free single-producer (main thread) single-consumer (lua thread) queue
class ResponseQueue {
public:
    ResponseQueue();
    ~ResponseQueue();

    // Push response (called from main thread only)
    void Push(Response&& response);

    // Pop all pending responses (called from lua thread only)
    std::vector<Response> PopAll();

    // Check if queue is empty
    bool Empty() const;

private:
    struct Node {
        Response data;
        std::atomic<Node*> next;

        Node(Response&& resp) : data(std::move(resp)), next(nullptr) {}
    };

    std::atomic<Node*> head_;  // Consumer reads from head
    std::atomic<Node*> tail_;  // Producer writes to tail
    Node* cached_head_;        // Consumer's cached head pointer
};
