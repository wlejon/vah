#include "WorkflowThread.h"
#include "WorkflowLibrary.h"
#include "WorkflowExecutionBindings.h"
#include "WorkflowExecutor.h"
#include "Logger.h"
#include <lua.hpp>
#include <sqlite3.h>
#include <thread>
#include <atomic>
#include <memory>
#include <unordered_map>
#include <mutex>

// Simple thread tracking
static std::atomic<int> g_next_workflow_thread_id{1000};  // Start at 1000 to distinguish from regular threads
static std::mutex g_workflow_threads_mutex;
static std::unordered_map<int, std::shared_ptr<std::thread>> g_workflow_threads;

// Thread main function
static void WorkflowThreadMain(int thread_id, int execution_id, const std::vector<std::string>& required_libraries) {
    LOG_INFO("Workflow thread {} starting for execution {}", thread_id, execution_id);

    // Create new lua_State
    lua_State* L = luaL_newstate();
    if (!L) {
        LOG_ERROR("Failed to create lua_State for workflow thread {}", thread_id);
        return;
    }

    // Open standard Lua libraries
    luaL_openlibs(L);

    // Register requested libraries using WorkflowLibraryRegistry
    int registered = WorkflowLibrary::WorkflowLibraryRegistry::RegisterRequestedLibraries(L, required_libraries);
    LOG_INFO("Workflow thread {} registered {} libraries", thread_id, registered);

    // Register execution API
    WorkflowExecutionBindings::RegisterExecutionAPI(L, execution_id);
    LOG_INFO("Workflow thread {} registered execution API for execution {}", thread_id, execution_id);

    // Create workflow executor
    WorkflowExecutor executor(L, execution_id);

    // Load workflow from database
    // Note: We need to get workflow_id from the execution record
    // For now, we'll need to query it from the database
    sqlite3* db = nullptr;
    int workflow_id = 0;

    if (sqlite3_open("data/workflow.db", &db) == SQLITE_OK) {
        std::string sql = "SELECT workflow_id FROM workflow_executions WHERE id = ?";
        sqlite3_stmt* stmt = nullptr;

        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, execution_id);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                workflow_id = sqlite3_column_int(stmt, 0);
            }
            sqlite3_finalize(stmt);
        }
        sqlite3_close_v2(db);
    }

    if (workflow_id == 0) {
        LOG_ERROR("Failed to get workflow_id for execution {}", execution_id);
        lua_close(L);
        return;
    }

    LOG_INFO("Workflow thread {} loading workflow {}", thread_id, workflow_id);

    if (!executor.LoadWorkflow(workflow_id)) {
        LOG_ERROR("Failed to load workflow {} for execution {}", workflow_id, execution_id);
        lua_close(L);
        return;
    }

    // Execute the workflow
    LOG_INFO("Workflow thread {} executing workflow {}", thread_id, workflow_id);
    bool success = executor.Execute();

    if (!success) {
        LOG_ERROR("Workflow execution {} failed", execution_id);
    } else {
        LOG_INFO("Workflow execution {} completed successfully", execution_id);
    }

    // Clean up
    lua_close(L);
    LOG_INFO("Workflow thread {} finished", thread_id);
}

int CreateWorkflowThread(const WorkflowThreadConfig& config) {
    try {
        // Validate config
        if (config.workflow_id <= 0 || config.execution_id <= 0) {
            LOG_ERROR("Invalid workflow config: workflow_id={}, execution_id={}",
                     config.workflow_id, config.execution_id);
            return -1;
        }

        // Allocate thread ID
        int thread_id = g_next_workflow_thread_id.fetch_add(1, std::memory_order_relaxed);

        // Create and start thread
        auto thread = std::make_shared<std::thread>(
            WorkflowThreadMain,
            thread_id,
            config.execution_id,
            config.required_libraries
        );

        // Store thread in registry
        {
            std::lock_guard<std::mutex> lock(g_workflow_threads_mutex);
            g_workflow_threads[thread_id] = thread;
        }

        // Detach thread (it will clean up itself)
        thread->detach();

        LOG_INFO("Created workflow thread {} for workflow {} execution {}",
                thread_id, config.workflow_id, config.execution_id);

        return thread_id;
    } catch (const std::exception& e) {
        LOG_ERROR("Failed to create workflow thread: {}", e.what());
        return -1;
    }
}
