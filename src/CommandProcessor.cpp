#include "CommandProcessor.h"
#include "ThreadManager.h"
#include "DocumentManager.h"
#include "DataModelManager.h"
#include "EventDispatcher.h"
#include "Logger.h"

CommandProcessor::CommandProcessor(
    ThreadManager* thread_manager,
    DocumentManager* document_manager,
    DataModelManager* data_model_manager,
    EventDispatcher* event_dispatcher,
    std::function<void()> on_close_application
)
    : thread_manager_(thread_manager)
    , document_manager_(document_manager)
    , data_model_manager_(data_model_manager)
    , event_dispatcher_(event_dispatcher)
    , on_close_application_(on_close_application)
{
}

void CommandProcessor::ProcessCommand(Command&& cmd) {
    std::visit([this](auto&& command) {
        using T = std::decay_t<decltype(command)>;

        if constexpr (std::is_same_v<T, Commands::SpawnThread>) {
            LOG_INFO("Processing SpawnThread command: {} (parent: {})", command.script_path, command.parent_thread_id);
            int new_thread_id;
            if (command.parent_thread_id != 0) {
                new_thread_id = thread_manager_->SpawnThread(command.script_path, command.parent_thread_id, command.parent_request_id);
            } else {
                new_thread_id = thread_manager_->SpawnThread(command.script_path);
            }

            // Send thread_spawned event back to the requesting thread with the new thread ID
            if (command.requesting_thread_id >= 0) {
                PayloadMap payload;
                payload["thread_id"] = new_thread_id;
                payload["script_path"] = command.script_path;
                event_dispatcher_->DispatchToThread(command.requesting_thread_id, "thread_spawned", payload);
            }
        }
        else if constexpr (std::is_same_v<T, Commands::StopThread>) {
            LOG_INFO("Processing StopThread command: {}", command.thread_id);
            thread_manager_->StopThread(command.thread_id);
        }
        else if constexpr (std::is_same_v<T, Commands::TriggerUI>) {
            LOG_INFO("Processing TriggerUI command: {}", command.event_name);
            // UI events are already handled by RmlUiBridge
        }
        else if constexpr (std::is_same_v<T, Commands::CallMainThread>) {
            command.callback();
        }
        else if constexpr (std::is_same_v<T, Commands::SaveThread>) {
            LOG_INFO("Processing SaveThread command: {} -> {}", command.thread_id, command.save_path);
            thread_manager_->SaveThread(command.thread_id, command.save_path);
        }
        else if constexpr (std::is_same_v<T, Commands::Print>) {
            LOG_INFO("[Lua Thread {}] {}", command.thread_id, command.message);
        }
        else if constexpr (std::is_same_v<T, Commands::LoadUIDocument>) {
            LOG_INFO("Processing LoadUIDocument command: {}", command.document_path);
            document_manager_->LoadDocument(command.document_path, command.show, command.document_id);

            // Register document ownership with event dispatcher
            if (!command.document_id.empty()) {
                event_dispatcher_->RegisterDocument(command.document_id, command.thread_id);
            }
        }
        else if constexpr (std::is_same_v<T, Commands::ShowUIDocument>) {
            document_manager_->ShowDocument(command.document_id);
        }
        else if constexpr (std::is_same_v<T, Commands::HideUIDocument>) {
            document_manager_->HideDocument(command.document_id);
        }
        else if constexpr (std::is_same_v<T, Commands::SetElementText>) {
            document_manager_->SetElementText(command.element_id, command.text);
        }
        else if constexpr (std::is_same_v<T, Commands::SetElementAttribute>) {
            document_manager_->SetElementAttribute(command.element_id, command.attribute_name, command.value);
        }
        else if constexpr (std::is_same_v<T, Commands::SetElementStyle>) {
            document_manager_->SetElementStyle(command.element_id, command.property, command.value);
        }
        else if constexpr (std::is_same_v<T, Commands::AddElementClass>) {
            document_manager_->AddElementClass(command.element_id, command.class_name);
        }
        else if constexpr (std::is_same_v<T, Commands::RemoveElementClass>) {
            document_manager_->RemoveElementClass(command.element_id, command.class_name);
        }
        else if constexpr (std::is_same_v<T, Commands::SetTextEditorContent>) {
            document_manager_->SetTextEditorContent(command.element_id, command.content);
        }
        else if constexpr (std::is_same_v<T, Commands::SetTextEditorTokens>) {
            document_manager_->SetTextEditorTokens(command.element_id, command.tokens);
        }
        else if constexpr (std::is_same_v<T, Commands::SetTextEditorEditable>) {
            document_manager_->SetTextEditorEditable(command.element_id, command.editable);
        }
        else if constexpr (std::is_same_v<T, Commands::SetTextEditorModified>) {
            document_manager_->SetTextEditorModified(command.element_id, command.modified);
        }
        else if constexpr (std::is_same_v<T, Commands::SetTextEditorConfig>) {
            document_manager_->SetTextEditorConfig(command.element_id, command.config_key, command.value);
        }
        else if constexpr (std::is_same_v<T, Commands::TextEditorCopy>) {
            document_manager_->TextEditorCopy(command.element_id);
        }
        else if constexpr (std::is_same_v<T, Commands::TextEditorPaste>) {
            document_manager_->TextEditorPaste(command.element_id);
        }
        else if constexpr (std::is_same_v<T, Commands::TextEditorCut>) {
            document_manager_->TextEditorCut(command.element_id);
        }
        else if constexpr (std::is_same_v<T, Commands::TextEditorSelectAll>) {
            document_manager_->TextEditorSelectAll(command.element_id);
        }
        else if constexpr (std::is_same_v<T, Commands::TextEditorUndo>) {
            document_manager_->TextEditorUndo(command.element_id);
        }
        else if constexpr (std::is_same_v<T, Commands::TextEditorRedo>) {
            document_manager_->TextEditorRedo(command.element_id);
        }
        else if constexpr (std::is_same_v<T, Commands::UpdateDataModel>) {
            data_model_manager_->UpdateModel(command.model_name, std::move(command.data));
        }
        else if constexpr (std::is_same_v<T, Commands::UpdateDataObject>) {
            data_model_manager_->UpdateObject(command.object_name, std::move(command.data));
        }
        else if constexpr (std::is_same_v<T, Commands::ReloadUIDocument>) {
            document_manager_->ReloadDocument(command.document_id);
        }
        else if constexpr (std::is_same_v<T, Commands::FileChanged>) {
            // This will be handled in main.cpp since it needs special logic
            // for RML vs RCSS files and path normalization
        }
        else if constexpr (std::is_same_v<T, Commands::AddFileWatch>) {
            // File watcher commands handled elsewhere
        }
        else if constexpr (std::is_same_v<T, Commands::RemoveFileWatch>) {
            // File watcher commands handled elsewhere
        }
        else if constexpr (std::is_same_v<T, Commands::RegisterGlobalEvent>) {
            event_dispatcher_->RegisterGlobalEvent(command.event_name, command.thread_id);
        }
        else if constexpr (std::is_same_v<T, Commands::UnregisterGlobalEvent>) {
            event_dispatcher_->UnregisterGlobalEvent(command.event_name);
        }
        else if constexpr (std::is_same_v<T, Commands::TriggerGlobalEvent>) {
            event_dispatcher_->DispatchGlobalEvent(command.event_name, command.payload);
        }
        else if constexpr (std::is_same_v<T, Commands::CloseApplication>) {
            LOG_INFO("Processing CloseApplication command");
            if (on_close_application_) {
                on_close_application_();
            }
        }
        else if constexpr (std::is_same_v<T, Commands::MarkSystemReady>) {
            event_dispatcher_->MarkSystemReady(command.system_name);
        }
        else if constexpr (std::is_same_v<T, Commands::QueryThreadList>) {
            LOG_INFO("Processing QueryThreadList command for thread {}", command.requesting_thread_id);

            // Get all thread info
            auto thread_infos = thread_manager_->GetAllThreadInfo();

            // Convert to PayloadMap with array-like DynamicMap
            PayloadMap response_data;
            DynamicRow threads_map;

            // Create array-like structure with numeric string keys
            for (size_t i = 0; i < thread_infos.size(); ++i) {
                const auto& info = thread_infos[i];
                DynamicRow thread_row;
                thread_row["thread_id"] = static_cast<int64_t>(info.thread_id);
                thread_row["script_path"] = info.script_path;
                thread_row["status"] = info.status;
                thread_row["uptime"] = info.uptime;

                // Use numeric string keys to create array (1-indexed for Lua)
                threads_map[std::to_string(i + 1)] = std::make_shared<DynamicMap>(DynamicMap{thread_row});
            }

            response_data["threads"] = std::make_shared<DynamicMap>(DynamicMap{threads_map});

            // Set promise to wake blocked Lua thread
            if (command.promise) {
                command.promise->set_value(std::move(response_data));
            }
        }
        else if constexpr (std::is_same_v<T, Commands::QueryThreadInfo>) {
            LOG_INFO("Processing QueryThreadInfo command for thread {}, querying thread {}",
                     command.requesting_thread_id, command.thread_id);

            // Get specific thread info
            auto info = thread_manager_->GetThreadInfo(command.thread_id);

            // Convert to PayloadMap
            PayloadMap response_data;
            response_data["thread_id"] = static_cast<int64_t>(info.thread_id);
            response_data["script_path"] = info.script_path;
            response_data["status"] = info.status;
            response_data["uptime"] = info.uptime;

            // Set promise to wake blocked Lua thread
            if (command.promise) {
                if (!thread_manager_->HasThread(command.thread_id)) {
                    command.promise->set_exception(
                        std::make_exception_ptr(std::runtime_error("Thread not found"))
                    );
                } else {
                    command.promise->set_value(std::move(response_data));
                }
            }
        }
        else if constexpr (std::is_same_v<T, Commands::QueryDocumentList>) {
            LOG_INFO("Processing QueryDocumentList command for thread {}", command.requesting_thread_id);

            // Get all document info
            auto document_infos = document_manager_->GetAllDocumentInfo();

            // Convert to PayloadMap with array-like DynamicMap
            PayloadMap response_data;
            DynamicRow documents_map;

            // Create array-like structure with numeric string keys
            for (size_t i = 0; i < document_infos.size(); ++i) {
                const auto& info = document_infos[i];
                DynamicRow doc_row;
                doc_row["document_id"] = info.document_id;
                doc_row["path"] = info.path;
                doc_row["visible"] = info.visible;
                doc_row["element_count"] = static_cast<int64_t>(info.element_count);
                doc_row["width"] = static_cast<int64_t>(info.width);
                doc_row["height"] = static_cast<int64_t>(info.height);

                // Use numeric string keys to create array (1-indexed for Lua)
                documents_map[std::to_string(i + 1)] = std::make_shared<DynamicMap>(DynamicMap{doc_row});
            }

            response_data["documents"] = std::make_shared<DynamicMap>(DynamicMap{documents_map});

            // Set promise to wake blocked Lua thread
            if (command.promise) {
                command.promise->set_value(std::move(response_data));
            }
        }
        else if constexpr (std::is_same_v<T, Commands::QueryDocumentInfo>) {
            LOG_INFO("Processing QueryDocumentInfo command for thread {}, querying document '{}'",
                     command.requesting_thread_id, command.document_id);

            // Get specific document info
            auto info = document_manager_->GetDocumentInfo(command.document_id);

            // Convert to PayloadMap
            PayloadMap response_data;
            response_data["document_id"] = info.document_id;
            response_data["path"] = info.path;
            response_data["visible"] = info.visible;
            response_data["element_count"] = static_cast<int64_t>(info.element_count);
            response_data["width"] = static_cast<int64_t>(info.width);
            response_data["height"] = static_cast<int64_t>(info.height);

            // Set promise to wake blocked Lua thread
            if (command.promise) {
                if (info.path.empty()) {
                    command.promise->set_exception(
                        std::make_exception_ptr(std::runtime_error("Document not found"))
                    );
                } else {
                    command.promise->set_value(std::move(response_data));
                }
            }
        }
        // Note: Notification commands (AddNotification, ClearNotifications, DismissNotification)
        // are now handled by the Lua notification system, not here

    }, std::move(cmd));
}
