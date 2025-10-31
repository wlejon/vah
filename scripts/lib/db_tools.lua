-- Database Tools
-- Validation, introspection, and data quality utilities for SQLite

local db_tools = {}

-- Validate data against schema before import
-- Returns: success, errors (array of error messages)
function db_tools.validate_data(schema, table_name, rows)
    local errors = {}

    -- Find table definition
    local table_def = nil
    for _, tbl in ipairs(schema.tables or {}) do
        if tbl.name == table_name then
            table_def = tbl
            break
        end
    end

    if not table_def then
        return false, {"Table '" .. table_name .. "' not found in schema"}
    end

    -- Build column map for validation
    local columns_map = {}
    local required_columns = {}

    for _, col in ipairs(table_def.columns) do
        columns_map[col.name] = col

        -- Track required columns (NOT NULL without DEFAULT)
        if (col.not_null or col.required) and not col.default and not col.type:match("AUTOINCREMENT") then
            table.insert(required_columns, col.name)
        end
    end

    -- Validate each row
    for row_idx, row in ipairs(rows) do
        -- Check required columns
        for _, col_name in ipairs(required_columns) do
            if row[col_name] == nil then
                table.insert(errors, string.format("Row %d: missing required column '%s'", row_idx, col_name))
            end
        end

        -- Type validation
        for col_name, value in pairs(row) do
            if value ~= nil then
                local col_def = columns_map[col_name]
                if col_def then
                    local col_type = string.upper(col_def.type or "TEXT")

                    -- Basic type checking
                    if col_type:match("INTEGER") and type(value) ~= "number" then
                        table.insert(errors, string.format("Row %d: column '%s' expects INTEGER, got %s", row_idx, col_name, type(value)))
                    elseif col_type:match("REAL") and type(value) ~= "number" then
                        table.insert(errors, string.format("Row %d: column '%s' expects REAL, got %s", row_idx, col_name, type(value)))
                    elseif col_type:match("TEXT") and type(value) ~= "string" then
                        if type(value) ~= "number" and type(value) ~= "boolean" then  -- Allow conversion
                            table.insert(errors, string.format("Row %d: column '%s' expects TEXT, got %s", row_idx, col_name, type(value)))
                        end
                    end
                end
            end
        end
    end

    if #errors > 0 then
        return false, errors
    end

    return true, {}
end

-- Analyze data quality for a table
-- Returns statistics about the data
function db_tools.analyze_table(db, table_name)
    if not db or not db:is_open() then
        return nil, "Database not open"
    end

    if not db:table_exists(table_name) then
        return nil, "Table '" .. table_name .. "' does not exist"
    end

    local analysis = {
        table_name = table_name,
        row_count = 0,
        columns = {}
    }

    -- Get row count
    local count_result, error = db:query_single("SELECT COUNT(*) as count FROM " .. table_name)
    if error ~= "" then
        return nil, "Failed to count rows: " .. error
    end

    analysis.row_count = count_result and count_result.count or 0

    -- Get table info
    local table_info, info_error = db:get_table_info(table_name)
    if info_error ~= "" then
        return nil, "Failed to get table info: " .. info_error
    end

    -- Analyze each column
    for _, col_info in ipairs(table_info or {}) do
        local col_name = col_info.name
        local col_analysis = {
            name = col_name,
            type = col_info.type,
            null_count = 0,
            unique_count = 0,
            sample_values = {}
        }

        -- Count nulls
        local null_result, null_error = db:query_single(
            string.format("SELECT COUNT(*) as count FROM %s WHERE %s IS NULL", table_name, col_name)
        )
        if null_error == "" and null_result then
            col_analysis.null_count = null_result.count or 0
        end

        -- Count unique values
        local unique_result, unique_error = db:query_single(
            string.format("SELECT COUNT(DISTINCT %s) as count FROM %s", col_name, table_name)
        )
        if unique_error == "" and unique_result then
            col_analysis.unique_count = unique_result.count or 0
        end

        -- Get sample values (up to 5)
        local sample_result, sample_error = db:query(
            string.format("SELECT DISTINCT %s FROM %s WHERE %s IS NOT NULL LIMIT 5", col_name, table_name, col_name)
        )
        if sample_error == "" and sample_result then
            for _, row in ipairs(sample_result) do
                table.insert(col_analysis.sample_values, row[col_name])
            end
        end

        -- Calculate completeness
        if analysis.row_count > 0 then
            col_analysis.completeness = (analysis.row_count - col_analysis.null_count) / analysis.row_count
        else
            col_analysis.completeness = 0
        end

        table.insert(analysis.columns, col_analysis)
    end

    return analysis, ""
