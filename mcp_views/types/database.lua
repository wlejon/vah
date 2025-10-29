-- Database Type Definition
-- Provides views for SQLite databases in the system

return {
    name = "Database",
    plural = "Databases",

    -- Query functions for each view type
    query = {
        -- List all databases
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            local offset = (page - 1) * limit

            -- Find all .db files in data directory
            local data_dir = "data"
            local files, err = fs.list_dir(data_dir)

            if err ~= "" then
                return {
                    items = {},
                    total = 0,
                    page = page,
                    total_pages = 0,
                    limit = limit
                }
            end

            -- Filter for .db files
            local db_files = {}
            for _, entry in ipairs(files) do
                if not entry.is_dir and entry.name:match("%.db$") then
                    local path = data_dir .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)

                    local size = 0
                    local modified = ""
                    if stat_err == "" and stats then
                        size = stats.size or 0
                        modified = stats.modified or ""
                    end

                    table.insert(db_files, {
                        name = entry.name,
                        path = path,
                        size = size,
                        modified = modified
                    })
                end
            end

            -- Sort by name
            table.sort(db_files, function(a, b)
                return a.name < b.name
            end)

            -- Paginate
            local total = #db_files
            local total_pages = math.max(1, math.ceil(total / limit))
            local items = {}

            local start_idx = offset + 1
            local end_idx = math.min(offset + limit, total)

            for i = start_idx, end_idx do
                table.insert(items, db_files[i])
            end

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit
            }
        end,

        -- View database details
        detail = function(context)
            local db_path = context.id

            if not db_path then
                error("Missing database path")
            end

            -- Get file stats
            local stats, err = fs.stat(db_path)
            if err ~= "" then
                error("Database not found: " .. db_path)
            end

            -- Open database and get table list
            local dbh, open_err = db.open(db_path)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Query table list
            local tables = {}
            local query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            local rows, query_err = dbh:query(query)

            if query_err == "" and rows then
                for _, row in ipairs(rows) do
                    table.insert(tables, row.name)
                end
            end

            dbh:close()

            return {
                id = db_path,
                name = db_path:match("([^/\\]+)$") or db_path,
                path = db_path,
                size = stats.size or 0,
                modified = stats.modified or "",
                table_count = #tables,
                tables = tables
            }
        end,

        -- Database summary statistics
        summary = function(context)
            -- Find all .db files
            local data_dir = "data"
            local files, err = fs.list_dir(data_dir)

            if err ~= "" then
                return {
                    total_databases = 0,
                    total_size = 0,
                    total_tables = 0
                }
            end

            local total_databases = 0
            local total_size = 0
            local total_tables = 0

            for _, entry in ipairs(files) do
                if not entry.is_dir and entry.name:match("%.db$") then
                    local path = data_dir .. "/" .. entry.name
                    total_databases = total_databases + 1

                    -- Get size
                    local stats, stat_err = fs.stat(path)
                    if stat_err == "" and stats then
                        total_size = total_size + (stats.size or 0)
                    end

                    -- Count tables
                    local dbh, open_err = db.open(path)
                    if open_err == "" and dbh then
                        local rows, query_err = dbh:query("SELECT COUNT(*) as count FROM sqlite_master WHERE type='table'")
                        if query_err == "" and rows and rows[1] then
                            total_tables = total_tables + (rows[1].count or 0)
                        end
                        dbh:close()
                    end
                end
            end

            return {
                total_databases = total_databases,
                total_size = total_size,
                total_tables = total_tables,
                average_size = total_databases > 0 and (total_size / total_databases) or 0
            }
        end,

        -- Search databases
        search = function(context)
            local search_query = context.query or ""

            if search_query == "" then
                return {
                    query = search_query,
                    items = {},
                    total_matches = 0
                }
            end

            -- Find all .db files
            local data_dir = "data"
            local files, err = fs.list_dir(data_dir)

            if err ~= "" then
                return {
                    query = search_query,
                    items = {},
                    total_matches = 0
                }
            end

            local matches = {}
            local search_lower = search_query:lower()

            -- Search in database names
            for _, entry in ipairs(files) do
                if not entry.is_dir and entry.name:match("%.db$") and entry.name:lower():find(search_lower, 1, true) then
                    local path = data_dir .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)

                    table.insert(matches, {
                        name = entry.name,
                        path = path,
                        size = (stat_err == "" and stats) and stats.size or 0
                    })
                end
            end

            return {
                query = search_query,
                items = matches,
                total_matches = #matches
            }
        end,

        -- Diff view (not supported for databases)
        diff = function(context)
            return {
                id = context.id or "",
                supported = false,
                not_supported = true,
                message = "Diff view is not supported for databases"
            }
        end,

        -- Database-specific status
        status = function(context)
            -- Could check database health, connection status, etc.
            return {
                status = "ready",
                message = "Database system operational"
            }
        end
    },

    -- No action tools yet (read-only)
    tools = {},

    -- No custom templates (use generic ones)
    templates = {}
}
