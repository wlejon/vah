#pragma once

#include <variant>
#include <string>
#include <vector>
#include <atomic>
#include <functional>
#include <unordered_map>
#include <sol/sol.hpp>
#include "InputState.h"
#include "DataStore.h"

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

    struct LoadUIDocument {
        std::string document_path;
        bool show = true;
        std::string document_id;  // Optional ID to reference this document later
    };

    struct ShowUIDocument {
        std::string document_id;
    };

    struct HideUIDocument {
        std::string document_id;
    };

    struct ReloadUIDocument {
        std::string document_id;
    };

    struct SetElementText {
        std::string element_id;
        std::string text;
    };

    struct SetElementAttribute {
        std::string element_id;
        std::string attribute_name;
        std::string value;
    };

    struct SetElementStyle {
        std::string element_id;
        std::string property;
        std::string value;
    };

    struct AddElementClass {
        std::string element_id;
        std::string class_name;
    };

    struct RemoveElementClass {
        std::string element_id;
        std::string class_name;
    };

    struct UpdateDataModel {
        std::string model_name;
        DynamicTable data;
    };

    struct GetInputEdits {
        std::string model;
        std::string record_id;
        int requesting_thread_id;
        int request_id;
    };

    struct ClearInputEdits {
        std::string model;
        std::string record_id;
    };

    struct FileChanged {
        std::string path;
        std::string event_type;  // "created", "modified", "deleted"
    };

    struct AddFileWatch {
        std::string path;
        bool recursive;
    };

    struct RemoveFileWatch {
        std::string path;
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
    Commands::LoadUIDocument,
    Commands::ShowUIDocument,
    Commands::HideUIDocument,
    Commands::ReloadUIDocument,
    Commands::SetElementText,
    Commands::SetElementAttribute,
    Commands::SetElementStyle,
    Commands::AddElementClass,
    Commands::RemoveElementClass,
    Commands::UpdateDataModel,
    Commands::GetInputEdits,
    Commands::ClearInputEdits,
    Commands::FileChanged,
    Commands::AddFileWatch,
    Commands::RemoveFileWatch
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