end

-- Test a query for syntax and execution
-- Returns: success, result/error
function db_tools.test_query(db, sql, params)
    if not db or not db:is_open() then
        return false, "Database not open"
    end

    params = params or {}

    -- Try to execute the query
    local result, error
    if #params > 0 then
        result, error = db:query(sql, table.unpack(params))
    else
        result, error = db:query(sql)
    end

    if error ~= "" then
        return false, error
    end

    -- Return success with row count
    local row_count = result and #result or 0
    return true, {
        row_count = row_count,
        rows = result
    }
end

-- Validate column names against schema to prevent SQL injection
local function validate_column_names(db, table_name, columns)
    -- Get table schema
    local table_info, info_error = db:get_table_info(table_name)
    if info_error ~= "" then
        return false, "Failed to get table info: " .. info_error
    end

    -- Build set of valid column names
    local valid_columns = {}
    for _, col_info in ipairs(table_info or {}) do
        valid_columns[col_info.name] = true
    end

    -- Check each column
    for _, col_name in ipairs(columns) do
        if not valid_columns[col_name] then
            return false, "Invalid column name: " .. col_name
        end
    end

    return true, ""
end

-- Find duplicate rows based on specified columns
function db_tools.find_duplicates(db, table_name, columns)
    if not db or not db:is_open() then
        return nil, "Database not open"
    end

    if not db:table_exists(table_name) then
        return nil, "Table '" .. table_name .. "' does not exist"
    end

    if not columns or #columns == 0 then
        return nil, "No columns specified for duplicate check"
    end

    -- Validate column names against schema
    local valid, error = validate_column_names(db, table_name, columns)
    if not valid then
        return nil, error
    end

    local col_list = table.concat(columns, ", ")
    local sql = string.format([[
        SELECT %s, COUNT(*) as count
        FROM %s
        GROUP BY %s
        HAVING COUNT(*) > 1
        ORDER BY count DESC
    ]], col_list, table_name, col_list)

    local result, error = db:query(sql)
    if error ~= "" then
        return nil, "Duplicate check failed: " .. error
    end

    return result, ""
end

-- Check referential integrity
-- Verifies that foreign key values exist in referenced tables
function db_tools.check_referential_integrity(db, table_name, foreign_key_column, referenced_table, referenced_column)
    if not db or not db:is_open() then
        return false, "Database not open"
    end

    local sql = string.format([[
        SELECT COUNT(*) as count
        FROM %s t1
        WHERE t1.%s IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM %s t2
            WHERE t2.%s = t1.%s
          )
    ]], table_name, foreign_key_column, referenced_table, referenced_column, foreign_key_column)

    local result, error = db:query_single(sql)
    if error ~= "" then
        return false, "Integrity check failed: " .. error
    end

    local orphan_count = result and result.count or 0

    if orphan_count > 0 then
        return false, string.format("Found %d orphaned rows in %s.%s", orphan_count, table_name, foreign_key_column)
    end

    return true, ""
end

-- Get table statistics (row count, size estimate)
function db_tools.get_table_stats(db)
    if not db or not db:is_open() then
        return nil, "Database not open"
    end

    local tables, error = db:get_tables()
    if error ~= "" then
        return nil, "Failed to get tables: " .. error
    end

    local stats = {}

    for _, table_row in ipairs(tables or {}) do
        local table_name = table_row.name

        -- Skip system tables
        if not table_name:match("^sqlite_") then
            local count_result, count_error = db:query_single("SELECT COUNT(*) as count FROM " .. table_name)

            local row_count = 0
            if count_error == "" and count_result then
                row_count = count_result.count or 0
            end

            table.insert(stats, {
                name = table_name,
                row_count = row_count
            })
        end
    end

    return stats, ""
