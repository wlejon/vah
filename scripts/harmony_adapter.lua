-- Harmony Format Adapter
-- Implements the model adapter interface for OpenAI's gpt-oss-20b Harmony format
-- Reference: docs/harmony-format-specification.md

local ModelAdapter = require("model_adapter")

local HarmonyAdapter = setmetatable({}, {__index = ModelAdapter})
HarmonyAdapter.__index = HarmonyAdapter

-- Create a new Harmony adapter
function HarmonyAdapter.new()
    local self = setmetatable({}, HarmonyAdapter)
    return self
end

-- Generate system prompt in Harmony-compatible format
function HarmonyAdapter:generate_system_prompt(tools, workflow_state)
    local base_prompt = [[You are an expert data analyst and database designer assisting users in transforming unstructured data into structured, queryable knowledge environments.
Knowledge cutoff: 2024-06
Current date: 2025-10-20
Reasoning: high

# Tools

]]

    -- Convert tool definitions to Harmony format
    for _, tool in ipairs(tools) do
        base_prompt = base_prompt .. "## functions." .. tool.name .. "\n"
        base_prompt = base_prompt .. tool.description .. "\n\n"

        if tool.parameters and #tool.parameters > 0 then
            base_prompt = base_prompt .. "Parameters:\n"
            for _, param in ipairs(tool.parameters) do
                local required_str = param.required and "required" or "optional"
                base_prompt = base_prompt .. string.format("- %s (%s, %s): %s\n",
                    param.name, param.type, required_str, param.description)
            end
            base_prompt = base_prompt .. "\n"
        end

        base_prompt = base_prompt .. "Returns: " .. tool.returns .. "\n\n"
    end

    base_prompt = base_prompt .. "\nYour goal is to help users create a \"leaf\" - a self-contained data environment tailored to their specific domain and practice."

    -- Add workflow state-specific instructions
    if workflow_state then
        local state_prompts = {
            exploration = [[

CURRENT PHASE: Data Exploration

Your task is to systematically examine the ingested data:
1. Read file contents and metadata
2. Identify patterns, relationships, and hierarchies
3. Recognize domain-specific terminology and concepts
4. Detect data types, formats, and structural conventions
5. Note any anomalies, gaps, or ambiguities

Ask clarifying questions if needed. When ready, create a comprehension document.]],

            validation = [[

CURRENT PHASE: Understanding Validation

A comprehension document has been created. The user will provide feedback.
If the understanding is incomplete or incorrect, refine your analysis.
When the user confirms understanding is correct, we'll proceed to schema design.]],

            model_design = [[

CURRENT PHASE: Data Model Design

Based on the validated understanding, design a database schema that:
1. Reflects the natural structure of the domain
2. Normalizes where appropriate while preserving semantic relationships
3. Accommodates the specific patterns found in the user's data
4. Supports queries and views the community will need

Present the schema with clear explanations.]],

            transformation = [[

CURRENT PHASE: Data Transformation

Generate parsing scripts for each file type encountered.
Scripts should:
1. Handle format conversions and data cleaning
2. Map source data to the target schema
3. Include error handling and validation
4. Report progress and issues]]
        }

        if state_prompts[workflow_state] then
            base_prompt = base_prompt .. state_prompts[workflow_state]
        end
    end

    return base_prompt
end

-- Tokenize Harmony format response
-- Character-level lexer (no regex as per spec)
function HarmonyAdapter:tokenize(response_text)
    local tokens = {}
    local i = 1
    local len = #response_text

    while i <= len do
        -- Look for special tokens starting with <|
        if response_text:sub(i, i+1) == "<|" then
            local token_end = response_text:find("|>", i + 2, true)
            if token_end then
                local token = response_text:sub(i + 2, token_end - 1)
                table.insert(tokens, {type = "TOKEN", value = token})
                i = token_end + 2
            else
                -- No matching |>, treat as text
                table.insert(tokens, {type = "TEXT", value = response_text:sub(i, i)})
                i = i + 1
            end
        else
            -- Collect text until next token
            local next_token = response_text:find("<|", i, true)
            if next_token then
                local text = response_text:sub(i, next_token - 1)
                if #text > 0 then
                    table.insert(tokens, {type = "TEXT", value = text})
                end
                i = next_token
            else
                -- Rest of content is text
                local text = response_text:sub(i)
                if #text > 0 then
                    table.insert(tokens, {type = "TEXT", value = text})
                end
                break
            end
        end
    end

    return tokens
end

-- Parse tool calls from Harmony format token stream
function HarmonyAdapter:parse_tool_calls(tokens)
    local tool_calls = {}
    local i = 1

    while i <= #tokens do
        local tok = tokens[i]

        -- Look for: <|channel|> text <|message|> json
        -- Pattern: channel commentary to=functions.TOOL_NAME
        if tok.type == "TOKEN" and tok.value == "channel" then
            -- Next should be text with channel info
            if i + 1 <= #tokens and tokens[i + 1].type == "TEXT" then
                local channel_text = tokens[i + 1].value

                -- Check if it's a commentary channel with a recipient
                local recipient = channel_text:match("commentary%s+to=([^%s]+)")

                if recipient then
                    -- Look for <|message|> token
                    local msg_idx = i + 2
                    while msg_idx <= #tokens do
                        if tokens[msg_idx].type == "TOKEN" and tokens[msg_idx].value == "message" then
                            -- Next token should be the message content
                            if msg_idx + 1 <= #tokens and tokens[msg_idx + 1].type == "TEXT" then
                                local args_json = tokens[msg_idx + 1].value:match("^%s*(.-)%s*$")

                                -- Extract function name (including underscores)
                                local tool_name = recipient:match("functions%.([%w_]+)")
                                if tool_name then
                                    -- Parse JSON arguments
                                    local success, args = pcall(json.decode, args_json)
                                    if not success then
                                        -- JSON parse failed, log the error
                                        print("WARNING: Failed to parse JSON for " .. tool_name)
                                        print("Raw JSON: " .. args_json:sub(1, 200))
                                        args = {}
                                    end

                                    table.insert(tool_calls, {
                                        name = tool_name,
                                        arguments = args
                                    })
                                end
                            end
                            break
                        end
                        msg_idx = msg_idx + 1
                    end
                end
            end
        end

        i = i + 1
    end

    return tool_calls
end

-- Format tool execution results for Harmony format
function HarmonyAdapter:format_tool_results(results)
    local results_text = "Tool Results:\n"

    for _, tr in ipairs(results) do
        if tr.result.success then
            -- Encode result as JSON for consistency
            local result_str
            if type(tr.result.result) == "string" then
                result_str = tr.result.result
            else
                result_str = json.encode(tr.result.result)
            end
            results_text = results_text .. string.format("- %s: %s\n", tr.tool, result_str)
        else
            results_text = results_text .. string.format("- %s: ERROR - %s\n", tr.tool, tr.result.error)
        end
    end

    return results_text
end

-- Get adapter name
function HarmonyAdapter:get_name()
    return "HarmonyAdapter"
end

return HarmonyAdapter
