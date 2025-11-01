-- Lua File Analyzer
-- Background thread for analyzing Lua files with syntax checking and LLM quality analysis
-- Runs separately from main indexer to avoid blocking

local LMStudioClient = require("lib.adapters.lm_studio_client")

-- State
local lm_client = nil
local lm_available = false
local analyzing = false
local current_run_id = nil

local analyzer_state = {
    status = "Idle",
    files_total = 0,
    files_analyzed = 0,
    files_failed = 0,
    syntax_errors = 0,
    current_file = "",
    is_analyzing = false
}

-- Check Lua file syntax
local function check_lua_syntax(content, file_path)
    local result = {
        has_errors = false,
        error_message = nil,
        error_line = nil
    }

    -- Use Lua's load() to check syntax without executing
    local func, err = load(content, "@" .. file_path)

    if not func then
        result.has_errors = true
        result.error_message = err

        -- Try to extract line number from error message
        local line_num = err:match(":(%d+):")
        if line_num then
            result.error_line = tonumber(line_num)
        end
    end

    return result
end

-- Analyze Lua file quality using LLM
local function analyze_lua_quality(content, file_path, file_name)
    if not lm_available then
        return nil, "LM Studio not available"
    end

    -- Build analysis prompt
    local prompt = string.format([[Analyze this Lua file and provide a code quality assessment.

File: %s
Lines of code: %d

```lua
%s
```

Provide your analysis as a JSON object with this exact structure:
{
  "overall_grade": "A-F letter grade",
  "maintainability_score": 1-10,
  "readability_score": 1-10,
  "complexity_score": 1-10,
  "best_practices_score": 1-10,
  "code_smells": ["list", "of", "issues"],
  "recommendations": ["list", "of", "suggestions"],
  "summary": "brief 1-2 sentence summary"
}

Be concise and specific. Focus on real issues, not theoretical ones.]],
        file_name,
        select(2, content:gsub('\n', '\n')) + 1,
        content
    )

    -- Call LLM
    local messages = {
        {role = "system", content = "You are a code quality analyzer. Respond only with valid JSON."},
        {role = "user", content = prompt}
    }

    local response, error = lm_client:chat(messages, {
        temperature = 0.3,
        max_tokens = 1000
    })

    if error then
        return nil, error
    end

    if not response or not response.choices or #response.choices == 0 then
        return nil, "Empty response from LLM"
    end

    local content_text = response.choices[1].message.content

    -- Try to extract JSON from response (in case there's extra text)
    local json_start = content_text:find("{")
    local json_end = content_text:find("}[^}]*$")

    if json_start and json_end then
        content_text = content_text:sub(json_start, json_end)
    end

    -- Parse JSON response
    local success, quality_data = pcall(json.decode, content_text)
    if not success then
        return nil, "Failed to parse LLM response as JSON: " .. tostring(quality_data)
    end

    return quality_data, nil
end

-- Store analysis results in database
local function store_analysis(database, file_id, analysis_type, analysis_data)
    local json_data = json.encode(analysis_data)

    local query = [[
        INSERT OR REPLACE INTO file_analysis
        (file_id, analysis_type, analysis_data, analyzed_at)
        VALUES (?, ?, ?, datetime('now'))
    ]]

    local success, error = database:execute(query, file_id, analysis_type, json_data)
    return success, error
end

-- Update UI state (sends event to file_indexer)
local function update_ui()
    datamodel.bind_table("lua_analyzer_status", {analyzer_state})

    -- Also broadcast status to other threads (like file_indexer)
    event.trigger_global("lua_analyzer_status_update", {
        status = analyzer_state.status,
        files_total = analyzer_state.files_total,
        files_analyzed = analyzer_state.files_analyzed,
        syntax_errors = analyzer_state.syntax_errors,
        current_file = analyzer_state.current_file,
        is_analyzing = analyzer_state.is_analyzing
    })
end

-- Main analysis function - processes one file at a time
local function analyze_files(run_id)
    if analyzing then
        print("Lua analyzer already running")
        return
    end

    analyzing = true
    current_run_id = run_id

    analyzer_state.status = "Starting analysis..."
    analyzer_state.is_analyzing = true
    analyzer_state.files_analyzed = 0
    analyzer_state.files_failed = 0
    analyzer_state.syntax_errors = 0
    update_ui()

    -- Open database
    local database, error = db.open("data/file_index.db")
    if error ~= "" then
        print("ERROR: Failed to open database: " .. error)
        analyzer_state.status = "Error: Failed to open database"
        analyzer_state.is_analyzing = false
        update_ui()
        analyzing = false
        return
    end

    -- Query all Lua files from the run
    local query = [[
        SELECT f.id, f.path, f.file_name, c.content
        FROM indexed_files f
        JOIN file_content c ON f.id = c.file_id
        WHERE f.file_extension = '.lua' AND f.last_run_id = ?
    ]]

    local result, query_error = database:query(query, run_id)
    if query_error ~= "" then
        print("ERROR: Failed to query Lua files: " .. query_error)
        analyzer_state.status = "Error: Failed to query files"
        analyzer_state.is_analyzing = false
        update_ui()
        database:close()
        analyzing = false
        return
    end

    if not result or #result == 0 then
        print("No Lua files to analyze")
        analyzer_state.status = "No Lua files found"
        analyzer_state.is_analyzing = false
        update_ui()
        database:close()
        analyzing = false
        return
    end

    analyzer_state.files_total = #result
    print("Found " .. #result .. " Lua files to analyze")

    -- Process each file
    for i, row in ipairs(result) do
        analyzer_state.current_file = row.file_name
        analyzer_state.status = "Analyzing " .. i .. "/" .. #result
        update_ui()

        print("Analyzing " .. i .. "/" .. #result .. ": " .. row.file_name)

        -- 1. Syntax check (always run, fast)
        local syntax_result = check_lua_syntax(row.content, row.path)
        local success, store_error = store_analysis(database, row.id, "lua_syntax", syntax_result)

        if not success then
            print("Warning: Failed to store syntax analysis: " .. store_error)
            analyzer_state.files_failed = analyzer_state.files_failed + 1
        else
            if syntax_result.has_errors then
                analyzer_state.syntax_errors = analyzer_state.syntax_errors + 1
                print("  Syntax error: " .. (syntax_result.error_message or "unknown"))
            end
        end

        -- 2. LLM quality analysis (only if available, slow)
        if lm_available then
            local quality_data, quality_error = analyze_lua_quality(row.content, row.path, row.file_name)

            if quality_data then
                success, store_error = store_analysis(database, row.id, "lua_quality", quality_data)
                if not success then
                    print("Warning: Failed to store quality analysis: " .. store_error)
                    analyzer_state.files_failed = analyzer_state.files_failed + 1
                else
                    print("  Quality grade: " .. (quality_data.overall_grade or "N/A"))
                end
            else
                print("  Quality analysis skipped: " .. quality_error)
            end
        end

        analyzer_state.files_analyzed = analyzer_state.files_analyzed + 1
        update_ui()
    end

    database:close()

    -- Complete
    analyzer_state.status = "Complete: " .. analyzer_state.files_analyzed .. " files analyzed"
    analyzer_state.current_file = ""
    analyzer_state.is_analyzing = false
    update_ui()

    print("Lua file analysis complete:")
    print("  Files analyzed: " .. analyzer_state.files_analyzed .. "/" .. analyzer_state.files_total)
    print("  Syntax errors: " .. analyzer_state.syntax_errors)
    print("  Failed: " .. analyzer_state.files_failed)

    -- Notify other threads that analysis is complete
    event.trigger_global("lua_analysis_complete", {
        files_analyzed = analyzer_state.files_analyzed,
        syntax_errors = analyzer_state.syntax_errors
    })

    analyzing = false
end

function startup()
    print("Lua analyzer started (thread_id: " .. thread_id .. ")")

    -- Initialize LM Studio client
    lm_client = LMStudioClient.new("http://127.0.0.1:1234", "openai/gpt-oss-20b")
    local is_healthy, health_error = lm_client:health_check()
    if is_healthy then
        print("LM Studio is available for code quality analysis")
        lm_available = true
    else
        print("LM Studio not available - will only run syntax checks: " .. (health_error or "unknown error"))
        lm_available = false
    end

    -- Register for global analysis requests
    event.register_global("file_analysis_needed", function(payload)
        print("Received file_analysis_needed event for run_id: " .. payload.run_id)
        analyze_files(payload.run_id)
    end)

    -- Initialize UI state
    update_ui()

    print("Lua analyzer ready")
end

function update(dt)
    -- Analysis is event-driven, nothing to do here
end

function shutdown()
    print("Lua analyzer shutting down")
end
