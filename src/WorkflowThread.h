#pragma once

#include <string>
#include <vector>

/**
 * Configuration for creating a workflow execution thread.
 */
struct WorkflowThreadConfig {
    int workflow_id;
    int execution_id;
    std::vector<std::string> required_libraries;
};

/**
 * Create a new workflow execution thread.
 *
 * This function:
 * 1. Creates a new lua_State
 * 2. Registers requested libraries from WorkflowLibraryRegistry
 * 3. Registers execution API with the given execution_id
 * 4. Spawns the thread using the existing thread infrastructure
 *
 * @param config Configuration for the workflow thread
 * @return Thread ID on success, or -1 on failure
 */
int CreateWorkflowThread(const WorkflowThreadConfig& config);
