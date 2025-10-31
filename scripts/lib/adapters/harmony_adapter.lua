-- Harmony Format Adapter
-- Implements the model adapter interface for OpenAI's gpt-oss-20b Harmony format
-- Reference: docs/harmony-format-specification.md

local ModelAdapter = require("lib.adapters.model_adapter")

local HarmonyAdapter = setmetatable({}, {__index = ModelAdapter})
HarmonyAdapter.__index = HarmonyAdapter

-- Token types
local TOKEN_TYPES = {
    -- Harmony control tokens
    CONTROL_TOKEN = "CONTROL_TOKEN",  -- <|start|>, <|end|>, <|message|>, etc.

    -- JSON structural tokens
    LBRACE = "LBRACE",           -- {
    RBRACE = "RBRACE",           -- }
    LBRACKET = "LBRACKET",       -- [
    RBRACKET = "RBRACKET",       -- ]
    COLON = "COLON",             -- :
    COMMA = "COMMA",             -- ,

    -- JSON value tokens
    STRING = "STRING",           -- "text"
    NUMBER = "NUMBER",           -- 123, 45.67
    TRUE = "TRUE",               -- true
    FALSE = "FALSE",             -- false
    NULL = "NULL",               -- null

    -- Identifiers and text
    IDENTIFIER = "IDENTIFIER",   -- channel_name, function_name
    DOT = "DOT",                 -- .
    EQUALS = "EQUALS",           -- =

    -- Whitespace
    WHITESPACE = "WHITESPACE",   -- spaces, tabs, newlines

    -- Everything else
    TEXT = "TEXT"
}

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

The user has approved your understanding.

YOUR NEXT RESPONSE MUST BE A TOOL CALL to functions.propose_schema.

Create a schema with this structure:
{
  "schema": {
    "tables": [
      {
        "name": "table_name",
        "columns": [
          {"name": "col_name", "type": "type", "primary": true/false, "foreign_key": "other_table.col"}
        ]
      }
    ]
  }
}

Design the schema to:
1. Reflect the natural structure of the domain
2. Normalize appropriately while preserving semantic relationships
3. Accommodate the specific patterns in the user's data
4. Support queries the user will need

DO NOT write explanatory text. DO NOT ask questions. ONLY call functions.propose_schema with the complete schema.]],

            transformation = [[

CURRENT PHASE: Data Transformation

The user has approved the schema.

YOUR NEXT RESPONSE MUST BE TOOL CALLS to functions.generate_parser for each file type in the ingested data.

For each unique file type (based on file extensions), call:
{
  "file_type": "extension",
  "script_content": "complete parsing script code"
}

Each parser script should:
1. Read the file format and extract data
2. Map the data to the approved schema tables
3. Include error handling and validation
4. Generate INSERT statements or return structured data

DO NOT write explanatory text. DO NOT ask questions. ONLY call functions.generate_parser for each file type.]]
        }

        if state_prompts[workflow_state] then
            base_prompt = base_prompt .. state_prompts[workflow_state]
        end
    end

    return base_prompt
end

-- Helper: Check if character is whitespace
local function is_whitespace(char)
    return char == ' ' or char == '\t' or char == '\n' or char == '\r'
end

-- Helper: Check if character is a digit
local function is_digit(char)
    return char >= '0' and char <= '9'
end

-- Helper: Check if character is a letter
local function is_letter(char)
    return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z')
end

-- Helper: Check if character is identifier character
local function is_identifier_char(char)
    return is_letter(char) or is_digit(char) or char == '_'
end

