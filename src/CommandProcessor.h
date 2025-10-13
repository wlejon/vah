#pragma once

#include "Commands.h"
#include <memory>

// Forward declarations
class ThreadManager;
class DocumentManager;
class DataModelManager;

class CommandProcessor {
public:
    CommandProcessor(
        ThreadManager* thread_manager,
        DocumentManager* document_manager,
        DataModelManager* data_model_manager
    );
    ~CommandProcessor() = default;

    // Process a single command
    void ProcessCommand(const Command& cmd);

private:
    ThreadManager* thread_manager_;
    DocumentManager* document_manager_;
    DataModelManager* data_model_manager_;
};
