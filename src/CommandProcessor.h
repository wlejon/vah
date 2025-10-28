#pragma once

#include "Commands.h"
#include <memory>
#include <functional>

// Forward declarations
class ThreadManager;
class DocumentManager;
class DataModelManager;
class EventDispatcher;
class HttpServerThread;

class CommandProcessor {
public:
    CommandProcessor(
        ThreadManager* thread_manager,
        DocumentManager* document_manager,
        DataModelManager* data_model_manager,
        EventDispatcher* event_dispatcher,
        HttpServerThread* http_server_thread = nullptr,
        std::function<void()> on_close_application = nullptr
    );
    ~CommandProcessor() = default;

    // Process a single command
    void ProcessCommand(const Command& cmd);

private:
    ThreadManager* thread_manager_;
    DocumentManager* document_manager_;
    DataModelManager* data_model_manager_;
    EventDispatcher* event_dispatcher_;
    HttpServerThread* http_server_thread_;
    std::function<void()> on_close_application_;
};