-- Character-level lexer
function HarmonyAdapter:tokenize(text)
    local tokens = {}
    local i = 1
    local len = #text

    while i <= len do
        local char = text:sub(i, i)

        -- Control tokens: <|token_name|>
        if char == '<' and text:sub(i, i + 1) == '<|' then
            local close_pos = text:find("|>", i + 2, true)
            if close_pos then
                local token_value = text:sub(i + 2, close_pos - 1)
                table.insert(tokens, {
                    type = TOKEN_TYPES.CONTROL_TOKEN,
                    value = token_value,
                    pos = i
                })
                i = close_pos + 2
            else
                -- No closing |>, treat as text
                table.insert(tokens, {type = TOKEN_TYPES.TEXT, value = char, pos = i})
                i = i + 1
            end

        -- JSON structural characters
        elseif char == '{' then
            table.insert(tokens, {type = TOKEN_TYPES.LBRACE, value = char, pos = i})
            i = i + 1
        elseif char == '}' then
            table.insert(tokens, {type = TOKEN_TYPES.RBRACE, value = char, pos = i})
            i = i + 1
        elseif char == '[' then
            table.insert(tokens, {type = TOKEN_TYPES.LBRACKET, value = char, pos = i})
            i = i + 1
        elseif char == ']' then
            table.insert(tokens, {type = TOKEN_TYPES.RBRACKET, value = char, pos = i})
            i = i + 1
        elseif char == ':' then
            table.insert(tokens, {type = TOKEN_TYPES.COLON, value = char, pos = i})
            i = i + 1
        elseif char == ',' then
            table.insert(tokens, {type = TOKEN_TYPES.COMMA, value = char, pos = i})
            i = i + 1
        elseif char == '.' then
            table.insert(tokens, {type = TOKEN_TYPES.DOT, value = char, pos = i})
            i = i + 1
        elseif char == '=' then
            table.insert(tokens, {type = TOKEN_TYPES.EQUALS, value = char, pos = i})
            i = i + 1

        -- Whitespace
        elseif is_whitespace(char) then
            local ws_start = i
            while i <= len and is_whitespace(text:sub(i, i)) do
                i = i + 1
            end
            table.insert(tokens, {
                type = TOKEN_TYPES.WHITESPACE,
                value = text:sub(ws_start, i - 1),
                pos = ws_start
            })

        -- String literals
        elseif char == '"' then
            local str_start = i
            i = i + 1  -- Skip opening quote
            local escaped = false
            local str_value = ""

            while i <= len do
                local c = text:sub(i, i)
                if escaped then
                    -- Handle escape sequences
                    if c == 'n' then
                        str_value = str_value .. '\n'
                    elseif c == 't' then
                        str_value = str_value .. '\t'
                    elseif c == 'r' then
                        str_value = str_value .. '\r'
                    elseif c == '\\' then
                        str_value = str_value .. '\\'
                    elseif c == '"' then
                        str_value = str_value .. '"'
                    elseif c == '/' then
                        str_value = str_value .. '/'
                    else
                        -- Unknown escape, keep as-is
                        str_value = str_value .. '\\' .. c
                    end
                    escaped = false
                    i = i + 1
                elseif c == '\\' then
                    escaped = true
                    i = i + 1
                elseif c == '"' then
                    -- End of string
                    i = i + 1
                    break
                else
                    str_value = str_value .. c
                    i = i + 1
                end
            end

            table.insert(tokens, {
                type = TOKEN_TYPES.STRING,
                value = str_value,
                pos = str_start
            })

        -- Numbers
        elseif is_digit(char) or (char == '-' and i < len and is_digit(text:sub(i + 1, i + 1))) then
            local num_start = i
            if char == '-' then
                i = i + 1
            end

            -- Integer part
            while i <= len and is_digit(text:sub(i, i)) do
                i = i + 1
            end

            -- Decimal part
            if i <= len and text:sub(i, i) == '.' then
                i = i + 1
                while i <= len and is_digit(text:sub(i, i)) do
                    i = i + 1
                end
            end

            -- Exponent part
            if i <= len and (text:sub(i, i) == 'e' or text:sub(i, i) == 'E') then
                i = i + 1
                if i <= len and (text:sub(i, i) == '+' or text:sub(i, i) == '-') then
                    i = i + 1
                end
                while i <= len and is_digit(text:sub(i, i)) do
                    i = i + 1
                end
            end

            local num_text = text:sub(num_start, i - 1)
            table.insert(tokens, {
                type = TOKEN_TYPES.NUMBER,
                value = tonumber(num_text),
                pos = num_start
            })

        -- Keywords: true, false, null
        elseif text:sub(i, i + 3) == "true" then
            table.insert(tokens, {type = TOKEN_TYPES.TRUE, value = true, pos = i})
            i = i + 4
        elseif text:sub(i, i + 4) == "false" then
            table.insert(tokens, {type = TOKEN_TYPES.FALSE, value = false, pos = i})
            i = i + 5
        elseif text:sub(i, i + 3) == "null" then
            table.insert(tokens, {type = TOKEN_TYPES.NULL, value = nil, pos = i})
            i = i + 4

        -- Identifiers
        elseif is_letter(char) or char == '_' then
            local id_start = i
            while i <= len and is_identifier_char(text:sub(i, i)) do
                i = i + 1
            end
            table.insert(tokens, {
                type = TOKEN_TYPES.IDENTIFIER,
                value = text:sub(id_start, i - 1),
                pos = id_start
            })

        -- Everything else is text
        else
            table.insert(tokens, {type = TOKEN_TYPES.TEXT, value = char, pos = i})
            i = i + 1
        end
    end

    return tokens
