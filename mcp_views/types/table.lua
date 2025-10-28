-- Table Type Definition
-- Provides views for database tables within SQLite databases

return {
    name = "Table",
    plural = "Tables",

    -- Query functions for each view type
    query = {
        -- List all tables in a database
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10
            local database = context.database

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            if not database then
                error("Missing required context parameter: database")
            end

            local offset = (page - 1) * limit

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Query table list with row counts
            local query = [[
                SELECT name FROM sqlite_master
                WHERE type='table'
                ORDER BY name
            ]]

            local rows, query_err = dbh:query(query)

            if query_err ~= "" then
                dbh:close()
                error("Failed to query tables: " .. query_err)
            end

            -- Get row count and column count for each table
            local tables = {}
            if rows then
                for _, row in ipairs(rows) do
                    local table_name = row.name

                    -- Get row count
                    local count_query = "SELECT COUNT(*) as count FROM " .. table_name
                    local count_rows, count_err = dbh:query(count_query)
                    local row_count = 0
                    if count_err == "" and count_rows and count_rows[1] then
                        row_count = count_rows[1].count or 0
                    end

                    -- Get column count
                    local info_query = "PRAGMA table_info(" .. table_name .. ")"
                    local info_rows, info_err = dbh:query(info_query)
                    local column_count = 0
                    if info_err == "" and info_rows then
                        column_count = #info_rows
                    end

                    table.insert(tables, {
                        name = table_name,
                        database = database,
                        row_count = row_count,
                        column_count = column_count
                    })
                end
            end

            dbh:close()

            -- Paginate
            local total = #tables
            local total_pages = math.max(1, math.ceil(total / limit))
            local items = {}

            local start_idx = offset + 1
            local end_idx = math.min(offset + limit, total)

            for i = start_idx, end_idx do
                table.insert(items, tables[i])
            end

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit,
                database = database
            }
        end,

        -- View table details (schema, indexes, etc.)
        detail = function(context)
            local table_name = context.id
            local database = context.database

            if not table_name then
                error("Missing table name")
            end

            if not database then
                error("Missing required context parameter: database")
            end

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Get table info (columns)
            local info_query = "PRAGMA table_info(" .. table_name .. ")"
            local info_rows, info_err = dbh:query(info_query)

            if info_err ~= "" then
                dbh:close()
                error("Failed to get table info: " .. info_err)
            end

            local columns = {}
            if info_rows then
                for _, col in ipairs(info_rows) do
                    table.insert(columns, {
                        name = col.name,
                        type = col.type,
                        notnull = col.notnull == 1,
                        default_value = col.dflt_value,
                        pk = col.pk > 0
                    })
                end
            end

            -- Get row count
            local count_query = "SELECT COUNT(*) as count FROM " .. table_name
            local count_rows, count_err = dbh:query(count_query)
            local row_count = 0
            if count_err == "" and count_rows and count_rows[1] then
                row_count = count_rows[1].count or 0
            end

            -- Get indexes
            local index_query = "PRAGMA index_list(" .. table_name .. ")"
            local index_rows, index_err = dbh:query(index_query)

            local indexes = {}
            if index_err == "" and index_rows then
                for _, idx in ipairs(index_rows) do
                    table.insert(indexes, {
                        name = idx.name,
                        unique = idx.unique == 1
                    })
                end
            end

            dbh:close()

            return {
                id = table_name,
                name = table_name,
                database = database,
                row_count = row_count,
                column_count = #columns,
                columns = columns,
                indexes = indexes,
                index_count = #indexes
            }
        end,

        -- Table summary statistics
        summary = function(context)
            local database = context.database

            if not database then
                error("Missing required context parameter: database")
            end

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Get all tables
            local query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            local rows, query_err = dbh:query(query)

            if query_err ~= "" then
                dbh:close()
                error("Failed to query tables: " .. query_err)
            end

            local total_tables = 0
            local total_rows = 0
            local total_columns = 0

            if rows then
                total_tables = #rows

                for _, row in ipairs(rows) do
                    local table_name = row.name

                    -- Get row count
                    local count_query = "SELECT COUNT(*) as count FROM " .. table_name
                    local count_rows, count_err = dbh:query(count_query)
                    if count_err == "" and count_rows and count_rows[1] then
                        total_rows = total_rows + (count_rows[1].count or 0)
                    end

                    -- Get column count
                    local info_query = "PRAGMA table_info(" .. table_name .. ")"
                    local info_rows, info_err = dbh:query(info_query)
                    if info_err == "" and info_rows then
                        total_columns = total_columns + #info_rows
                    end
                end
            end

            dbh:close()

            return {
                database = database,
                total_tables = total_tables,
                total_rows = total_rows,
                total_columns = total_columns,
                average_rows_per_table = total_tables > 0 and (total_rows / total_tables) or 0,
                average_columns_per_table = total_tables > 0 and (total_columns / total_tables) or 0
            }
        end,

        -- Search tables by name
        search = function(context)
            local search_query = context.query or ""
            local database = context.database

            if not database then
                error("Missing required context parameter: database")
            end

            if search_query == "" then
                return {
                    query = search_query,
                    items = {},
                    total_matches = 0
                }
            end

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Get all tables
            local query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            local rows, query_err = dbh:query(query)

            if query_err ~= "" then
                dbh:close()
                error("Failed to query tables: " .. query_err)
            end

            local matches = {}
            local search_lower = search_query:lower()

            if rows then
                for _, row in ipairs(rows) do
                    local table_name = row.name

                    if table_name:lower():find(search_lower, 1, true) then
                        -- Get row count
                        local count_query = "SELECT COUNT(*) as count FROM " .. table_name
                        local count_rows, count_err = dbh:query(count_query)
                        local row_count = 0
                        if count_err == "" and count_rows and count_rows[1] then
                            row_count = count_rows[1].count or 0
                        end

                        table.insert(matches, {
                            name = table_name,
                            database = database,
                            row_count = row_count
                        })
                    end
                end
            end

            dbh:close()

            return {
                query = search_query,
                items = matches,
                total_matches = #matches,
                database = database
            }
        end,

        -- Diff view (not supported for tables)
        diff = function(context)
            return {
                id = context.id or "",
                supported = false,
                not_supported = true,
                message = "Diff view is not supported for tables"
            }
        end,

        -- Table-specific status
        status = function(context)
            return {
                status = "ready",
                message = "Table system operational"
            }
        end
    },

    -- No action tools yet (read-only)
    tools = {},

    -- No custom templates (use generic ones)
    templates = {}
}
