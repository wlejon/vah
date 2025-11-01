-- File Indexer
-- Project-oriented filesystem indexer for text files

local database = nil
local current_run_id = nil
local indexing_in_progress = false

-- Configuration: File type whitelist
local INDEXED_EXTENSIONS = {
    -- Code files
    [".cpp"] = true, [".h"] = true, [".hpp"] = true, [".c"] = true, [".cc"] = true, [".cxx"] = true,
    [".lua"] = true, [".py"] = true, [".js"] = true, [".ts"] = true, [".tsx"] = true, [".jsx"] = true,
    [".rs"] = true, [".go"] = true, [".java"] = true, [".cs"] = true, [".php"] = true, [".rb"] = true,
    -- Data files
    [".json"] = true, [".xml"] = true, [".yaml"] = true, [".yml"] = true,
    [".toml"] = true, [".ini"] = true, [".sql"] = true, [".conf"] = true, [".config"] = true,
    -- Markup files
    [".html"] = true, [".css"] = true, [".scss"] = true, [".sass"] = true, [".less"] = true,
    [".rml"] = true, [".rcss"] = true,
    -- Script files
    [".sh"] = true, [".bat"] = true, [".ps1"] = true, [".cmd"] = true,
    -- Documentation
    [".md"] = true, [".txt"] = true, [".rst"] = true
}

-- Configuration: Directories to skip
local SKIP_DIRECTORIES = {
    [".git"] = true,
    [".svn"] = true,
    [".hg"] = true,
    ["node_modules"] = true,
    ["build"] = true,
    ["target"] = true,
    ["bin"] = true,
    ["obj"] = true,
    [".vs"] = true,
    ["Debug"] = true,
    ["Release"] = true,
    ["__pycache__"] = true,
    [".cache"] = true,
    ["dist"] = true,
    ["out"] = true,
    [".idea"] = true,
    ["venv"] = true,
    [".venv"] = true,
    ["env"] = true,
    [".env"] = true
}

-- Data models
local indexer_data = {
    status = "Ready",
    files_indexed = 0,
    files_skipped = 0,
    total_size = 0,
    current_file = "",
    is_indexing = false
}

local file_list_data = {
    files = {}
}

local stats_data = {
    total_files = 0,
    total_size = 0,
    file_types = {}
}

local analyzer_status = {
    status = "Idle",
    files_total = 0,
    files_analyzed = 0,
    syntax_errors = 0,
    current_file = "",
    is_analyzing = false
}

-- Utility: Format size
function format_size(size)
    if size < 1024 then
        return string.format("%d B", size)
    elseif size < 1024 * 1024 then
        return string.format("%.1f KB", size / 1024)
    elseif size < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", size / (1024 * 1024))
    else
        return string.format("%.1f GB", size / (1024 * 1024 * 1024))
    end
end

-- Utility: Simple hash function for content
function simple_hash(content)
    local hash = 0
    for i = 1, #content do
        hash = (hash * 31 + string.byte(content, i)) % 2147483647
    end
    return tostring(hash)
end

-- Utility: Check if file should be indexed
function should_index_file(path, file_name)
    -- Skip hidden files (starting with .)
    if file_name:sub(1, 1) == "." then
        return false
    end

    -- Check extension
    local ext = path:match("%.([^%.]+)$")
    if ext then
        ext = "." .. ext:lower()
        return INDEXED_EXTENSIONS[ext] == true
    end

    return false
end

-- Utility: Check if path contains a skipped directory
function path_contains_skip_directory(path)
    -- Split path into components and check each
    for dir_name in path:gmatch("[^/\\]+") do
        -- Skip hidden directories (starting with .)
        if dir_name:sub(1, 1) == "." then
            return true
        end

        if SKIP_DIRECTORIES[dir_name] == true then
            return true
        end
    end

    return false
end

-- Initialize database schema if needed
function initialize_database(db)
    -- Check if tables exist
    local check_query = [[
        SELECT name FROM sqlite_master
        WHERE type='table' AND name='index_runs'
    ]]

    local result, error = db:query(check_query)
    if error ~= "" then
        print("ERROR: Failed to check database: " .. error)
        return false
    end

    -- If tables don't exist, create them
    if not result or #result == 0 then
        print("Initializing file index database schema...")

        -- Read schema file
        local schema_sql, read_error = fs.read_file("data/file_index_schema.sql")
        if read_error ~= "" then
            print("ERROR: Failed to read schema file: " .. read_error)
            return false
        end

        -- Execute schema (multi-statement SQL)
        local success, exec_error = db:execute_file(schema_sql)
        if not success then
            print("ERROR: Failed to execute schema: " .. exec_error)
            return false
        end

        print("Database schema created successfully")
    end

    return true
