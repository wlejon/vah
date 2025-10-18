-- CSV Importer
-- Comprehensive CSV parser and SQLite importer with full RFC 4180 support

local csv_importer = {}

-- RFC 4180 compliant CSV parser
-- Handles quoted fields, embedded commas, newlines, and escaped quotes
function csv_importer.parse_line(line, delimiter)
    delimiter = delimiter or ","
    local fields = {}
    local field = ""
    local in_quotes = false
    local i = 1

    while i <= #line do
        local char = line:sub(i, i)
        local next_char = line:sub(i + 1, i + 1)

        if in_quotes then
            if char == '"' then
                if next_char == '"' then
                    -- Escaped quote (two consecutive quotes)
                    field = field .. '"'
                    i = i + 1  -- Skip next quote
                else
                    -- End of quoted field
                    in_quotes = false
                end
            else
                field = field .. char
            end
        else
            if char == '"' then
                -- Start of quoted field
                in_quotes = true
            elseif char == delimiter then
                -- Field separator
                table.insert(fields, field)
                field = ""
            else
                field = field .. char
            end
        end

        i = i + 1
    end

    -- Add final field
    table.insert(fields, field)

    return fields, in_quotes  -- Return in_quotes to detect incomplete lines
end

-- Parse entire CSV content with support for multiline fields
function csv_importer.parse(content, options)
    options = options or {}
    local delimiter = options.delimiter or ","
    local has_header = options.has_header ~= false  -- Default true
    local skip_empty = options.skip_empty ~= false  -- Default true

    local lines = {}
    local current_line = ""

    -- Split into lines while respecting quoted fields
    for line in content:gmatch("[^\r\n]+") do
        if current_line ~= "" then
            current_line = current_line .. "\n" .. line
        else
            current_line = line
        end

        -- Check if line is complete (not inside quotes)
        local _, in_quotes = csv_importer.parse_line(current_line, delimiter)
        if not in_quotes then
            if not skip_empty or current_line:match("%S") then
                table.insert(lines, current_line)
            end
            current_line = ""
        end
    end

    -- Handle any remaining content
    if current_line ~= "" then
        if not skip_empty or current_line:match("%S") then
            table.insert(lines, current_line)
        end
    end

    if #lines == 0 then
        return nil, "Empty CSV content"
    end

    -- Parse header
    local headers = nil
    local data_start = 1

    if has_header then
        headers = csv_importer.parse_line(lines[1], delimiter)
        data_start = 2
    end

    -- Parse data rows
    local rows = {}
    for i = data_start, #lines do
        local fields = csv_importer.parse_line(lines[i], delimiter)

        if headers then
            -- Create row object with field names
            local row = {}
            for j = 1, #headers do
                row[headers[j]] = fields[j] or ""
            end
            table.insert(rows, row)
        else
            -- Just use array of fields
            table.insert(rows, fields)
        end
    end

    return {
        headers = headers,
        rows = rows,
        row_count = #rows,
        column_count = headers and #headers or (#rows > 0 and #rows[1] or 0)
    }
end

-- Detect delimiter by analyzing first few lines
function csv_importer.detect_delimiter(content, max_lines)
    max_lines = max_lines or 10
    local delimiters = {",", ";", "\t", "|"}
    local scores = {}

    for _, delim in ipairs(delimiters) do
        scores[delim] = 0
    end

    local line_count = 0
    for line in content:gmatch("[^\r\n]+") do
        if line_count >= max_lines then break end

        for _, delim in ipairs(delimiters) do
            local fields = csv_importer.parse_line(line, delim)
            -- Prefer delimiter with consistent field count and more than 1 field
            if #fields > 1 then
                scores[delim] = scores[delim] + #fields
            end
        end

        line_count = line_count + 1
    end

    -- Find delimiter with highest score
    local best_delim = ","
    local best_score = 0

    for delim, score in pairs(scores) do
        if score > best_score then
            best_score = score
            best_delim = delim
        end
    end

    return best_delim
end

-- Data type detection utilities
function csv_importer.is_integer(value)
    if value == "" or value == nil then return false end
    return value:match("^%-?%d+$") ~= nil
end

function csv_importer.is_float(value)
    if value == "" or value == nil then return false end
    return value:match("^%-?%d*%.?%d+$") ~= nil
