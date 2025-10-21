-- Manufold Agent System
-- Agent-assisted workflow for transforming unstructured data into structured knowledge environments

local LMStudioClient = require("lm_studio_client")

-- Create LM Studio client
local client = LMStudioClient.new("http://127.0.0.1:1234", "openai/gpt-oss-20b")

-- Workflow states
local WORKFLOW_STATES = {
    WELCOME = "welcome",
    INGESTION = "ingestion",
    EXPLORATION = "exploration",
    VALIDATION = "validation",
    MODEL_DESIGN = "model_design",
    TRANSFORMATION = "transformation",
    VIEW_GENERATION = "view_generation",
    COMPLETE = "complete"
}

-- Agent state
local agent_state = {
    -- Workflow
    current_state = WORKFLOW_STATES.WELCOME,
    session_id = nil,

    -- Ingestion
    ingested_files = {},
    file_count = 0,
    ingestion_status = "",

    -- Agent conversation
    conversation_history = {},  -- {role, content}
    current_response = "",
    is_thinking = false,

    -- Understanding
    comprehension_doc = "",
    user_feedback = "",
    understanding_validated = false,

    -- Data model
    proposed_schema = false,  -- {tables, relationships} - use false instead of nil for data binding
    schema_json = "",       -- JSON string representation for display
    schema_approved = false,

    -- Transformation
    generated_scripts = {},
    import_progress = 0,
    import_status = "",

    -- Database
    db_path = "",

    -- UI state
    status_message = "Welcome to Manufold",
    can_proceed = false,
    show_feedback_input = false,

    -- Helper booleans for UI conditionals
    has_conversation = false,
    has_scripts = false,
}

-- Tool definitions in Harmony format
local TOOLS_DESCRIPTION = [[
# Tools

## functions.list_files
Lists all files that have been ingested into the current session.

Returns: JSON array of file objects with name, path, size, and type fields.

## functions.read_file
Reads the complete contents of a specific file.

Parameters:
- path (string, required): Full path to the file to read

Returns: File contents as a string.

## functions.create_comprehension_doc
Creates a comprehension document describing what the data represents.

Parameters:
- content (string, required): Markdown-formatted comprehension document

Returns: Confirmation message.

## functions.propose_schema
Proposes a database schema for the ingested data.

Parameters:
- schema (object, required): Schema definition with tables array, each containing name and columns

Returns: Confirmation message.

## functions.generate_parser
Generates a parsing script for a specific file type.

Parameters:
- file_type (string, required): File extension (csv, json, txt, etc)
- script_content (string, required): Lua script code for parsing the file type

Returns: Confirmation message.
]]

