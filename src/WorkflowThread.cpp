#include "WorkflowThread.h"
#include "WorkflowLibrary.h"
#include "Logger.h"
#include <sol/sol.hpp>
#include <sqlite3.h>
#include <thread>
#include <atomic>
#include <memory>
#include <unordered_map>
#include <mutex>

// Simple thread tracking
static std::atomic<int> g_next_workflow_thread_id{1000};
static std::mutex g_workflow_threads_mutex;
static std::unordered_map<int, std::shared_ptr<std::thread>> g_workflow_threads;

// Thread main function
static void WorkflowThreadMain(int thread_id, int execution_id, const std::vector<std::string>& required_libraries) {
    LOG_INFO("Workflow thread {} starting for execution {}", thread_id, execution_id);

    // Create new sol::state
    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::math,
                      sol::lib::string, sol::lib::table, sol::lib::os);

    // Register executor dependencies (always needed for workflow_executor.lua to run)
    std::vector<std::string> executor_deps = {"db", "json", "thread"};
    int executor_libs = WorkflowLibrary::WorkflowLibraryRegistry::RegisterRequestedLibraries(lua, executor_deps);
    LOG_INFO("Workflow thread {} registered {} executor libraries", thread_id, executor_libs);

    // Register requested libraries using WorkflowLibraryRegistry
    int registered = WorkflowLibrary::WorkflowLibraryRegistry::RegisterRequestedLibraries(lua, required_libraries);
    LOG_INFO("Workflow thread {} registered {} workflow libraries", thread_id, registered);

    // Register execution API using Lua implementation (no more hardcoded SQL in C++)
    try {
        sol::load_result load_result = lua.load_file("scripts/execution_api.lua");
        if (!load_result.valid()) {
            sol::error err = load_result;
            LOG_ERROR("Failed to load execution_api.lua: {}", err.what());
            return;
        }

        sol::protected_function_result exec_result = load_result();
        if (!exec_result.valid()) {
            sol::error err = exec_result;
            LOG_ERROR("Failed to execute execution_api.lua: {}", err.what());
            return;
        }

        sol::table execution_api_module = exec_result;
        sol::protected_function create_execution_api = execution_api_module["create_execution_api"];

        if (!create_execution_api.valid()) {
            LOG_ERROR("execution_api.lua does not export create_execution_api function");
            return;
        }

        sol::protected_function_result api_result = create_execution_api(execution_id);
        if (!api_result.valid()) {
            sol::error err = api_result;
            LOG_ERROR("Failed to create execution API: {}", err.what());
            return;
        }

        lua["execution"] = api_result.get<sol::table>();
        LOG_INFO("Workflow thread {} registered Lua-based execution API for execution {}", thread_id, execution_id);
    } catch (const std::exception& e) {
        LOG_ERROR("Exception while registering execution API: {}", e.what());
        return;
    }

    // Get workflow_id from execution record
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
        return;
    }

    LOG_INFO("Workflow thread {} executing workflow {} (execution {})", thread_id, workflow_id, execution_id);

    // Use sol to load and execute the Lua executor
    try {
        // Load the workflow executor module
        sol::load_result load_result = lua.load_file("scripts/workflow_executor.lua");
        if (!load_result.valid()) {
            sol::error err = load_result;
            LOG_ERROR("Failed to load workflow_executor.lua: {}", err.what());
            return;
        }

        // Execute to get the module
        sol::protected_function_result exec_result = load_result();
        if (!exec_result.valid()) {
            sol::error err = exec_result;
            LOG_ERROR("Failed to execute workflow_executor.lua: {}", err.what());
            return;
        }

        sol::table executor_module = exec_result;

        // Call execute_workflow function
        sol::protected_function execute_workflow = executor_module["execute_workflow"];
        if (!execute_workflow.valid()) {
            LOG_ERROR("workflow_executor.lua does not export execute_workflow function");
            return;
        }

        sol::protected_function_result result = execute_workflow(execution_id, workflow_id);
        if (!result.valid()) {
            sol::error err = result;
            LOG_ERROR("Workflow execution {} failed: {}", execution_id, err.what());
        } else {
            bool success = result;
            if (success) {
                LOG_INFO("Workflow execution {} completed successfully", execution_id);
            } else {
                LOG_ERROR("Workflow execution {} failed", execution_id);
            }
        }

    } catch (const std::exception& e) {
        LOG_ERROR("Workflow thread {} exception: {}", thread_id, e.what());
    }

    // sol::state destructor handles cleanup
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

void RegisterWorkflowThreadBindings(sol::state& lua) {
    // Get or create the thread table
    auto thread_table = lua["thread"].get_or_create<sol::table>();

    // Register create_workflow_thread function
    thread_table["create_workflow_thread"] = [](int workflow_id, int execution_id, sol::optional<sol::table> libraries) {
        WorkflowThreadConfig config;
        config.workflow_id = workflow_id;
        config.execution_id = execution_id;

        // Parse required libraries from table
        if (libraries) {
            for (const auto& [key, value] : libraries.value()) {
                if (value.is<std::string>()) {
                    config.required_libraries.push_back(value.as<std::string>());
                }
            }
        }

        int thread_id = CreateWorkflowThread(config);
        return thread_id;
    };

    LOG_DEBUG("Registered workflow thread bindings");
}