end

-- Create index run record
function start_index_run(root_path)
    local query = [[
        INSERT INTO index_runs (root_path, started_at, status)
        VALUES (?, datetime('now'), 'running')
    ]]

    local success, error = database:execute(query, root_path)
    if not success then
        print("ERROR: Failed to create index run: " .. error)
        return nil
    end

    -- Get the last inserted ID
    local result, query_error = database:query("SELECT last_insert_rowid() as id")
    if query_error ~= "" or not result or #result == 0 then
        print("ERROR: Failed to get run ID: " .. query_error)
        return nil
    end

    return result[1].id
end

-- Complete index run
function complete_index_run(run_id, files_indexed, files_skipped, total_size, status)
    local query = [[
        UPDATE index_runs
        SET completed_at = datetime('now'),
            files_indexed = ?,
            files_skipped = ?,
            total_size = ?,
            status = ?
        WHERE id = ?
    ]]

    database:execute(query, files_indexed, files_skipped, total_size, status, run_id)
end

-- Index a single file
function index_file(file_path, root_path)
    local stat, stat_error = fs.stat(file_path)
    if stat_error ~= "" then
        return false, "Failed to stat file: " .. stat_error
    end

    -- Read file content
    local content, read_error = fs.read_file(file_path)
    if read_error ~= "" then
        return false, "Failed to read file: " .. read_error
    end

    -- Calculate relative path
    local relative_path = file_path:sub(#root_path + 2)  -- +2 to skip separator

    -- Get file info
    local file_name = fs.basename(file_path)
    local file_ext = fs.extension(file_path):lower()
    local file_size = stat.size
    local modified_time = stat.modified_time
    local content_hash = simple_hash(content)

    -- Count lines
    local line_count = 1
    for _ in content:gmatch("\n") do
        line_count = line_count + 1
    end

    -- Insert or update file record
    local file_query = [[
        INSERT OR REPLACE INTO indexed_files
        (path, relative_path, file_name, file_extension, file_size, modified_time, content_hash, last_run_id, indexed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ]]

    local success, error = database:execute(
        file_query,
        file_path, relative_path, file_name, file_ext,
        file_size, modified_time, content_hash, current_run_id
    )

    if not success then
        return false, "Failed to insert file: " .. error
    end

    -- Get file ID
    local result, query_error = database:query("SELECT id FROM indexed_files WHERE path = ?", file_path)
    if query_error ~= "" or not result or #result == 0 then
        return false, "Failed to get file ID"
    end
    local file_id = result[1].id

    -- Insert file content
    local content_query = [[
        INSERT OR REPLACE INTO file_content
        (file_id, content, line_count, char_count)
        VALUES (?, ?, ?, ?)
    ]]

    success, error = database:execute(content_query, file_id, content, line_count, #content)
    if not success then
        return false, "Failed to insert content: " .. error
    end

    return true, ""
end

-- Main indexing function
function start_indexing()
    if indexing_in_progress then
        print("Indexing already in progress")
        return
    end

    indexing_in_progress = true

    -- Update UI
    indexer_data.is_indexing = true
    indexer_data.status = "Starting indexing..."
    indexer_data.files_indexed = 0
    indexer_data.files_skipped = 0
    indexer_data.total_size = 0
    indexer_data.current_file = ""
    datamodel.bind_table("indexer_status", {indexer_data})

    -- Get root path
    local root_path = fs.get_cwd()
    print("Starting indexing from: " .. root_path)

    -- Open database
    database, error = db.open("data/file_index.db")
    if error ~= "" then
        print("ERROR: Failed to open database: " .. error)
        indexer_data.status = "Error: Failed to open database"
        indexer_data.is_indexing = false
        datamodel.bind_table("indexer_status", {indexer_data})
        indexing_in_progress = false
        return
    end

    -- Initialize database schema if needed
    if not initialize_database(database) then
        indexer_data.status = "Error: Failed to initialize database"
        indexer_data.is_indexing = false
        datamodel.bind_table("indexer_status", {indexer_data})
        database:close()
        indexing_in_progress = false
        return
    end

    -- Start run
    current_run_id = start_index_run(root_path)
    if not current_run_id then
        indexer_data.status = "Error: Failed to create index run"
        indexer_data.is_indexing = false
        datamodel.bind_table("indexer_status", {indexer_data})
        database:close()
        indexing_in_progress = false
        return
    end

    indexer_data.status = "Indexing files..."
    datamodel.bind_table("indexer_status", {indexer_data})

    -- Walk filesystem
    local files_indexed = 0
    local files_skipped = 0
    local total_size = 0

    local walk_success, walk_error = fs.walk(root_path, function(path, is_dir, size)
        -- Skip directories in callback - we just ignore them
        if is_dir then
            return true  -- Always continue walking
        end

        -- Check if this file's path contains any skipped directories
        if path_contains_skip_directory(path) then
            files_skipped = files_skipped + 1
            return true
        end

        -- Process file
        local file_name = fs.basename(path)

        if should_index_file(path, file_name) then
            indexer_data.current_file = path
            datamodel.bind_table("indexer_status", {indexer_data})

            local success, error = index_file(path, root_path)
            if success then
                files_indexed = files_indexed + 1
                total_size = total_size + size
                indexer_data.files_indexed = files_indexed
                indexer_data.total_size = total_size

                -- Update UI every 10 files
                if files_indexed % 10 == 0 then
                    datamodel.bind_table("indexer_status", {indexer_data})
                end
            else
                print("Warning: Failed to index " .. path .. ": " .. error)
                files_skipped = files_skipped + 1
                indexer_data.files_skipped = files_skipped
            end
        else
            files_skipped = files_skipped + 1
        end

        return true
    end)

    -- Complete run
    local final_status = walk_success and "completed" or "failed"
    complete_index_run(current_run_id, files_indexed, files_skipped, total_size, final_status)

    -- Update UI
    indexer_data.status = "Indexing complete: " .. files_indexed .. " files indexed"
    indexer_data.current_file = ""
    datamodel.bind_table("indexer_status", {indexer_data})

    print("Indexing complete: " .. files_indexed .. " files indexed, " .. files_skipped .. " files skipped")
    print("Total size: " .. format_size(total_size))

    -- Refresh stats and file list
    refresh_stats()
    refresh_file_list()

    indexer_data.is_indexing = false
    datamodel.bind_table("indexer_status", {indexer_data})

    -- Trigger file analyzers if indexing succeeded
    if walk_success then
        print("Triggering file analyzers...")
        event.trigger_global("file_analysis_needed", {
            run_id = current_run_id
        })
    end

    database:close()
    database = nil
    indexing_in_progress = false
end

-- Refresh statistics
function refresh_stats()
    local db, error = db.open("data/file_index.db")
    if error ~= "" then
        print("ERROR: Failed to open database: " .. error)
        return
    end

    -- Get total stats
    local total_query = [[
        SELECT COUNT(*) as total_files, SUM(file_size) as total_size
        FROM indexed_files
    ]]

    local result, query_error = db:query(total_query)
    if query_error == "" and result and #result > 0 then
        stats_data.total_files = result[1].total_files or 0
        stats_data.total_size = result[1].total_size or 0
    end

    -- Get file type breakdown
    local type_query = [[
        SELECT * FROM file_type_breakdown
        LIMIT 20
    ]]

    result, query_error = db:query(type_query)
    if query_error == "" and result then
        stats_data.file_types = {}
        for _, row in ipairs(result) do
            table.insert(stats_data.file_types, {
                extension = row.extension,
                count = row.count,
                size = format_size(row.total_size)
            })
        end
    end

    datamodel.bind_table("stats", {stats_data})
    datamodel.bind_table("file_types", stats_data.file_types)

    db:close()
end

-- Refresh file list
function refresh_file_list()
    local db, error = db.open("data/file_index.db")
    if error ~= "" then
        print("ERROR: Failed to open database: " .. error)
        return
    end

    -- Get recent files with line counts and analysis data
    local query = [[
        SELECT
            f.id,
            f.path,
            f.relative_path,
            f.file_name,
            f.file_extension,
            f.file_size,
            f.modified_time,
            c.line_count,
            syntax.analysis_data as syntax_data,
            quality.analysis_data as quality_data
        FROM indexed_files f
        LEFT JOIN file_content c ON f.id = c.file_id
        LEFT JOIN file_analysis syntax ON f.id = syntax.file_id AND syntax.analysis_type = 'lua_syntax'
        LEFT JOIN file_analysis quality ON f.id = quality.file_id AND quality.analysis_type = 'lua_quality'
        ORDER BY f.modified_time DESC
        LIMIT 100
    ]]

    local result, query_error = db:query(query)
    if query_error == "" and result then
        file_list_data.files = {}
        for i, row in ipairs(result) do
            -- Convert modified_time to readable date
            local date_str = "Unknown"
            if row.modified_time and row.modified_time > 0 then
                local timestamp = math.floor(row.modified_time)
                if timestamp > 946684800 and timestamp < 2147483647 then  -- Between 2000 and 2038
                    date_str = os.date("%Y-%m-%d %H:%M", timestamp)
                end
            end

            local file_entry = {
                id = row.id,
                path = row.path,
                relative_path = row.relative_path,
                file_name = row.file_name,
                extension = row.file_extension or "",
                size = format_size(row.file_size),
                modified = date_str,
                lines = row.line_count or 0,
                has_analysis = false,
                syntax_error = false,
                quality_grade = ""
            }

            -- Parse syntax analysis
            if row.syntax_data then
                local success, syntax_info = pcall(json.decode, row.syntax_data)
                if success and syntax_info.has_errors then
                    file_entry.syntax_error = true
                end
            end

            -- Parse quality analysis
            if row.quality_data then
                local success, quality_info = pcall(json.decode, row.quality_data)
                if success and quality_info.overall_grade then
                    file_entry.has_analysis = true
                    file_entry.quality_grade = quality_info.overall_grade
                    file_entry.grade_class = "grade-" .. quality_info.overall_grade
                end
            end

            table.insert(file_list_data.files, file_entry)
        end
    end

    datamodel.bind_table("indexed_files", file_list_data.files)

    db:close()
end

-- Load detailed file analysis
function load_file_analysis(file_id)
    local db, error = db.open("data/file_index.db")
    if error ~= "" then
        print("ERROR: Failed to open database: " .. error)
        return
    end

    -- Get file with analysis data
    local query = [[
        SELECT
            f.id,
            f.path,
            f.relative_path,
            f.file_name,
            f.file_extension,
            f.file_size,
            f.modified_time,
            c.line_count,
            syntax.analysis_data as syntax_data,
            quality.analysis_data as quality_data
        FROM indexed_files f
        LEFT JOIN file_content c ON f.id = c.file_id
        LEFT JOIN file_analysis syntax ON f.id = syntax.file_id AND syntax.analysis_type = 'lua_syntax'
        LEFT JOIN file_analysis quality ON f.id = quality.file_id AND quality.analysis_type = 'lua_quality'
        WHERE f.id = ?
    ]]

    local result, query_error = db:query(query, file_id)
    if query_error ~= "" or not result or #result == 0 then
        print("ERROR: Failed to load file analysis: " .. query_error)
        db:close()
        return
    end

    local row = result[1]

    -- Convert modified_time to readable date
    local date_str = "Unknown"
    if row.modified_time and row.modified_time > 0 then
        local timestamp = math.floor(row.modified_time)
        if timestamp > 946684800 and timestamp < 2147483647 then
            date_str = os.date("%Y-%m-%d %H:%M", timestamp)
        end
    end

    local file_detail = {
        id = row.id,
        file_name = row.file_name,
        relative_path = row.relative_path,
        size = format_size(row.file_size),
        lines = row.line_count or 0,
        modified = date_str,
        has_syntax_analysis = false,
        syntax_has_errors = false,
        syntax_error_message = "",
        syntax_error_line = 0,
        has_quality_analysis = false,
        quality_grade = "",
        grade_class = "",
        quality_summary = "",
        maintainability_score = 0,
        readability_score = 0,
        complexity_score = 0,
        best_practices_score = 0,
        has_code_smells = false,
        has_recommendations = false
    }

    -- Parse syntax analysis
    if row.syntax_data then
        local success, syntax_info = pcall(json.decode, row.syntax_data)
        if success then
            file_detail.has_syntax_analysis = true
            file_detail.syntax_has_errors = syntax_info.has_errors or false
            file_detail.syntax_error_message = syntax_info.error_message or ""
            file_detail.syntax_error_line = syntax_info.error_line or 0
        end
    end

    -- Parse quality analysis
    local code_smells_list = {}
    local recommendations_list = {}

    if row.quality_data then
        local success, quality_info = pcall(json.decode, row.quality_data)
        if success then
            file_detail.has_quality_analysis = true
            file_detail.quality_grade = quality_info.overall_grade or ""
            file_detail.grade_class = "grade-" .. (quality_info.overall_grade or "")
            file_detail.quality_summary = quality_info.summary or ""
            file_detail.maintainability_score = quality_info.maintainability_score or 0
            file_detail.readability_score = quality_info.readability_score or 0
            file_detail.complexity_score = quality_info.complexity_score or 0
            file_detail.best_practices_score = quality_info.best_practices_score or 0

            -- Convert arrays to tables for databinding
            if quality_info.code_smells and #quality_info.code_smells > 0 then
                file_detail.has_code_smells = true
                for _, smell in ipairs(quality_info.code_smells) do
                    table.insert(code_smells_list, {text = smell})
                end
            end

            if quality_info.recommendations and #quality_info.recommendations > 0 then
                file_detail.has_recommendations = true
                for _, rec in ipairs(quality_info.recommendations) do
                    table.insert(recommendations_list, {text = rec})
                end
            end
        end
    end

    -- Bind data
    datamodel.bind_table("selected_file", {file_detail})
    datamodel.bind_table("code_smells", code_smells_list)
    datamodel.bind_table("recommendations", recommendations_list)

    db:close()
end

function startup()
    print("File indexer started (thread_id: " .. thread_id .. ")")

    -- Register event handlers
    event.register("start_indexing", function(payload)
        start_indexing()
    end)

    event.register("refresh_stats", function(payload)
        refresh_stats()
        refresh_file_list()
    end)

    event.register("view_file_analysis", function(payload)
        print("Loading analysis for file ID: " .. payload.file_id)
        load_file_analysis(payload.file_id)
    end)

    event.register("close_detail_panel", function(payload)
        datamodel.bind_table("selected_file", {})
        datamodel.bind_table("code_smells", {})
        datamodel.bind_table("recommendations", {})
    end)

    -- Register global event for analyzer status updates
    event.register_global("lua_analyzer_status_update", function(payload)
        analyzer_status.status = payload.status or analyzer_status.status
        analyzer_status.files_total = payload.files_total or analyzer_status.files_total
        analyzer_status.files_analyzed = payload.files_analyzed or analyzer_status.files_analyzed
        analyzer_status.syntax_errors = payload.syntax_errors or analyzer_status.syntax_errors
        analyzer_status.current_file = payload.current_file or analyzer_status.current_file
        analyzer_status.is_analyzing = payload.is_analyzing or false
        datamodel.bind_table("lua_analyzer_status", {analyzer_status})
    end)

    -- Register global event to refresh when analysis completes
    event.register_global("lua_analysis_complete", function(payload)
        print("Lua analysis complete, refreshing file list...")
        refresh_file_list()
    end)

    -- Initialize data models
    datamodel.bind_table("indexer_status", {indexer_data})
    datamodel.bind_table("stats", {stats_data})
    datamodel.bind_table("file_types", stats_data.file_types)
    datamodel.bind_table("indexed_files", file_list_data.files)
    datamodel.bind_table("lua_analyzer_status", {analyzer_status})
    datamodel.bind_table("selected_file", {})  -- Initialize empty, populated on click
    datamodel.bind_table("code_smells", {})
    datamodel.bind_table("recommendations", {})

    -- Load initial stats if database exists
    if fs.exists("data/file_index.db") then
        refresh_stats()
        refresh_file_list()
    end

    -- Load UI
    ui.load_document("ui/apps/file_indexer/file_indexer.rml", true, "file_indexer")
end

function update(dt)
    -- Nothing to do - indexing is event-driven
end

function shutdown()
    if database then
        database:close()
    end
    print("File indexer shutting down")
end
