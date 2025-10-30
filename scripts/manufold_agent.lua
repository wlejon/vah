-- Manufold Agent System
-- Agent-assisted workflow for transforming unstructured data into structured knowledge environments
-- Enhanced with view-oriented tools

local LMStudioClient = require("lm_studio_client")
local HarmonyAdapter = require("harmony_adapter")
local manufold_tools = require("manufold_tools")

-- Import tool modules
local FileInspector = require("file_inspector")
local SchemaExecutor = require("schema_executor")
local DbInspector = require("db_inspector")
local ParserExecutor = require("parser_executor")
local ViewGenerator = require("view_generator")

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
    return adapter:generate_system_prompt(manufold_tools, workflow_state)
end

-- Execute a tool call with view-oriented results
local function execute_tool(tool_name, arguments)
    print("Executing tool: " .. tool_name)
    if arguments then
        print("  Args: " .. json.encode(arguments):sub(1, 200))
    end

    -- File System Tools
    if tool_name == "list_files" then
        local result = FileInspector.list_files(agent_state.ingested_files)
        return {success = true, result = result}

    elseif tool_name == "inspect_file" then
        if not arguments or not arguments.path then
            return {success = false, error = "Missing path parameter"}
        end

        local result = FileInspector.inspect_file(arguments.path, arguments.max_bytes)
        if result.error then
            return {success = false, error = result.error}
        end
        return {success = true, result = result}

    elseif tool_name == "analyze_file_collection" then
        local result = FileInspector.analyze_collection(agent_state.ingested_files)
        return {success = true, result = result}

    -- Schema Tools
    elseif tool_name == "propose_schema" then
        if not arguments or not arguments.schema then
            return {success = false, error = "Missing schema parameter"}
        end

        -- Summarize and validate schema
        local result = SchemaExecutor.summarize_schema(arguments.schema)

        -- Store schema
        agent_state.proposed_schema = arguments.schema
        agent_state.schema_json = json.encode(arguments.schema, true) or "{}"
        agent_state.current_state = WORKFLOW_STATES.MODEL_DESIGN
        agent_state.status_message = get_status_for_state()
        update_ui()

        return {success = true, result = result}

    elseif tool_name == "execute_schema" then
        if not agent_state.proposed_schema then
            return {success = false, error = "No schema has been proposed yet"}
        end

        if not arguments or not arguments.db_path then
            return {success = false, error = "Missing db_path parameter"}
        end

        -- Execute schema
        local result = SchemaExecutor.execute_schema(agent_state.proposed_schema, arguments.db_path)

        -- Update agent state
        if result.ready_for_import then
            agent_state.db_path = arguments.db_path
            agent_state.schema_approved = true
        end

        return {success = true, result = result}

    elseif tool_name == "introspect_database" then
        if not arguments or not arguments.db_path then
            return {success = false, error = "Missing db_path parameter"}
        end

        local include_stats = arguments.include_data_stats
        local result = DbInspector.introspect(arguments.db_path, include_stats)

        if result.error then
            return {success = false, error = result.error}
        end

        return {success = true, result = result}

    -- Parser Tools
    elseif tool_name == "generate_parser" then
        if not arguments or not arguments.file_type or not arguments.script_content or
           not arguments.target_table or not arguments.field_mapping then
            return {success = false, error = "Missing required parameters"}
        end

        -- Generate unique parser ID
        local parser_id = "parser_" .. arguments.file_type .. "_" .. os.time()

        -- Register parser
        local result = ParserExecutor.register_parser(
            parser_id,
            arguments.file_type,
            arguments.script_content,
            arguments.target_table,
            arguments.field_mapping
        )

        -- Store script info
        table.insert(agent_state.generated_scripts, {
            parser_id = parser_id,
            file_type = arguments.file_type,
            script = arguments.script_content,
            target_table = arguments.target_table
        })
        update_ui()

        return {success = true, result = result}

    elseif tool_name == "execute_parser" then
        if not arguments or not arguments.parser_id or not arguments.file_paths or not arguments.db_path then
            return {success = false, error = "Missing required parameters"}
        end

        local dry_run = arguments.dry_run or false

        local result = ParserExecutor.execute_parser(
            arguments.parser_id,
            arguments.file_paths,
            arguments.db_path,
            dry_run
        )

        if result.execution_summary and result.execution_summary.error then
            return {success = false, error = result.execution_summary.error}
        end

        -- Update import progress
        if not dry_run then
            agent_state.import_progress = 100
            agent_state.import_status = string.format(
                "Imported %d rows from %d files",
                result.execution_summary.total_rows_inserted or 0,
                result.execution_summary.files_processed or 0
            )
            update_ui()
        end

        return {success = true, result = result}

    elseif tool_name == "validate_import" then
        if not arguments or not arguments.db_path or not arguments.table_name then
            return {success = false, error = "Missing required parameters"}
        end

        local result = ParserExecutor.validate_import(
            arguments.db_path,
            arguments.table_name,
            arguments.validation_rules
        )

        if result.error then
            return {success = false, error = result.error}
        end

        return {success = true, result = result}

    -- Documentation Tools
    elseif tool_name == "create_comprehension_doc" then
        if not arguments or not arguments.content then
            return {success = false, error = "Missing content parameter"}
        end

        agent_state.comprehension_doc = arguments.content
        agent_state.show_feedback_input = true
        agent_state.current_state = WORKFLOW_STATES.VALIDATION
        agent_state.status_message = get_status_for_state()
        update_ui()

        -- Analyze document
        local word_count = 0
        for _ in arguments.content:gmatch("%S+") do
            word_count = word_count + 1
        end

        local section_count = 0
        for _ in arguments.content:gmatch("\n#") do
            section_count = section_count + 1
        end

        local result = {
            document_summary = {
                section_count = section_count,
                word_count = word_count,
                topics_covered = {"(extracted from document)"}
            },
            ready_for_validation = true
        }

        return {success = true, result = result}

    -- View Generation Tools
    elseif tool_name == "generate_view" then
        if not arguments or not arguments.view_type or not arguments.data_source then
            return {success = false, error = "Missing required parameters"}
        end

        local result = ViewGenerator.generate_view(
            arguments.view_type,
            arguments.data_source,
            arguments.layout_preferences
        )

        if result.error then
            return {success = false, error = result.error}
        end

        -- Save generated files
        for _, file in ipairs(result.generated_files) do
            -- Create directory if needed
            local dir = fs.dirname(file.path)
            if dir and dir ~= "" then
                fs.create_dir(dir)
            end

            -- Write file
            local write_success, write_err = fs.write_file(file.path, file.content)
            if not write_success then
                print("Warning: Failed to write " .. file.path .. ": " .. (write_err or "unknown error"))
            else
                print("Generated: " .. file.path)
            end
        end

        return {success = true, result = result}

    elseif tool_name == "query_data" then
        if not arguments or not arguments.db_path or not arguments.query then
            return {success = false, error = "Missing required parameters"}
        end

        local result = DbInspector.query_data(
            arguments.db_path,
            arguments.query,
            arguments.max_rows
        )

        if result.error then
            return {success = false, error = result.error}
        end

        return {success = true, result = result}

    else
        return {success = false, error = "Unknown tool: " .. tool_name}
    end
