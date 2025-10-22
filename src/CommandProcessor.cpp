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
    EventDispatcher* event_dispatcher
)
    : thread_manager_(thread_manager)
    , document_manager_(document_manager)
    , data_model_manager_(data_model_manager)
    , event_dispatcher_(event_dispatcher)
{
}

void CommandProcessor::ProcessCommand(const Command& cmd) {
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
        else if constexpr (std::is_same_v<T, Commands::UpdateDataModel>) {
            data_model_manager_->UpdateModel(command.model_name, std::move(const_cast<DynamicTable&>(command.data)));
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
        // Note: Notification commands (AddNotification, ClearNotifications, DismissNotification)
        // are now handled by the Lua notification system, not here

    }, cmd);
}
