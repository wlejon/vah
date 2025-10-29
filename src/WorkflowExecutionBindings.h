#pragma once

extern "C" {
    typedef struct lua_State lua_State;
}

namespace WorkflowExecutionBindings {

/**
 * Register execution API bindings in a lua_State.
 * Creates a global "execution" table with methods for workflow execution context.
 *
 * @param L The lua_State to register bindings into
 * @param execution_id The execution ID to associate with this lua_State
 */
void RegisterExecutionAPI(lua_State* L, int execution_id);

} // namespace WorkflowExecutionBindings
