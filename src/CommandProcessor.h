#pragma once

#include "Commands.h"
#include <memory>
#include <functional>
#include <unordered_map>
#include <moodycamel/concurrentqueue.h>

// Forward declarations
class ThreadManager;
class DocumentManager;
class DataModelManager;
class EventDispatcher;

class CommandProcessor {
public:
    CommandProcessor(
        ThreadManager* thread_manager,
        DocumentManager* document_manager,
        DataModelManager* data_model_manager,
        EventDispatcher* event_dispatcher,
        std::function<void()> on_close_application = nullptr
    );
    ~CommandProcessor() = default;

    // Process a single command
    void ProcessCommand(Command&& cmd);

    // Process all pending commands from the queue (used during shutdown)
    // Returns the number of commands processed
    int ProcessPendingCommands(moodycamel::ConcurrentQueue<Command>* command_queue);

private:
    ThreadManager* thread_manager_;
    DocumentManager* document_manager_;
    DataModelManager* data_model_manager_;
    EventDispatcher* event_dispatcher_;
    std::function<void()> on_close_application_;
};
