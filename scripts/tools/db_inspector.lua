-- Database Inspector
-- Provides rich, structured views of database schemas and data

local DbInspector = {}

-- Introspect a database and return comprehensive schema information
function DbInspector.introspect(db_path, include_data_stats)
    include_data_stats = include_data_stats ~= false -- default true

    -- Check if database exists
    if not fs.exists(db_path) then
        return {
            error = "Database not found: " .. db_path,
            database_info = {path = db_path, exists = false}
        }
    end

    -- Get database file stats
    local db_stat, _ = fs.stat(db_path)
    local db_size = db_stat and db_stat.size or 0

    -- Open database
    local db = sqlite.open(db_path)
    if not db then
        return {
            error = "Failed to open database: " .. db_path,
            database_info = {path = db_path, exists = true, size_bytes = db_size}
        }
    end

    -- Get all tables
    local tables_query = [[
        SELECT name, sql
        FROM sqlite_master
        WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        ORDER BY name
    ]]
    local raw_tables, err = db:query(tables_query)

    if not raw_tables then
        db:close()
        return {
            error = "Failed to query schema: " .. (err or "unknown error"),
            database_info = {path = db_path, size_bytes = db_size}
        }
    end

    local tables = {}
    local relationships = {}

    -- For each table, get detailed information
    for _, table_info in ipairs(raw_tables) do
        local table_name = table_info.name

        -- Get column information
        local pragma_query = "PRAGMA table_info(" .. table_name .. ")"
        local columns_raw, _ = db:query(pragma_query)

        local columns = {}
        for _, col_info in ipairs(columns_raw or {}) do
            table.insert(columns, {
                name = col_info.name,
                type = col_info.type,
                nullable = col_info.notnull == 0,
                default = col_info.dflt_value,
                primary_key = col_info.pk > 0
            })
        end

        -- Get foreign keys
        local fk_query = "PRAGMA foreign_key_list(" .. table_name .. ")"
        local fks_raw, _ = db:query(fk_query)

        local foreign_keys = {}
        for _, fk in ipairs(fks_raw or {}) do
            table.insert(foreign_keys, {
                from_col = fk.from,
                to_table = fk.table,
                to_col = fk.to
            })

            -- Track relationships
            table.insert(relationships, {
                from_table = table_name,
                to_table = fk.table,
                via_column = fk.from,
                cardinality = "many_to_one" -- SQLite FK implies this
            })
        end

        -- Get indexes
        local idx_query = "PRAGMA index_list(" .. table_name .. ")"
        local indexes_raw, _ = db:query(idx_query)

        local indexes = {}
        for _, idx in ipairs(indexes_raw or {}) do
            -- Get index columns
            local idx_info_query = "PRAGMA index_info(" .. idx.name .. ")"
            local idx_cols_raw, _ = db:query(idx_info_query)

            local idx_columns = {}
            for _, idx_col in ipairs(idx_cols_raw or {}) do
                table.insert(idx_columns, idx_col.name)
            end

            table.insert(indexes, {
                name = idx.name,
                columns = idx_columns,
                unique = idx.unique == 1
            })
        end

        -- Get row count and data statistics
        local row_count = 0
        local data_sample = {}
        local statistics = {}

        if include_data_stats then
            local count_query = "SELECT COUNT(*) as count FROM " .. table_name
            local count_result, _ = db:query(count_query)
            if count_result and count_result[1] then
                row_count = count_result[1].count
            end

            -- Get sample data (first 3 rows)
            if row_count > 0 then
                local sample_query = "SELECT * FROM " .. table_name .. " LIMIT 3"
                data_sample, _ = db:query(sample_query)
            end

            -- Get column statistics
            local column_stats = {}
            for _, col in ipairs(columns) do
                local stats = {
                    col = col.name,
                    null_count = 0,
                    distinct_count = 0
                }

                -- Count nulls
                local null_query = string.format(
                    "SELECT COUNT(*) as count FROM %s WHERE %s IS NULL",
                    table_name, col.name
                )
                local null_result, _ = db:query(null_query)
                if null_result and null_result[1] then
                    stats.null_count = null_result[1].count
                end

                -- Count distinct values
                local distinct_query = string.format(
                    "SELECT COUNT(DISTINCT %s) as count FROM %s",
                    col.name, table_name
                )
                local distinct_result, _ = db:query(distinct_query)
                if distinct_result and distinct_result[1] then
                    stats.distinct_count = distinct_result[1].count
                end

                table.insert(column_stats, stats)
            end

            statistics = {
                column_stats = column_stats
            }
        end

        table.insert(tables, {
            name = table_name,
            columns = columns,
            indexes = indexes,
            foreign_keys = foreign_keys,
            row_count = row_count,
            data_sample = data_sample or {},
            statistics = statistics
        })
    end

    -- Get index count
    local index_query = [[
        SELECT COUNT(*) as count
        FROM sqlite_master
        WHERE type = 'index'
        AND name NOT LIKE 'sqlite_%'
    ]]
    local index_count_result, _ = db:query(index_query)
    local index_count = 0
    if index_count_result and index_count_result[1] then
        index_count = index_count_result[1].count
    end

    db:close()

    -- Health check
    local health_issues = {}
    local health_warnings = {}

    for _, table in ipairs(tables) do
        -- Check for missing primary keys
        local has_pk = false
        for _, col in ipairs(table.columns) do
            if col.primary_key then
                has_pk = true
                break
            end
        end
        if not has_pk then
            table.insert(health_warnings, string.format(
                "Table '%s' has no primary key",
                table.name
            ))
        end

        -- Check for empty tables
        if include_data_stats and table.row_count == 0 then
            table.insert(health_warnings, string.format(
                "Table '%s' is empty",
                table.name
            ))
        end
    end

    -- Generate query suggestions
    local query_suggestions = {}
    for _, table in ipairs(tables) do
        if table.row_count > 0 then
            table.insert(query_suggestions, string.format(
                "SELECT * FROM %s LIMIT 10  -- Browse data",
                table.name
            ))
        end

        -- Suggest joins for foreign keys
        for _, fk in ipairs(table.foreign_keys) do
            table.insert(query_suggestions, string.format(
                "SELECT * FROM %s JOIN %s ON %s.%s = %s.%s  -- Join related data",
                table.name, fk.to_table, table.name, fk.from_col, fk.to_table, fk.to_col
            ))
        end
    end

    return {
        database_info = {
            path = db_path,
            size_bytes = db_size,
            table_count = #tables,
            index_count = index_count
        },
        tables = tables,
        relationships = relationships,
        health = {
            issues = health_issues,
            warnings = health_warnings
        },
        query_suggestions = query_suggestions
    }
