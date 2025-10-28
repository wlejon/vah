-- Row Type Definition
-- Provides views for database table rows

return {
    name = "Row",
    plural = "Rows",

    -- Query functions for each view type
    query = {
        -- List rows in a table with pagination
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10
            local database = context.database
            local table_name = context.table

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            if not database then
                error("Missing required context parameter: database")
            end

            if not table_name then
                error("Missing required context parameter: table")
            end

            local offset = (page - 1) * limit

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Get total row count
            local count_query = "SELECT COUNT(*) as count FROM " .. table_name
            local count_rows, count_err = dbh:query(count_query)
            local total = 0

            if count_err == "" and count_rows and count_rows[1] then
                total = count_rows[1].count or 0
            end

            -- Get column names
            local info_query = "PRAGMA table_info(" .. table_name .. ")"
            local info_rows, info_err = dbh:query(info_query)

            local columns = {}
            if info_err == "" and info_rows then
                for _, col in ipairs(info_rows) do
                    table.insert(columns, col.name)
                end
            end

            -- Query rows with pagination
            local data_query = "SELECT * FROM " .. table_name .. " LIMIT " .. limit .. " OFFSET " .. offset
            local data_rows, data_err = dbh:query(data_query)

            local items = {}
            if data_err == "" and data_rows then
                for idx, row in ipairs(data_rows) do
                    -- Add row index for detail view
                    row._row_index = offset + idx

                    -- Generate a display name from first few columns
                    local name_parts = {}
                    for _, col in ipairs(columns) do
                        if col ~= "_row_index" and row[col] ~= nil then
                            local value = tostring(row[col])
                            -- Truncate long values
                            if #value > 50 then
                                value = value:sub(1, 47) .. "..."
                            end
                            table.insert(name_parts, value)
                            -- Only show first 3 columns in name
                            if #name_parts >= 3 then
                                break
                            end
                        end
                    end
                    row.name = table.concat(name_parts, " | ")
                    if row.name == "" then
                        row.name = "Row " .. (offset + idx)
                    end

                    table.insert(items, row)
                end
            end

            dbh:close()

            local total_pages = math.max(1, math.ceil(total / limit))

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit,
                database = database,
                table = table_name,
                columns = columns
            }
        end,

        -- View single row details
        detail = function(context)
            local row_id = context.id
            local database = context.database
            local table_name = context.table
            local primary_key = context.primary_key or "rowid"

            if not row_id then
                error("Missing row ID")
            end

            if not database then
                error("Missing required context parameter: database")
            end

            if not table_name then
                error("Missing required context parameter: table")
            end

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Get row by primary key or rowid
            local query = "SELECT * FROM " .. table_name .. " WHERE " .. primary_key .. " = ?"
            local rows, query_err = dbh:query(query, row_id)

            if query_err ~= "" then
                dbh:close()
                error("Failed to query row: " .. query_err)
            end

            if not rows or #rows == 0 then
                dbh:close()
                error("Row not found: " .. row_id)
            end

            local row = rows[1]

            -- Get column info for types
            local info_query = "PRAGMA table_info(" .. table_name .. ")"
            local info_rows, info_err = dbh:query(info_query)

            local columns = {}
            if info_err == "" and info_rows then
                for _, col in ipairs(info_rows) do
                    columns[col.name] = {
                        type = col.type,
                        notnull = col.notnull == 1,
                        pk = col.pk > 0
                    }
                end
            end

            dbh:close()

            -- Build result with column metadata
            local result = {
                id = row_id,
                database = database,
                table = table_name,
                primary_key = primary_key
            }

            -- Add each column value
            for key, value in pairs(row) do
                result[key] = value
            end

            -- Add column metadata
            result._columns = columns

            return result
        end,

        -- Row summary statistics
        summary = function(context)
            local database = context.database
            local table_name = context.table

            if not database then
                error("Missing required context parameter: database")
            end

            if not table_name then
                error("Missing required context parameter: table")
            end

            -- Open database
            local dbh, open_err = db.open(database)
            if open_err ~= "" or not dbh then
                error("Failed to open database: " .. open_err)
            end

            -- Get row count
            local count_query = "SELECT COUNT(*) as count FROM " .. table_name
            local count_rows, count_err = dbh:query(count_query)
            local total_rows = 0

            if count_err == "" and count_rows and count_rows[1] then
                total_rows = count_rows[1].count or 0
            end

            -- Get column count
            local info_query = "PRAGMA table_info(" .. table_name .. ")"
            local info_rows, info_err = dbh:query(info_query)
            local column_count = 0

            if info_err == "" and info_rows then
                column_count = #info_rows
            end

            dbh:close()

            return {
                database = database,
                table = table_name,
                total_rows = total_rows,
                column_count = column_count,
                total_cells = total_rows * column_count
            }
        end,

        -- Search rows by content
        search = function(context)
            local search_query = context.query or ""
            local database = context.database
            local table_name = context.table

            if not database then
                error("Missing required context parameter: database")
            end

            if not table_name then
                error("Missing required context parameter: table")
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

            -- Get column names
            local info_query = "PRAGMA table_info(" .. table_name .. ")"
            local info_rows, info_err = dbh:query(info_query)

            local columns = {}
            if info_err == "" and info_rows then
                for _, col in ipairs(info_rows) do
                    table.insert(columns, col.name)
                end
            end

            -- Build search query (search all text columns)
            -- Note: This is a simple implementation that searches all columns
            local where_conditions = {}
            for _, col in ipairs(columns) do
                table.insert(where_conditions, col .. " LIKE ?")
            end

            local search_pattern = "%" .. search_query .. "%"
            local params = {}
            for i = 1, #columns do
                table.insert(params, search_pattern)
            end

            local query = "SELECT * FROM " .. table_name
            if #where_conditions > 0 then
                query = query .. " WHERE " .. table.concat(where_conditions, " OR ")
            end
            query = query .. " LIMIT 100"  -- Limit search results

            local rows, query_err = dbh:query(query, table.unpack(params))

            local matches = {}
            if query_err == "" and rows then
                for _, row in ipairs(rows) do
                    table.insert(matches, row)
                end
            end

            dbh:close()

            return {
                query = search_query,
                items = matches,
                total_matches = #matches,
                database = database,
                table = table_name
            }
        end,

        -- Diff view (compare two rows or show changes)
        diff = function(context)
            -- This could be used to compare two rows or show before/after of an edit
            -- For now, not implemented
            return {
                id = context.id or "",
                supported = false,
                not_supported = true,
                message = "Diff view is not yet implemented for rows"
            }
        end,

        -- Row-specific status
        status = function(context)
            return {
                status = "ready",
                message = "Row system operational"
            }
        end
    },

    -- No action tools yet (read-only)
    -- Future: insert_row, update_row, delete_row
    tools = {},

    -- Custom templates
    templates = {
        list = "mcp_views/templates/row_list.md"
    }
}