end

function csv_importer.is_boolean(value)
    if value == "" or value == nil then return false end
    local lower = value:lower()
    return lower == "true" or lower == "false" or
           lower == "yes" or lower == "no" or
           lower == "1" or lower == "0"
end

function csv_importer.is_date(value)
    if value == "" or value == nil then return false end
    -- Simple date patterns: YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY
    return value:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil or
           value:match("^%d%d/%d%d/%d%d%d%d$") ~= nil
end

-- Infer schema from CSV data
function csv_importer.infer_schema(parsed_csv, sample_size)
    sample_size = sample_size or math.min(100, #parsed_csv.rows)

    if not parsed_csv.headers then
        return nil, "Cannot infer schema without headers"
    end

    local schema = {}

    for i, header in ipairs(parsed_csv.headers) do
        local type_counts = {
            integer = 0,
            float = 0,
            boolean = 0,
            date = 0,
            text = 0,
            null = 0
        }

        local max_length = 0
        local has_nulls = false

        -- Sample rows to determine type
        for j = 1, math.min(sample_size, #parsed_csv.rows) do
            local row = parsed_csv.rows[j]
            local value = row[header]

            if value == "" or value == nil then
                type_counts.null = type_counts.null + 1
                has_nulls = true
            else
                max_length = math.max(max_length, #value)

                if csv_importer.is_integer(value) then
                    type_counts.integer = type_counts.integer + 1
                elseif csv_importer.is_float(value) then
                    type_counts.float = type_counts.float + 1
                elseif csv_importer.is_boolean(value) then
                    type_counts.boolean = type_counts.boolean + 1
                elseif csv_importer.is_date(value) then
                    type_counts.date = type_counts.date + 1
                else
                    type_counts.text = type_counts.text + 1
                end
            end
        end

        -- Determine best type
        local sql_type = "TEXT"
        local non_null_count = sample_size - type_counts.null

        if non_null_count > 0 then
            local integer_ratio = type_counts.integer / non_null_count
            local float_ratio = (type_counts.integer + type_counts.float) / non_null_count

            if integer_ratio > 0.9 then
                sql_type = "INTEGER"
            elseif float_ratio > 0.9 then
                sql_type = "REAL"
            elseif type_counts.boolean / non_null_count > 0.9 then
                sql_type = "INTEGER"  -- Store booleans as 0/1
            else
                sql_type = "TEXT"
            end
        end

        schema[header] = {
            name = header,
            type = sql_type,
            nullable = has_nulls,
            max_length = max_length,
            index = i
        }
    end

    return schema
end

-- Generate SQLite CREATE TABLE statement
function csv_importer.generate_create_table(table_name, schema, options)
    options = options or {}
    local add_id = options.add_id ~= false  -- Default true

    -- Sanitize table name
    local safe_table_name = table_name:gsub("[^%w_]", "_")

    local columns = {}

    if add_id then
        table.insert(columns, "    id INTEGER PRIMARY KEY AUTOINCREMENT")
    end

    -- Sort columns by index to maintain order
    local sorted_columns = {}
    for _, col in pairs(schema) do
        table.insert(sorted_columns, col)
    end
    table.sort(sorted_columns, function(a, b) return a.index < b.index end)

    for _, col in ipairs(sorted_columns) do
        -- Sanitize column name
        local safe_name = col.name:gsub("[^%w_]", "_")

        local def = "    " .. safe_name .. " " .. col.type

        if not col.nullable then
            def = def .. " NOT NULL"
        end

        table.insert(columns, def)
    end

    local sql = "CREATE TABLE IF NOT EXISTS " .. safe_table_name .. " (\n"
    sql = sql .. table.concat(columns, ",\n")
    sql = sql .. "\n)"

    return sql, safe_table_name
end

-- Convert value to appropriate type for SQL
function csv_importer.convert_value(value, sql_type)
    if value == "" or value == nil then
        return nil
    end

    if sql_type == "INTEGER" then
        local num = tonumber(value)
        if num then
            return math.floor(num)
        end
        -- Handle booleans
        local lower = value:lower()
        if lower == "true" or lower == "yes" then return 1 end
        if lower == "false" or lower == "no" then return 0 end
        return nil
    elseif sql_type == "REAL" then
        return tonumber(value)
    else
        return value
    end
end

-- Escape value for SQL
function csv_importer.escape_sql_value(value)
    if value == nil then
        return "NULL"
    elseif type(value) == "number" then
        return tostring(value)
    else
        return "'" .. tostring(value):gsub("'", "''") .. "'"
    end
end

-- Import CSV into SQLite database
function csv_importer.import_to_sqlite(database, table_name, parsed_csv, schema, options)
    options = options or {}
    local batch_size = options.batch_size or 1000
    local create_table = options.create_table ~= false  -- Default true
    local add_id = options.add_id ~= false  -- Default true

    -- Create table if needed
    if create_table then
        local create_sql, safe_table_name = csv_importer.generate_create_table(table_name, schema, {add_id = add_id})
        table_name = safe_table_name

        local success, error = database:execute(create_sql)
        if not success then
            return false, "Failed to create table: " .. error
        end
    end

    -- Prepare column names and order
    local columns = {}
    for _, col in pairs(schema) do
        table.insert(columns, {name = col.name, type = col.type, index = col.index})
    end
    table.sort(columns, function(a, b) return a.index < b.index end)

    local safe_table_name = table_name:gsub("[^%w_]", "_")
    local column_names = {}
    for _, col in ipairs(columns) do
        table.insert(column_names, col.name:gsub("[^%w_]", "_"))
    end

    -- Begin transaction
    local success, error = database:execute("BEGIN TRANSACTION")
    if not success then
        return false, "Failed to begin transaction: " .. error
    end

    -- Insert data in batches
    local total_inserted = 0
    local batch_values = {}

    for i, row in ipairs(parsed_csv.rows) do
        local values = {}
        for _, col in ipairs(columns) do
            local value = csv_importer.convert_value(row[col.name], col.type)
            table.insert(values, csv_importer.escape_sql_value(value))
        end

        table.insert(batch_values, "(" .. table.concat(values, ", ") .. ")")

        -- Execute batch when full or at end
        if #batch_values >= batch_size or i == #parsed_csv.rows then
            local insert_sql = string.format(
                "INSERT INTO %s (%s) VALUES %s",
                safe_table_name,
                table.concat(column_names, ", "),
                table.concat(batch_values, ", ")
            )

            local success, error = database:execute(insert_sql)
            if not success then
                database:execute("ROLLBACK")
                return false, "Failed to insert data: " .. error
            end

            total_inserted = total_inserted + #batch_values
            batch_values = {}
        end
    end

    -- Commit transaction
    success, error = database:execute("COMMIT")
    if not success then
        database:execute("ROLLBACK")
        return false, "Failed to commit transaction: " .. error
    end

    return true, string.format("Successfully imported %d rows into table '%s'", total_inserted, safe_table_name)
end

-- High-level import function
function csv_importer.import_csv_file(database, csv_path, table_name, options)
    options = options or {}

    -- Read file
    local content, error = fs.read_file(csv_path)
    if error ~= "" then
        return false, "Failed to read CSV file: " .. error
    end

    -- Auto-detect delimiter if not specified
    local delimiter = options.delimiter
    if not delimiter then
        delimiter = csv_importer.detect_delimiter(content)
        print("Auto-detected delimiter: " .. (delimiter == "\t" and "\\t" or delimiter))
    end

    -- Parse CSV
    local parsed, parse_error = csv_importer.parse(content, {
        delimiter = delimiter,
        has_header = options.has_header,
        skip_empty = options.skip_empty
    })

    if not parsed then
        return false, "Failed to parse CSV: " .. parse_error
    end

    print(string.format("Parsed CSV: %d rows, %d columns", parsed.row_count, parsed.column_count))

    -- Infer schema
    local schema, schema_error = csv_importer.infer_schema(parsed, options.sample_size)
    if not schema then
        return false, "Failed to infer schema: " .. schema_error
    end

    -- Print schema
    print("\nInferred schema:")
    for _, col in pairs(schema) do
        print(string.format("  %s: %s%s", col.name, col.type, col.nullable and " (nullable)" or ""))
    end
    print()

    -- Import to database
    return csv_importer.import_to_sqlite(database, table_name, parsed, schema, options)
end

return csv_importer
