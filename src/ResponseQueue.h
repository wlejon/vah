#pragma once

#include <string>
#include <vector>
#include <atomic>
#include <memory>
#include "InputState.h"  // For PayloadMap

// Response sent from main thread to lua thread
// THREADING: PayloadMap is thread-safe and can cross thread boundaries
// The receiving Lua thread converts PayloadMap to a Lua table
struct Response {
    int request_id;
    PayloadMap data;         // Thread-safe data that can cross lua_State boundaries
    std::string error;       // Empty if success

    Response(int id, PayloadMap&& d, const std::string& e = "")
        : request_id(id), data(std::move(d)), error(e) {}
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
