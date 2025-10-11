#pragma once

#include <variant>
#include <string>
#include <vector>
#include <atomic>
#include <functional>
#include <unordered_map>
#include <sol/sol.hpp>
#include "InputState.h"

// Command types that lua threads can send to the main thread
namespace Commands {
    struct SpawnThread {
        std::string script_path;
        PayloadMap config;
        int parent_thread_id = 0;   // 0 = no parent
        int parent_request_id = 0;  // Request ID in parent to respond to
        int requesting_thread_id = 0;  // Thread that issued this command
    };

    struct TriggerUI {
        std::string event_name;
        PayloadMap payload;
    };

    struct CallMainThread {
        std::function<void()> callback;
    };

    struct StopThread {
        int thread_id;
    };

    struct SaveThread {
        int thread_id;
        std::string save_path;
    };

    struct Print {
        int thread_id;
        std::string message;
    };

    struct SendResponse {
        int target_thread_id;
        int request_id;
        sol::object data;
        std::string error;
    };

    struct LoadUIDocument {
        std::string document_path;
        bool show = true;
    };

    struct SetElementText {
        std::string element_id;
        std::string text;
    };
}

// Variant holding all possible command types
using Command = std::variant<
    Commands::SpawnThread,
    Commands::TriggerUI,
    Commands::CallMainThread,
    Commands::StopThread,
    Commands::SaveThread,
    Commands::Print,
    Commands::SendResponse,
    Commands::LoadUIDocument,
    Commands::SetElementText
>;

// Lock-free multi-producer (lua threads) single-consumer (main thread) queue
class CommandQueue {
public:
    CommandQueue();
    ~CommandQueue();

    // Thread-safe push (called from any lua thread)
    void Push(Command&& cmd);

    // Pop and process all pending commands (called from main thread only)
    template<typename Visitor>
    void ProcessAll(Visitor&& visitor) {
        auto commands = PopAll();
        for (auto& cmd : commands) {
            std::visit(std::forward<Visitor>(visitor), cmd);
        }
    }

    // Check if queue is empty
    bool Empty() const;

private:
    struct Node {
        Command data;
        std::atomic<Node*> next;

        Node(Command&& cmd) : data(std::move(cmd)), next(nullptr) {}
    };

    std::vector<Command> PopAll();

    std::atomic<Node*> head_;  // Consumer reads from head
    std::atomic<Node*> tail_;  // Producers write to tail
    Node* cached_head_;        // Consumer's cached head pointer
};