end

-- Compare two schemas and find differences
function db_tools.compare_schemas(schema1, schema2)
    local differences = {
        added_tables = {},
        removed_tables = {},
        modified_tables = {}
    }

    -- Build table maps
    local tables1 = {}
    for _, tbl in ipairs(schema1.tables or {}) do
        tables1[tbl.name] = tbl
    end

    local tables2 = {}
    for _, tbl in ipairs(schema2.tables or {}) do
        tables2[tbl.name] = tbl
    end

    -- Find added and removed tables
    for name, _ in pairs(tables2) do
        if not tables1[name] then
            table.insert(differences.added_tables, name)
        end
    end

    for name, _ in pairs(tables1) do
        if not tables2[name] then
            table.insert(differences.removed_tables, name)
        end
    end

    -- Find modified tables (simple column count comparison)
    for name, tbl1 in pairs(tables1) do
        local tbl2 = tables2[name]
        if tbl2 then
            if #tbl1.columns ~= #tbl2.columns then
                table.insert(differences.modified_tables, name)
            else
                -- Compare column names
                local cols1 = {}
                for _, col in ipairs(tbl1.columns) do
                    cols1[col.name] = true
                end

                for _, col in ipairs(tbl2.columns) do
                    if not cols1[col.name] then
                        table.insert(differences.modified_tables, name)
                        break
                    end
                end
            end
        end
    end

    local has_changes = #differences.added_tables > 0 or
                       #differences.removed_tables > 0 or
                       #differences.modified_tables > 0

    return has_changes, differences
end

-- Export table data to Lua table format
-- Default limit of 1000 rows to prevent memory issues with large tables
function db_tools.export_table(db, table_name, limit)
    if not db or not db:is_open() then
        return nil, "Database not open"
    end

    if not db:table_exists(table_name) then
        return nil, "Table '" .. table_name .. "' does not exist"
    end

    -- Apply default limit if none provided
    limit = limit or 1000

    local sql = "SELECT * FROM " .. table_name
    if limit > 0 then
        sql = sql .. " LIMIT " .. limit
    end

    local result, error = db:query(sql)
    if error ~= "" then
        return nil, "Export failed: " .. error
    end

    return result, ""
end

-- Create database backup (copy to new file)
function db_tools.backup_database(source_path, backup_path)
    -- Simple file copy using Lua
    local source_file, err1 = io.open(source_path, "rb")
    if not source_file then
        return false, "Failed to open source: " .. (err1 or "unknown error")
    end

    local content = source_file:read("*all")
    source_file:close()

    local backup_file, err2 = io.open(backup_path, "wb")
    if not backup_file then
        return false, "Failed to create backup: " .. (err2 or "unknown error")
    end

    backup_file:write(content)
    backup_file:close()

    return true, ""
end

-- Vacuum database (reclaim space and optimize)
function db_tools.vacuum(db)
    if not db or not db:is_open() then
        return false, "Database not open"
    end

    local success, error = db:execute("VACUUM")
    if not success then
        return false, "Vacuum failed: " .. error
    end

    return true, ""
end

-- Print analysis results (for debugging)
function db_tools.print_analysis(analysis)
    if not analysis then
        print("No analysis data")
        return
    end

    print(string.format("\nTable: %s", analysis.table_name))
    print(string.format("Rows: %d", analysis.row_count))
    print("\nColumns:")

    for _, col in ipairs(analysis.columns) do
        print(string.format("  %s (%s)", col.name, col.type))
        print(string.format("    Null count: %d (%.1f%% complete)", col.null_count, col.completeness * 100))
        print(string.format("    Unique values: %d", col.unique_count))
        if #col.sample_values > 0 then
            print("    Sample: " .. table.concat(col.sample_values, ", "))
        end
    end
end

return db_tools
