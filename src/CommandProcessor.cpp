#include "CommandProcessor.h"
#include "ThreadManager.h"
#include "DocumentManager.h"
#include "DataModelManager.h"
#include "NotificationFeed.h"
#include "Logger.h"

CommandProcessor::CommandProcessor(
    ThreadManager* thread_manager,
    DocumentManager* document_manager,
    DataModelManager* data_model_manager,
    NotificationFeed* notification_feed
)
    : thread_manager_(thread_manager)
    , document_manager_(document_manager)
    , data_model_manager_(data_model_manager)
    , notification_feed_(notification_feed)
{
}

void CommandProcessor::ProcessCommand(const Command& cmd) {
    // Intercept and notify BEFORE processing
    InterceptForNotification(cmd);

    std::visit([this](auto&& command) {
        using T = std::decay_t<decltype(command)>;

        if constexpr (std::is_same_v<T, Commands::SpawnThread>) {
            LOG_INFO("Processing SpawnThread command: {} (parent: {})", command.script_path, command.parent_thread_id);
            if (command.parent_thread_id != 0) {
                thread_manager_->SpawnThread(command.script_path, command.parent_thread_id, command.parent_request_id);
            } else {
                thread_manager_->SpawnThread(command.script_path);
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

    }, cmd);
}

void CommandProcessor::InterceptForNotification(const Command& cmd) {
    if (!notification_feed_) return;

    std::visit([this](auto&& command) {
        using T = std::decay_t<decltype(command)>;

        if constexpr (std::is_same_v<T, Commands::SpawnThread>) {
            Notification notif;
            notif.id = NotificationFeed::GenerateId();
            notif.type = static_cast<int>(NotificationType::Info);
            notif.title = "Starting thread";
            notif.message = command.script_path;
            notif.thread_name = "Main";
            notif.timestamp = NotificationFeed::GetCurrentTime();
            notif.dismissible = true;
            notif.expandable = false;
            notif.ttl_seconds = 5.0;
            notification_feed_->AddNotification(std::move(notif));
        }
        else if constexpr (std::is_same_v<T, Commands::UpdateDataModel>) {
            Notification notif;
            notif.id = NotificationFeed::GenerateId();
            notif.type = static_cast<int>(NotificationType::Progress);
            notif.title = "Updating data model";
            notif.message = command.model_name + " (" + std::to_string(command.data.size()) + " rows)";
            notif.thread_name = "System";
            notif.timestamp = NotificationFeed::GetCurrentTime();
            notif.dismissible = false;
            notif.expandable = false;
            notif.ttl_seconds = 5.0;
            notification_feed_->AddNotification(std::move(notif));
        }
        else if constexpr (std::is_same_v<T, Commands::LoadUIDocument>) {
            Notification notif;
            notif.id = NotificationFeed::GenerateId();
            notif.type = static_cast<int>(NotificationType::Info);
            notif.title = "Loading UI document";
            notif.message = command.document_path;
            notif.thread_name = "UI";
            notif.timestamp = NotificationFeed::GetCurrentTime();
            notif.dismissible = true;
            notif.expandable = false;
            notif.ttl_seconds = 5.0;
            notification_feed_->AddNotification(std::move(notif));
        }
        else if constexpr (std::is_same_v<T, Commands::StopThread>) {
            Notification notif;
            notif.id = NotificationFeed::GenerateId();
            notif.type = static_cast<int>(NotificationType::Warning);
            notif.title = "Stopping thread";
            notif.message = "Thread ID: " + std::to_string(command.thread_id);
            notif.thread_name = "Main";
            notif.timestamp = NotificationFeed::GetCurrentTime();
            notif.dismissible = true;
            notif.expandable = false;
            notif.ttl_seconds = 5.0;
            notification_feed_->AddNotification(std::move(notif));
        }
        else if constexpr (std::is_same_v<T, Commands::Print>) {
            // Only show print commands as notifications for important messages
            // (could filter based on content or add a flag)
        }
        // Other commands are not shown in notification feed (too noisy)
    }, cmd);
}