end

-- Parse tool calls using adapter
local function parse_tool_calls(content)
    local tokens = adapter:tokenize(content)
    return adapter:parse_tool_calls(tokens)
end

-- Trim conversation history to prevent unbounded memory growth
local function trim_conversation_history()
    local max_messages = 50
    if #agent_state.conversation_history > max_messages then
        print("Trimming conversation history from " .. #agent_state.conversation_history .. " to " .. max_messages .. " messages")
        local recent = {}
        for i = #agent_state.conversation_history - max_messages + 1, #agent_state.conversation_history do
            table.insert(recent, agent_state.conversation_history[i])
        end
        agent_state.conversation_history = recent
    end
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

    -- Trim conversation history to prevent memory growth
    trim_conversation_history()

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

    print("Agent response: " .. content:sub(1, 200) .. (content:len() > 200 and "..." or ""))

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

        -- Define critical tools that should stop execution on failure
        local critical_tools = {
            execute_schema = true,
            execute_parser = true
        }

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
                local result_preview = json.encode(result.result):sub(1, 300)
                print("Tool success: " .. result_preview .. (result_preview:len() >= 300 and "..." or ""))
            else
                print("Tool error: " .. (result.error or "Unknown error"))
            end

            -- Check if this is a critical tool failure
            if not result.success and critical_tools[call.name] then
                print("Critical tool failure - stopping execution")
                -- Add error context to results
                table.insert(tool_results, {
                    tool = "system",
                    result = {
                        success = false,
                        error = "Execution stopped due to critical tool failure in " .. call.name
                    }
                })
                break
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

    datamodel.bind_table("manufold", {agent_state})
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
                -- Determine if binary
                local ext = fs.extension(entry_path)
                local is_binary = ext == ".jpg" or ext == ".png" or ext == ".pdf" or
                                 ext == ".zip" or ext == ".exe" or ext == ".bin"

                table.insert(agent_state.ingested_files, {
                    path = entry_path,
                    name = fs.basename(entry_path),
                    size = size or 0,
                    type = ext or "unknown",
                    mime_type = "text/plain",
                    is_binary = is_binary
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

        local ext = fs.extension(path)
        local is_binary = ext == ".jpg" or ext == ".png" or ext == ".pdf" or
                         ext == ".zip" or ext == ".exe" or ext == ".bin"

        table.insert(agent_state.ingested_files, {
            path = path,
            name = fs.basename(path),
            size = file_size,
            type = ext or "unknown",
            mime_type = "text/plain",
            is_binary = is_binary
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
        "I have ingested %d files. Please use the list_files tool to see the collection, then begin analysis.",
        agent_state.file_count
    )

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

    -- Trigger schema design
    send_to_agent("APPROVED. Please now propose a database schema using the propose_schema tool.")
end

local function on_approve_schema(payload)
    print("Schema approved")

    agent_state.schema_approved = true
    agent_state.current_state = WORKFLOW_STATES.TRANSFORMATION
    agent_state.status_message = get_status_for_state()

    -- Create database path with validation
    agent_state.session_id = "session_" .. os.time()

    -- Ensure data directory exists
    local data_dir = "data"
    local dir_stat, dir_err = fs.stat(data_dir)
    if not dir_stat or not dir_stat.is_dir then
        print("Creating data directory: " .. data_dir)
        local create_success, create_err = fs.create_dir(data_dir)
        if not create_success then
            print("WARNING: Failed to create data directory: " .. (create_err or "unknown error"))
            -- Fallback to current directory
            agent_state.db_path = agent_state.session_id .. ".db"
        else
            agent_state.db_path = data_dir .. "/" .. agent_state.session_id .. ".db"
        end
    else
        agent_state.db_path = data_dir .. "/" .. agent_state.session_id .. ".db"
    end

    print("Database path: " .. agent_state.db_path)

    update_ui()

    -- Trigger schema execution and parser generation
    send_to_agent(string.format(
        "APPROVED. First execute the schema using execute_schema with db_path '%s'. Then generate parser scripts for each file type.",
        agent_state.db_path
    ))
end

local function on_start_import(payload)
    print("Starting import")

    if #agent_state.generated_scripts == 0 then
        print("ERROR: No parser scripts generated")
        return
    end

    if not agent_state.db_path or agent_state.db_path == "" then
        print("ERROR: No database path set")
        return
    end

    -- Group files by type
    local files_by_type = {}
    for _, file in ipairs(agent_state.ingested_files) do
        if not file.is_binary then
            local ext = file.type or "unknown"
            if not files_by_type[ext] then
                files_by_type[ext] = {}
            end
            table.insert(files_by_type[ext], file.path)
        end
    end

    -- Execute each parser
    for _, script_info in ipairs(agent_state.generated_scripts) do
        local file_paths = files_by_type[script_info.file_type] or {}

        if #file_paths > 0 then
            print(string.format("Executing parser for %s files (%d files)", script_info.file_type, #file_paths))

            local execute_msg = string.format(
                "Execute parser '%s' on %d files using execute_parser tool.",
                script_info.parser_id,
                #file_paths
            )
            send_to_agent(execute_msg)
        end
    end

    -- Transition to view generation after import
    agent_state.current_state = WORKFLOW_STATES.VIEW_GENERATION
    agent_state.status_message = get_status_for_state()
    update_ui()
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
    agent_state.db_path = ""
    agent_state.import_progress = 0
    agent_state.import_status = ""

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
    print("Tools loaded: " .. #manufold_tools .. " enhanced tools with view-oriented responses")
end

function update(dt)
    -- Event-driven, no per-frame updates needed
end

function shutdown()
    print("Manufold Agent shutting down")
end