end

-- Execute a query and return structured results with statistics
function DbInspector.query_data(db_path, query, max_rows)
    max_rows = max_rows or 100

    -- Open database
    local db = sqlite.open(db_path)
    if not db then
        return {
            error = "Failed to open database: " .. db_path
        }
    end

    -- Measure execution time
    local start_time = os.clock()

    -- Execute query
    local rows, err = db:query(query)

    local execution_time_ms = (os.clock() - start_time) * 1000

    if not rows then
        db:close()
        return {
            error = "Query failed: " .. (err or "unknown error"),
            query_info = {
                executed_query = query,
                execution_time_ms = execution_time_ms
            }
        }
    end

    -- Limit rows
    local was_limited = false
    if #rows > max_rows then
        was_limited = true
        local limited_rows = {}
        for i = 1, max_rows do
            table.insert(limited_rows, rows[i])
        end
        rows = limited_rows
    end

    -- Extract column information
    local columns = {}
    if #rows > 0 then
        for col_name, _ in pairs(rows[1]) do
            -- Determine type by inspecting first non-null value
            local col_type = "unknown"
            for _, row in ipairs(rows) do
                local val = row[col_name]
                if val ~= nil then
                    col_type = type(val)
                    break
                end
            end

            table.insert(columns, {
                name = col_name,
                type = col_type
            })
        end
    end

    -- Calculate statistics
    local numeric_columns = {}
    local text_columns = {}

    for _, col in ipairs(columns) do
        if col.type == "number" then
            -- Numeric statistics
            local values = {}
            for _, row in ipairs(rows) do
                local val = row[col.name]
                if type(val) == "number" then
                    table.insert(values, val)
                end
            end

            if #values > 0 then
                table.sort(values)
                local sum = 0
                for _, v in ipairs(values) do
                    sum = sum + v
                end

                numeric_columns[col.name] = {
                    min = values[1],
                    max = values[#values],
                    avg = sum / #values,
                    sum = sum
                }
            end
        elseif col.type == "string" then
            -- Text statistics
            local value_counts = {}
            for _, row in ipairs(rows) do
                local val = row[col.name]
                if type(val) == "string" then
                    value_counts[val] = (value_counts[val] or 0) + 1
                end
            end

            -- Find most common values
            local most_common = {}
            for val, count in pairs(value_counts) do
                table.insert(most_common, {val, count})
            end
            table.sort(most_common, function(a, b) return a[2] > b[2] end)

            -- Take top 5
            local top_5 = {}
            for i = 1, math.min(5, #most_common) do
                table.insert(top_5, {
                    value = most_common[i][1],
                    count = most_common[i][2]
                })
            end

            text_columns[col.name] = {
                unique_count = #most_common,
                most_common = top_5
            }
        end
    end

    db:close()

    -- Generate visualization suggestions
    local viz_suggestions = {}

    if #rows == 0 then
        table.insert(viz_suggestions, "Query returned no results - no visualization needed")
    elseif #columns == 1 then
        table.insert(viz_suggestions, "Single column - could display as simple list")
    elseif #columns <= 5 then
        table.insert(viz_suggestions, "Small table - display in compact table view")
        if numeric_columns and next(numeric_columns) then
            table.insert(viz_suggestions, "Has numeric data - could visualize as bar chart or line graph")
        end
    else
        table.insert(viz_suggestions, "Many columns - use scrollable wide table or detail cards")
    end

    return {
        query_info = {
            executed_query = query,
            execution_time_ms = execution_time_ms,
            row_count = #rows,
            was_limited = was_limited
        },
        columns = columns,
        rows = rows,
        statistics = {
            numeric_columns = numeric_columns,
            text_columns = text_columns
        },
        visualization_suggestions = viz_suggestions
    }
end

return DbInspector
