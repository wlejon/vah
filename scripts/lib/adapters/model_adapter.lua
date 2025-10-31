-- Model Adapter Interface
-- Base class/interface for model-specific adapters
-- Each adapter translates between model formats and VAH's tool system

local ModelAdapter = {}
ModelAdapter.__index = ModelAdapter

-- Create a new adapter instance
function ModelAdapter.new()
    local self = setmetatable({}, ModelAdapter)
    return self
end

-- Generate system prompt from tool definitions and workflow state
-- @param tools Array of tool definition objects
-- @param workflow_state Current workflow state information
-- @return string System prompt formatted for the specific model
function ModelAdapter:generate_system_prompt(tools, workflow_state)
    error("generate_system_prompt must be implemented by subclass")
end

-- Tokenize model response into typed tokens
-- @param response_text Raw response text from the model
-- @return Array of token objects {type, value}
function ModelAdapter:tokenize(response_text)
    error("tokenize must be implemented by subclass")
end

-- Parse tool calls from token stream
-- @param tokens Array of token objects from tokenize()
-- @return Array of tool call objects {name, arguments}
function ModelAdapter:parse_tool_calls(tokens)
    error("parse_tool_calls must be implemented by subclass")
end

-- Format tool execution results to send back to model
-- @param results Array of result objects {tool, result}
-- @return string Formatted results for the model
function ModelAdapter:format_tool_results(results)
    error("format_tool_results must be implemented by subclass")
end

-- Helper: Get model name/identifier
function ModelAdapter:get_name()
    return "BaseAdapter"
end

return ModelAdapter
