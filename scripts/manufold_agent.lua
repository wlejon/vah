-- Manufold Agent System
-- Agent-assisted workflow for transforming unstructured data into structured knowledge environments

local LMStudioClient = require("lm_studio_client")
local HarmonyAdapter = require("harmony_adapter")
local tool_definitions = require("tool_definitions")

-- Create LM Studio client and model adapter
local client = LMStudioClient.new("http://127.0.0.1:1234", "openai/gpt-oss-20b")
local adapter = HarmonyAdapter.new()

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
    has_schema = false,
}

-- System prompt generation using adapter
local function get_system_prompt(workflow_state)
    return adapter:generate_system_prompt(tool_definitions, workflow_state)
end

-- Execute a tool call
local function execute_tool(tool_name, arguments)
    print("Executing tool: " .. tool_name .. " with args: " .. json.encode(arguments))

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

        print("Reading file: " .. path)
        local content, error = fs.read_file(path)
        if error and error ~= "" then
            print("Read error: " .. tostring(error))
            return {success = false, error = error}
        end

        print("Read " .. (content and #content or 0) .. " bytes")
        return {success = true, result = content}

    elseif tool_name == "create_comprehension_doc" then
        agent_state.comprehension_doc = arguments.content or ""
        agent_state.show_feedback_input = true
        agent_state.current_state = WORKFLOW_STATES.VALIDATION
        agent_state.status_message = get_status_for_state()
        update_ui()

        return {success = true, result = "Comprehension document created"}

    elseif tool_name == "propose_schema" then
        if not arguments or not arguments.schema then
            print("ERROR: propose_schema called with null or missing schema")
            return {success = false, error = "Missing schema parameter"}
        end

        agent_state.proposed_schema = arguments.schema
        -- Convert to JSON for display
        agent_state.schema_json = json.encode(arguments.schema, true) or "{}"
        agent_state.current_state = WORKFLOW_STATES.MODEL_DESIGN
        agent_state.status_message = get_status_for_state()
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

-- Parse tool calls using adapter
local function parse_tool_calls(content)
    local tokens = adapter:tokenize(content)
    return adapter:parse_tool_calls(tokens)
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
            local result

            -- Check if there was a parse error
            if call.parse_error then
                result = {
                    success = false,
                    error = "JSON Parse Error: " .. call.parse_error.message .. "\n\nError occurred here:\n" .. call.parse_error.context .. "\n\nPlease fix the JSON syntax and try again."
                }
                print("Tool parse error for " .. call.name .. ": " .. call.parse_error.message)
            else
                result = execute_tool(call.name, call.arguments)
            end

            table.insert(tool_results, {
                tool = call.name,
                result = result
            })

            -- Log result
            if result.success then
                local result_str = type(result.result) == "string" and result.result:sub(1, 100) or json.encode(result.result):sub(1, 100)
                print("Tool result: " .. result_str .. (result_str:len() >= 100 and "..." or ""))
            else
                print("Tool error: " .. (result.error or "Unknown error"))
            end
        end

        -- Format tool results using adapter and send back to agent
        local results_text = adapter:format_tool_results(tool_results)
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
    agent_state.has_schema = agent_state.proposed_schema ~= false

    data.bind("manufold", {agent_state})
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
        local file_size = 0
        if stat_result and stat_result.size then
            file_size = stat_result.size
        end

        table.insert(agent_state.ingested_files, {
            path = path,
            name = fs.basename(path),
            size = file_size,
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

    -- Trigger schema design with minimal message
    -- The system prompt for model_design phase will force the tool call
    send_to_agent("APPROVED")
end

local function on_approve_schema(payload)
    print("Schema approved")

    agent_state.schema_approved = true
    agent_state.current_state = WORKFLOW_STATES.TRANSFORMATION
    agent_state.status_message = get_status_for_state()
    update_ui()

    -- Trigger parser generation with minimal message
    -- The system prompt for transformation phase will force the tool calls
    send_to_agent("APPROVED")
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