end

-- Parse JSON from token stream
local function parse_json_value(tokens, idx)
    -- Skip whitespace
    while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
        idx = idx + 1
    end

    if idx > #tokens then
        return nil, idx, "Unexpected end of tokens"
    end

    local tok = tokens[idx]

    -- String
    if tok.type == TOKEN_TYPES.STRING then
        return tok.value, idx + 1, nil

    -- Number
    elseif tok.type == TOKEN_TYPES.NUMBER then
        return tok.value, idx + 1, nil

    -- Boolean and null
    elseif tok.type == TOKEN_TYPES.TRUE then
        return true, idx + 1, nil
    elseif tok.type == TOKEN_TYPES.FALSE then
        return false, idx + 1, nil
    elseif tok.type == TOKEN_TYPES.NULL then
        return nil, idx + 1, nil

    -- Object
    elseif tok.type == TOKEN_TYPES.LBRACE then
        local obj = {}
        idx = idx + 1

        -- Skip whitespace
        while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
            idx = idx + 1
        end

        -- Empty object
        if idx <= #tokens and tokens[idx].type == TOKEN_TYPES.RBRACE then
            return obj, idx + 1, nil
        end

        while idx <= #tokens do
            -- Skip whitespace
            while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
                idx = idx + 1
            end

            -- Key (must be string)
            if idx > #tokens or tokens[idx].type ~= TOKEN_TYPES.STRING then
                return nil, idx, "Expected string key in object"
            end
            local key = tokens[idx].value
            idx = idx + 1

            -- Skip whitespace
            while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
                idx = idx + 1
            end

            -- Colon
            if idx > #tokens or tokens[idx].type ~= TOKEN_TYPES.COLON then
                return nil, idx, "Expected : after object key"
            end
            idx = idx + 1

            -- Value
            local value, new_idx, err = parse_json_value(tokens, idx)
            if err then
                return nil, new_idx, err
            end
            obj[key] = value
            idx = new_idx

            -- Skip whitespace
            while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
                idx = idx + 1
            end

            -- Check for comma or closing brace
            if idx > #tokens then
                return nil, idx, "Unexpected end in object"
            end

            if tokens[idx].type == TOKEN_TYPES.RBRACE then
                return obj, idx + 1, nil
            elseif tokens[idx].type == TOKEN_TYPES.COMMA then
                idx = idx + 1
            else
                return nil, idx, "Expected , or } in object"
            end
        end

        return nil, idx, "Unclosed object"

    -- Array
    elseif tok.type == TOKEN_TYPES.LBRACKET then
        local arr = {}
        idx = idx + 1

        -- Skip whitespace
        while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
            idx = idx + 1
        end

        -- Empty array
        if idx <= #tokens and tokens[idx].type == TOKEN_TYPES.RBRACKET then
            return arr, idx + 1, nil
        end

        while idx <= #tokens do
            -- Parse value
            local value, new_idx, err = parse_json_value(tokens, idx)
            if err then
                return nil, new_idx, err
            end
            table.insert(arr, value)
            idx = new_idx

            -- Skip whitespace
            while idx <= #tokens and tokens[idx].type == TOKEN_TYPES.WHITESPACE do
                idx = idx + 1
            end

            -- Check for comma or closing bracket
            if idx > #tokens then
                return nil, idx, "Unexpected end in array"
            end

            if tokens[idx].type == TOKEN_TYPES.RBRACKET then
                return arr, idx + 1, nil
            elseif tokens[idx].type == TOKEN_TYPES.COMMA then
                idx = idx + 1
            else
                return nil, idx, "Expected , or ] in array"
            end
        end

        return nil, idx, "Unclosed array"
    else
        return nil, idx, "Unexpected token: " .. tok.type
    end
end

