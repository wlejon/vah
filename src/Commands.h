#pragma once

#include <variant>
#include <string>
#include <functional>
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
        int thread_id;  // Which thread loaded this document
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

    struct SetTextEditorContent {
        std::string element_id;
        std::string content;
    };

    struct SetTextEditorTokens {
        std::string element_id;
        DynamicTable tokens;  // Array of token objects
    };

    struct SetTextEditorEditable {
        std::string element_id;
        bool editable;
    };

    struct SetTextEditorModified {
        std::string element_id;
        bool modified;
    };

    struct SetTextEditorConfig {
        std::string element_id;
        std::string config_key;
        DynamicValue value;
    };

    struct UpdateDataModel {
        std::string model_name;
        DynamicTable data;
    };

    struct TriggerTextEditorModified {
        std::string element_id;
        bool modified;
        std::string content;
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

    struct RegisterGlobalEvent {
        std::string event_name;
        int thread_id;
    };

    struct UnregisterGlobalEvent {
        std::string event_name;
    };

    struct TriggerGlobalEvent {
        std::string event_name;
        PayloadMap payload;
    };

    struct NotificationActionData {
        std::string id;
        std::string label;
    };

    struct AddNotification {
        int type;
        std::string title;
        std::string message;
        std::string thread_name;
        bool dismissible;
        bool expandable;
        std::string expanded_content;
        std::vector<NotificationActionData> actions;
        PayloadMap metadata;
        double ttl_seconds;
        int thread_id = -1;
    };

    struct ClearNotifications {
    };

    struct DismissNotification {
        std::string notification_id;
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
    Commands::SetTextEditorContent,
    Commands::SetTextEditorTokens,
    Commands::SetTextEditorEditable,
    Commands::SetTextEditorModified,
    Commands::SetTextEditorConfig,
    Commands::UpdateDataModel,
    Commands::TriggerTextEditorModified,
    Commands::FileChanged,
    Commands::AddFileWatch,
    Commands::RemoveFileWatch,
    Commands::RegisterGlobalEvent,
    Commands::UnregisterGlobalEvent,
    Commands::TriggerGlobalEvent,
    Commands::AddNotification,
    Commands::ClearNotifications,
    Commands::DismissNotification
>;

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