-- System prompt for the agent
local function get_system_prompt(workflow_state)
    local base_prompt = [[You are an expert data analyst and database designer assisting users in transforming unstructured data into structured, queryable knowledge environments.
Knowledge cutoff: 2024-06
Current date: 2025-10-20
Reasoning: high

]] .. TOOLS_DESCRIPTION .. [[

Your goal is to help users create a "leaf" - a self-contained data environment tailored to their specific domain and practice.]]

    local state_prompts = {
        [WORKFLOW_STATES.EXPLORATION] = [[

CURRENT PHASE: Data Exploration

Your task is to systematically examine the ingested data:
1. Read file contents and metadata
2. Identify patterns, relationships, and hierarchies
3. Recognize domain-specific terminology and concepts
4. Detect data types, formats, and structural conventions
5. Note any anomalies, gaps, or ambiguities

Ask clarifying questions if needed. When ready, create a comprehension document.]],

        [WORKFLOW_STATES.VALIDATION] = [[

CURRENT PHASE: Understanding Validation

A comprehension document has been created. The user will provide feedback.
If the understanding is incomplete or incorrect, refine your analysis.
When the user confirms understanding is correct, we'll proceed to schema design.]],

        [WORKFLOW_STATES.MODEL_DESIGN] = [[

CURRENT PHASE: Data Model Design

Based on the validated understanding, design a database schema that:
1. Reflects the natural structure of the domain
2. Normalizes where appropriate while preserving semantic relationships
3. Accommodates the specific patterns found in the user's data
4. Supports queries and views the community will need

Present the schema with clear explanations.]],

        [WORKFLOW_STATES.TRANSFORMATION] = [[

CURRENT PHASE: Data Transformation

Generate parsing scripts for each file type encountered.
Scripts should:
1. Handle format conversions and data cleaning
2. Map source data to the target schema
3. Include error handling and validation
4. Report progress and issues]]
    }

    return base_prompt .. (state_prompts[workflow_state] or "")
end

-- Execute a tool call
local function execute_tool(tool_name, arguments)
    print("Executing tool: " .. tool_name)

    if tool_name == "list_files" then
        return {
            success = true,
            result = agent_state.ingested_files
        }

    elseif tool_name == "read_file" then
        local path = arguments.path
        if not path then
            return {success = false, error = "Missing path parameter"}
        end

        local content, error = fs.read_file(path)
        if error then
            return {success = false, error = error}
        end

        return {success = true, result = content}

    elseif tool_name == "create_comprehension_doc" then
        agent_state.comprehension_doc = arguments.content or ""
        agent_state.show_feedback_input = true
        update_ui()

        return {success = true, result = "Comprehension document created"}

    elseif tool_name == "propose_schema" then
        agent_state.proposed_schema = arguments.schema
        -- Convert to JSON for display
        agent_state.schema_json = json.encode(arguments.schema, true) or "{}"
        update_ui()

        return {success = true, result = "Schema proposed"}

    elseif tool_name == "generate_parser" then
        table.insert(agent_state.generated_scripts, {
            file_type = arguments.file_type,
            script = arguments.script_content
        })
        update_ui()

        return {success = true, result = "Parser script generated"}

    else
        return {success = false, error = "Unknown tool: " .. tool_name}
    end
end

-- Simple lexer for Harmony format tokens
local function tokenize_harmony(content)
    local tokens = {}
    local i = 1
    local len = #content

    while i <= len do
        -- Look for special tokens starting with <|
        if content:sub(i, i+1) == "<|" then
            local token_end = content:find("|>", i + 2, true)
            if token_end then
                local token = content:sub(i + 2, token_end - 1)
                table.insert(tokens, {type = "token", value = token})
                i = token_end + 2
            else
                i = i + 1
            end
        else
            -- Collect text until next token
            local next_token = content:find("<|", i, true)
            if next_token then
                local text = content:sub(i, next_token - 1)
                if #text > 0 then
                    table.insert(tokens, {type = "text", value = text})
                end
                i = next_token
            else
                -- Rest of content is text
                local text = content:sub(i)
                if #text > 0 then
                    table.insert(tokens, {type = "text", value = text})
                end
                break
            end
        end
    end

    return tokens
end

-- Parse tool calls from Harmony format tokens
local function parse_tool_calls(content)
    local tool_calls = {}
    local tokens = tokenize_harmony(content)

    local i = 1
    while i <= #tokens do
        local tok = tokens[i]

        -- Look for: <|channel|> text <|message|> json
        if tok.type == "token" and tok.value == "channel" then
            -- Next should be text with channel info
            if i + 1 <= #tokens and tokens[i + 1].type == "text" then
                local channel_text = tokens[i + 1].value

                -- Check if it's a commentary channel with a recipient
                local recipient = channel_text:match("commentary%s+to=([^%s]+)")

                if recipient then
                    print("Found channel commentary to: " .. recipient)

                    -- Look for <|message|> token
                    local msg_idx = i + 2
                    while msg_idx <= #tokens do
                        if tokens[msg_idx].type == "token" and tokens[msg_idx].value == "message" then
                            -- Next token should be the message content
                            if msg_idx + 1 <= #tokens and tokens[msg_idx + 1].type == "text" then
                                local args_json = tokens[msg_idx + 1].value:match("^%s*(.-)%s*$")

                                -- Extract function name (including underscores)
                                local tool_name = recipient:match("functions%.([%w_]+)")
                                if tool_name then
                                    print("Tool: " .. tool_name .. ", Args: " .. args_json)

                                    local success, args = pcall(json.decode, args_json)
                                    if not success then
                                        print("JSON parse failed, using empty object")
                                        args = {}
                                    end

                                    table.insert(tool_calls, {
                                        name = tool_name,
                                        arguments = args
                                    })
                                    print("Detected Harmony tool call: " .. tool_name)
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

-- Send a message to the agent
local function send_to_agent(user_message)
    -- Add user message to conversation
    if user_message and user_message ~= "" then
        table.insert(agent_state.conversation_history, {
            role = "user",
            content = user_message
        })
    end

    agent_state.is_thinking = true
    agent_state.current_response = ""
    agent_state.status_message = "Agent is thinking..."
    update_ui()

    -- Build messages for API
    local messages = {
        {role = "system", content = get_system_prompt(agent_state.current_state)}
    }

    -- Add conversation history
    for _, msg in ipairs(agent_state.conversation_history) do
        table.insert(messages, msg)
    end

    -- Make agent request
    local response, error = client:chat(messages, {
        temperature = 0.7,
        max_tokens = 2000
    })

    if error then
        print("Agent error: " .. error)
        agent_state.is_thinking = false
        agent_state.status_message = "Error: " .. error
        update_ui()
        return
    end

    if not response or not response.choices or not response.choices[1] then
        print("Invalid response from agent")
        agent_state.is_thinking = false
        agent_state.status_message = "Error: Invalid response"
        update_ui()
        return
    end

    local message = response.choices[1].message
    local content = message.content or ""

    print("Agent response: " .. content)

    -- Parse and execute tool calls
    local tool_calls = parse_tool_calls(content)

    print("Found " .. #tool_calls .. " tool calls")

    -- Add assistant message first (without tool results)
    table.insert(agent_state.conversation_history, {
        role = "assistant",
        content = content
    })

    if #tool_calls > 0 then
        print("Executing " .. #tool_calls .. " tool calls")
        local tool_results = {}

        for _, call in ipairs(tool_calls) do
            local result = execute_tool(call.name, call.arguments)
            table.insert(tool_results, {
                tool = call.name,
                result = result
            })
        end

        -- Format tool results as message to send back to agent
        local results_text = "Tool Results:\n"
        for _, tr in ipairs(tool_results) do
            if tr.result.success then
                results_text = results_text .. string.format("- %s: %s\n", tr.tool, json.encode(tr.result.result))
            else
                results_text = results_text .. string.format("- %s: ERROR - %s\n", tr.tool, tr.result.error)
            end
        end

        -- Send tool results back to agent
        send_to_agent(results_text)
    else
        agent_state.current_response = content
        agent_state.is_thinking = false
        agent_state.status_message = get_status_for_state()
        update_ui()
    end
end

-- Get status message for current state
function get_status_for_state()
    local status_messages = {
        [WORKFLOW_STATES.WELCOME] = "Drop files or folders to begin",
        [WORKFLOW_STATES.INGESTION] = "Ingesting files...",
        [WORKFLOW_STATES.EXPLORATION] = "Agent is exploring your data",
        [WORKFLOW_STATES.VALIDATION] = "Review the agent's understanding",
        [WORKFLOW_STATES.MODEL_DESIGN] = "Agent is designing the data model",
        [WORKFLOW_STATES.TRANSFORMATION] = "Transforming data...",
        [WORKFLOW_STATES.VIEW_GENERATION] = "Generating views...",
        [WORKFLOW_STATES.COMPLETE] = "Environment created successfully"
    }
    return status_messages[agent_state.current_state] or "Ready"
end

-- Update UI with current state
function update_ui()
    -- Update helper booleans
    agent_state.has_conversation = #agent_state.conversation_history > 0
    agent_state.has_scripts = #agent_state.generated_scripts > 0

    data.bind("manufold", {agent_state})

    -- Update texteditor content for messages
    for i, msg in ipairs(agent_state.conversation_history) do
        local editor_id = "msg_" .. (i - 1)  -- 0-indexed
        ui.set_texteditor_content(editor_id, msg.content)
        ui.set_texteditor_editable(editor_id, false)

        -- Also for model design conversation
        local design_id = "msg_design_" .. (i - 1)
        ui.set_texteditor_content(design_id, msg.content)
        ui.set_texteditor_editable(design_id, false)
    end

    -- Update current response
    if agent_state.current_response ~= "" then
        ui.set_texteditor_content("current_response", agent_state.current_response)
        ui.set_texteditor_editable("current_response", false)
    end
end

-- Event handlers

local function on_files_dropped(payload)
    print("Files dropped")

    -- Transition to ingestion state
    agent_state.current_state = WORKFLOW_STATES.INGESTION
    agent_state.status_message = "Ingesting files..."
    update_ui()

    -- Get dropped file path from payload
    local path = payload.path
    if not path then
        print("ERROR: No path in file_drop payload")
        return
    end

    print("Ingesting: " .. path)

    local stat_result, stat_err = fs.stat(path)
    if stat_result and stat_result.is_dir then
        -- Ingest directory recursively
        fs.walk(path, function(entry_path, is_dir, size)
            if not is_dir then
                table.insert(agent_state.ingested_files, {
                    path = entry_path,
                    name = fs.basename(entry_path),
                    size = size or 0,
                    type = fs.extension(entry_path) or "unknown"
                })
            end
            return true  -- Continue walking
        end)
    else
        -- Single file
        table.insert(agent_state.ingested_files, {
            path = path,
            name = fs.basename(path),
            size = 0,
            type = fs.extension(path) or "unknown"
        })
    end

    agent_state.file_count = #agent_state.ingested_files
    agent_state.ingestion_status = "Ingested " .. agent_state.file_count .. " files"

    -- Transition to exploration
    agent_state.current_state = WORKFLOW_STATES.EXPLORATION
    agent_state.status_message = get_status_for_state()
    agent_state.can_proceed = true
    update_ui()

    print("Ingestion complete: " .. agent_state.file_count .. " files")
end

local function on_start_exploration(payload)
    print("Starting exploration")

    -- Send initial message to agent
    local initial_message = string.format(
        "I have ingested %d files. Please analyze this data and help me understand what it represents. Here's a summary:\n\n",
        agent_state.file_count
    )

    -- Add file list
    for i, file in ipairs(agent_state.ingested_files) do
        if i <= 20 then  -- Limit to first 20 files
            initial_message = initial_message .. string.format("- %s (%s)\n", file.name, file.type)
        end
    end

    if agent_state.file_count > 20 then
        initial_message = initial_message .. string.format("... and %d more files\n", agent_state.file_count - 20)
    end

    send_to_agent(initial_message)
end

local function on_send_message(payload)
    local message = payload.message or ""
    if message ~= "" then
        send_to_agent(message)
    end
end

local function on_submit_feedback(payload)
    local feedback = payload.feedback or ""

    if feedback == "" then
        return
    end

    agent_state.user_feedback = feedback

    -- Send feedback to agent
    send_to_agent("FEEDBACK: " .. feedback)

    agent_state.show_feedback_input = false
    update_ui()
end

local function on_approve_understanding(payload)
    print("Understanding approved")

    agent_state.understanding_validated = true
    agent_state.current_state = WORKFLOW_STATES.MODEL_DESIGN
    agent_state.status_message = get_status_for_state()
    update_ui()

    -- Ask agent to propose schema
    send_to_agent("The understanding is correct. Please propose a database schema for this data.")
end

local function on_approve_schema(payload)
    print("Schema approved")

    agent_state.schema_approved = true
    agent_state.current_state = WORKFLOW_STATES.TRANSFORMATION
    agent_state.status_message = get_status_for_state()
    update_ui()

    -- Ask agent to generate parsers
    send_to_agent("The schema is approved. Please generate parsing scripts for the data transformation.")
end

local function on_start_import(payload)
    print("Starting import")

    -- Create database
    agent_state.session_id = "session_" .. os.time()
    agent_state.db_path = "data/" .. agent_state.session_id .. ".db"

    -- For now, just simulate the import
    -- In a real implementation, we'd execute the generated scripts

    agent_state.import_progress = 0
    agent_state.import_status = "Starting import..."
    update_ui()

    -- Simulate import progress
    local progress_timer = 0
    local function simulate_import()
        if agent_state.import_progress < 100 then
            agent_state.import_progress = agent_state.import_progress + 10
            agent_state.import_status = string.format("Importing... %d%%", agent_state.import_progress)
            update_ui()
        else
            agent_state.current_state = WORKFLOW_STATES.VIEW_GENERATION
            agent_state.status_message = get_status_for_state()
            update_ui()

            -- Ask agent to generate views
            send_to_agent("Data import complete. Please generate an overview interface for the imported data.")
        end
    end

    -- This is a simplified version - in reality we'd use a timer or coroutine
    for i = 1, 10 do
        simulate_import()
    end
end

local function on_reset_session(payload)
    print("Resetting session")

    -- Clear all state
    agent_state.current_state = WORKFLOW_STATES.WELCOME
    agent_state.session_id = nil
    agent_state.ingested_files = {}
    agent_state.file_count = 0
    agent_state.conversation_history = {}
    agent_state.current_response = ""
    agent_state.comprehension_doc = ""
    agent_state.proposed_schema = false
    agent_state.schema_json = ""
    agent_state.generated_scripts = {}
    agent_state.understanding_validated = false
    agent_state.schema_approved = false
    agent_state.status_message = get_status_for_state()
    agent_state.can_proceed = false
    agent_state.show_feedback_input = false

    update_ui()
end

-- Lifecycle functions

function startup()
    print("Manufold Agent starting (thread_id: " .. thread_id .. ")")

    -- Initialize UI
    update_ui()

    -- Register event handlers
    event.register_global("file_drop", on_files_dropped)
    event.register("start_exploration", on_start_exploration)
    event.register("send_message", on_send_message)
    event.register("submit_feedback", on_submit_feedback)
    event.register("approve_understanding", on_approve_understanding)
    event.register("approve_schema", on_approve_schema)
    event.register("start_import", on_start_import)
    event.register("reset_session", on_reset_session)

    -- Load UI
    ui.load_document("ui/manufold.rml", true, "manufold")

    print("Manufold Agent ready")
end

function update(dt)
    -- Event-driven, no per-frame updates needed
end

function shutdown()
    print("Manufold Agent shutting down")
end
