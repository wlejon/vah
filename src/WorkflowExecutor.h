#pragma once

#include <lua.hpp>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>
#include <map>

/**
 * Represents a workflow node loaded from the database.
 */
struct WorkflowNode {
    int id;              // node_id from workflow_nodes
    int type_id;         // node_type_id
    double x;
    double y;
    nlohmann::json config;  // Parsed from config JSON field
};

/**
 * Represents a connection between workflow nodes.
 */
struct WorkflowConnection {
    int from_node;
    int from_port;
    int to_node;
    int to_port;
};

/**
 * Core workflow execution engine.
 *
 * Responsible for:
 * - Loading workflow definition from database
 * - Executing nodes in topological order
 * - Handling callback nodes (on_start, on_complete, etc.)
 * - Managing node script execution in sandboxed Lua environments
 * - Updating execution state in database
 */
class WorkflowExecutor {
public:
    /**
     * Construct a workflow executor.
     *
     * @param L Lua state for script execution
     * @param execution_id ID of the execution record in workflow_executions table
     */
    WorkflowExecutor(lua_State* L, int execution_id);

    /**
     * Load workflow definition from database.
     *
     * @param workflow_id ID of the workflow to load
     * @return true on success, false on error
     */
    bool LoadWorkflow(int workflow_id);

    /**
     * Execute the loaded workflow.
     *
     * Executes nodes in topological order, handling callbacks and updating state.
     *
     * @return true on successful completion, false on error or stop command
     */
    bool Execute();

    /**
     * Stop execution (can be called from another thread).
     */
    void Stop();

private:
    // Core execution methods

    /**
     * Perform topological sort to determine node execution order.
     *
     * @return Vector of node IDs in execution order, empty if cycle detected
     */
    std::vector<int> TopologicalSort();

    /**
     * Execute a single node's script.
     *
     * @param node_id ID of the node to execute
     * @param inputs JSON object containing input values from connected nodes
     * @return true on success, false on error
     */
    bool ExecuteNode(int node_id, const nlohmann::json& inputs);

    /**
     * Execute all callback nodes of a specific type.
     *
     * @param callback_type Type of callback ("on_start", "on_complete", etc.)
     * @param context JSON object with context data for the callback
     * @return true on success, false on error
     */
    bool ExecuteCallbackNodes(const std::string& callback_type, const nlohmann::json& context);

    /**
     * Gather input values for a node from connected nodes' outputs.
     *
     * @param node_id Node to gather inputs for
     * @return JSON object mapping input port names to values
     */
    nlohmann::json GatherNodeInputs(int node_id);

    /**
     * Check for control commands (pause/stop) from execution_control table.
     *
     * @return true to continue execution, false to stop
     */
    bool CheckControlCommand();

    /**
     * Update execution status in workflow_executions table.
     *
     * @param status Status string ("running", "completed", "error", "stopped")
     * @param error Optional error message
     */
    void UpdateExecutionStatus(const std::string& status, const std::string& error = "");

    /**
     * Update node execution status in execution_nodes table.
     *
     * @param node_id Node ID
     * @param status Status string ("pending", "running", "completed", "error")
     * @param outputs JSON object containing node outputs (empty for non-completed states)
     * @param error Optional error message
     */
    void UpdateNodeStatus(int node_id, const std::string& status,
                         const nlohmann::json& outputs = nlohmann::json::object(),
                         const std::string& error = "");

    // Helper methods for Lua interaction

    /**
     * Push a JSON value onto the Lua stack.
     */
    void PushJsonToLua(const nlohmann::json& j);

    /**
     * Convert Lua value at stack index to JSON.
     */
    nlohmann::json LuaToJson(int index);

    // Member variables
    lua_State* m_lua_state;
    int m_execution_id;
    int m_workflow_id;

    std::vector<WorkflowNode> m_nodes;
    std::vector<WorkflowConnection> m_connections;
    std::vector<WorkflowNode> m_callback_nodes;

    // Map of node_id -> outputs (JSON)
    std::map<int, nlohmann::json> m_node_outputs;

    // Stop flag for thread-safe termination
    bool m_stop_requested;

    // Last error message
    std::string m_last_error;
};