-- Parse tool calls from Harmony format token stream
function HarmonyAdapter:parse_tool_calls(tokens)
    local tool_calls = {}
    local i = 1

    while i <= #tokens do
        local tok = tokens[i]

        -- Look for <|channel|>
        if tok.type == TOKEN_TYPES.CONTROL_TOKEN and tok.value == "channel" then
            -- Parse channel attributes
            -- Format: commentary to=functions.TOOL_NAME
            local channel_info = {
                name = nil,
                to = nil
            }

            i = i + 1

            -- Skip whitespace
            while i <= #tokens and tokens[i].type == TOKEN_TYPES.WHITESPACE do
                i = i + 1
            end

            -- Parse channel name (identifier)
            if i <= #tokens and tokens[i].type == TOKEN_TYPES.IDENTIFIER then
                channel_info.name = tokens[i].value
                i = i + 1
            end

            -- Skip whitespace
            while i <= #tokens and tokens[i].type == TOKEN_TYPES.WHITESPACE do
                i = i + 1
            end

            -- Parse attributes (to=...)
            while i <= #tokens do
                if tokens[i].type == TOKEN_TYPES.IDENTIFIER then
                    local attr_name = tokens[i].value
                    i = i + 1

                    if i <= #tokens and tokens[i].type == TOKEN_TYPES.EQUALS then
                        i = i + 1

                        -- Parse qualified name: functions.tool_name
                        local qualified_name = ""
                        while i <= #tokens do
                            if tokens[i].type == TOKEN_TYPES.IDENTIFIER then
                                qualified_name = qualified_name .. tokens[i].value
                                i = i + 1
                            elseif tokens[i].type == TOKEN_TYPES.DOT then
                                qualified_name = qualified_name .. "."
                                i = i + 1
                            else
                                break
                            end
                        end

                        if attr_name == "to" then
                            channel_info.to = qualified_name
                        end
                    end

                    -- Skip whitespace
                    while i <= #tokens and tokens[i].type == TOKEN_TYPES.WHITESPACE do
                        i = i + 1
                    end
                elseif tokens[i].type == TOKEN_TYPES.CONTROL_TOKEN then
                    -- Next control token, stop parsing attributes
                    break
                else
                    i = i + 1
                end
            end

            -- Only process commentary channels with recipients
            if channel_info.name == "commentary" and channel_info.to then
                -- Look for <|message|> token
                while i <= #tokens do
                    if tokens[i].type == TOKEN_TYPES.CONTROL_TOKEN and tokens[i].value == "message" then
                        i = i + 1

                        -- Parse JSON arguments
                        local args, new_idx, err = parse_json_value(tokens, i)

                        -- Extract tool name from qualified name first
                        -- Format: functions.tool_name
                        local namespace, tool_name = channel_info.to:match("([^%.]+)%.(.+)")

                        if err then
                            -- Build error context showing the problematic area
                            local error_context = ""
                            local context_start = math.max(1, new_idx - 5)
                            local context_end = math.min(#tokens, new_idx + 5)

                            for ctx_i = context_start, context_end do
                                if ctx_i == new_idx then
                                    error_context = error_context .. " >>> "
                                end
                                local tok = tokens[ctx_i]
                                if tok.type == TOKEN_TYPES.CONTROL_TOKEN then
                                    error_context = error_context .. "<|" .. tok.value .. "|>"
                                elseif tok.type == TOKEN_TYPES.WHITESPACE then
                                    -- Show whitespace as visible characters
                                    error_context = error_context .. tok.value:gsub("\n", "\\n"):gsub("\t", "\\t")
                                else
                                    error_context = error_context .. tostring(tok.value)
                                end
                                if ctx_i == new_idx then
                                    error_context = error_context .. " <<< "
                                end
                                if ctx_i < context_end then
                                    error_context = error_context .. " "
                                end
                            end

                            print("WARNING: Failed to parse JSON for " .. (tool_name or "unknown"))
                            print("Error: " .. err)
                            print("Context: " .. error_context)

                            -- Return the error as a failed tool call so the agent can see it
                            if namespace == "functions" and tool_name then
                                table.insert(tool_calls, {
                                    name = tool_name,
                                    arguments = {},
                                    parse_error = {
                                        message = err,
                                        position = new_idx,
                                        context = error_context
                                    }
                                })
                            end

                            -- Skip to next control token
                            while i <= #tokens and tokens[i].type ~= TOKEN_TYPES.CONTROL_TOKEN do
                                i = i + 1
                            end
                        else
                            i = new_idx

                            if namespace == "functions" and tool_name then
                                table.insert(tool_calls, {
                                    name = tool_name,
                                    arguments = args or {}
                                })
                            end
                        end

                        break
                    end
                    i = i + 1
                end
            end
        else
            i = i + 1
        end
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
