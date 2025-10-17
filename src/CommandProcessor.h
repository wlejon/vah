#pragma once

#include "Commands.h"
#include <memory>

// Forward declarations
class ThreadManager;
class DocumentManager;
class DataModelManager;
class NotificationFeed;

class CommandProcessor {
public:
    CommandProcessor(
        ThreadManager* thread_manager,
        DocumentManager* document_manager,
        DataModelManager* data_model_manager,
        NotificationFeed* notification_feed
    );
    ~CommandProcessor() = default;

    // Process a single command
    void ProcessCommand(const Command& cmd);

private:
    // Intercept command and create notification
    void InterceptForNotification(const Command& cmd);

    ThreadManager* thread_manager_;
    DocumentManager* document_manager_;
    DataModelManager* data_model_manager_;
    NotificationFeed* notification_feed_;
};
