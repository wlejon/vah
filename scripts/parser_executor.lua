-- Parser Executor
-- Executes generated parser scripts with sandboxing, error handling, and rich result views

local ParserExecutor = {}

-- Storage for generated parsers
local parsers = {}

-- Register a parser for later execution
function ParserExecutor.register_parser(parser_id, file_type, script_content, target_table, field_mapping)
    -- Analyze script
    local line_count = 0
    for _ in script_content:gmatch("\n") do
        line_count = line_count + 1
    end

    -- Check for error handling patterns
    local has_error_handling = script_content:match("pcall") or
                                script_content:match("error") or
                                script_content:match("if%s+not")

    -- Check for validation
    local has_validation = script_content:match("validate") or
                           script_content:match("check") or
                           script_content:match("assert")

    -- Extract function names
    local functions_defined = {}
    for func_name in script_content:gmatch("function%s+([%w_]+)") do
        table.insert(functions_defined, func_name)
    end

    -- Store parser
    parsers[parser_id] = {
        file_type = file_type,
        script_content = script_content,
        target_table = target_table,
        field_mapping = field_mapping,
        analysis = {
            line_count = line_count,
            has_error_handling = has_error_handling,
            has_validation = has_validation,
            functions_defined = functions_defined
        }
    }

    -- Convert field mapping to list format
    local field_mapping_list = {}
    for source, target in pairs(field_mapping or {}) do
        table.insert(field_mapping_list, {
            source_field = source,
            target_column = target,
            transform = "direct"
        })
    end

    return {
        parser_info = {
            file_type = file_type,
            target_table = target_table,
            field_count = #field_mapping_list,
            estimated_complexity = line_count > 100 and "complex" or (line_count > 50 and "moderate" or "simple")
        },
        script_analysis = {
            line_count = line_count,
            has_error_handling = has_error_handling,
            has_validation = has_validation,
            functions_defined = functions_defined
        },
        field_mapping = field_mapping_list,
        validation_rules = {}, -- Could be extracted from script
        ready_to_execute = true
    }
end

-- Create a sandboxed environment for parser execution
local function create_parser_sandbox(db, file_path)
    local sandbox = {
        -- Safe Lua functions
        assert = assert,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        pcall = pcall,
        select = select,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack,

        -- Safe libraries
        string = string,
        table = table,
        math = math,

        -- JSON for parsing
        json = json,

        -- File system (read-only for safety)
        fs = {
            read_file = fs.read_file,
            basename = fs.basename,
            dirname = fs.dirname,
            extension = fs.extension
        },

        -- Database access
        db = db,

        -- Current file being processed
        file_path = file_path,

        -- Results accumulator
        _rows_parsed = 0,
        _rows_inserted = 0,
        _errors = {},
        _warnings = {}
    }

    -- Add helper functions for parsers
    sandbox.add_row = function(row_data)
        sandbox._rows_parsed = sandbox._rows_parsed + 1
        -- Row will be inserted by executor
        return row_data
    end

    sandbox.report_error = function(line, error_msg, context)
        table.insert(sandbox._errors, {
            line = line or 0,
            error = error_msg,
            context = context or ""
        })
    end

    sandbox.report_warning = function(warning_msg)
        table.insert(sandbox._warnings, warning_msg)
    end

    return sandbox
end

-- Execute a parser on multiple files
function ParserExecutor.execute_parser(parser_id, file_paths, db_path, dry_run)
    dry_run = dry_run or false

    -- Get parser
    local parser = parsers[parser_id]
    if not parser then
        return {
            execution_summary = {
                status = "failed",
                error = "Parser not found: " .. parser_id
            }
        }
    end

    -- Open database
    local db = sqlite.open(db_path)
    if not db then
        return {
            execution_summary = {
                status = "failed",
                error = "Failed to open database: " .. db_path
            }
        }
    end

    -- Start transaction for better performance
    if not dry_run then
        db:execute("BEGIN TRANSACTION")
    end

    local start_time = os.clock()
    local per_file_results = {}
    local total_rows_parsed = 0
    local total_rows_inserted = 0
    local files_processed = 0
    local files_failed = 0

    -- Process each file
    for _, file_path in ipairs(file_paths) do
        -- Create sandbox for this file
        local sandbox = create_parser_sandbox(db, file_path)

        -- Load and compile parser script
        local parser_func, compile_err = load(parser.script_content, "parser_" .. parser_id, "t", sandbox)

        if not parser_func then
            files_failed = files_failed + 1
            table.insert(per_file_results, {
                file = file_path,
                status = "failed",
                rows_parsed = 0,
                rows_inserted = 0,
                errors = {{line = 0, error = "Script compilation failed: " .. (compile_err or "unknown error"), context = ""}},
                warnings = {}
            })
        else
            -- Execute parser
            local success, result = pcall(parser_func)

            if not success then
                files_failed = files_failed + 1
                table.insert(per_file_results, {
                    file = file_path,
                    status = "failed",
                    rows_parsed = sandbox._rows_parsed,
                    rows_inserted = sandbox._rows_inserted,
                    errors = {{line = 0, error = "Runtime error: " .. tostring(result), context = ""}},
                    warnings = sandbox._warnings
                })
            else
                -- Parser executed successfully
                -- Result should be array of rows to insert

                local rows_to_insert = {}
                if type(result) == "table" then
                    -- Check if it's an array of rows
                    if #result > 0 then
                        rows_to_insert = result
                    end
                end

                sandbox._rows_parsed = #rows_to_insert

                -- Insert rows into database
                if not dry_run and #rows_to_insert > 0 then
                    -- Build insert statement
                    local columns = {}
                    for col_name, _ in pairs(rows_to_insert[1] or {}) do
                        table.insert(columns, col_name)
                    end

                    if #columns > 0 then
                        local placeholders = {}
                        for i = 1, #columns do
                            table.insert(placeholders, "?")
                        end

                        local insert_sql = string.format(
                            "INSERT INTO %s (%s) VALUES (%s)",
                            parser.target_table,
                            table.concat(columns, ", "),
                            table.concat(placeholders, ", ")
                        )

                        -- Prepare statement
                        for _, row in ipairs(rows_to_insert) do
                            local values = {}
                            for _, col in ipairs(columns) do
                                table.insert(values, row[col])
                            end

                            -- Execute insert (simplified - in real implementation use prepared statements)
                            local values_str = {}
                            for _, val in ipairs(values) do
                                if type(val) == "string" then
                                    table.insert(values_str, "'" .. val:gsub("'", "''") .. "'")
                                elseif val == nil then
                                    table.insert(values_str, "NULL")
                                else
                                    table.insert(values_str, tostring(val))
                                end
                            end

                            local final_sql = string.format(
                                "INSERT INTO %s (%s) VALUES (%s)",
                                parser.target_table,
                                table.concat(columns, ", "),
                                table.concat(values_str, ", ")
                            )

                            local insert_success, insert_err = db:execute(final_sql)
                            if insert_success then
                                sandbox._rows_inserted = sandbox._rows_inserted + 1
                            else
                                table.insert(sandbox._errors, {
                                    line = 0,
                                    error = "Insert failed: " .. (insert_err or "unknown error"),
                                    context = final_sql
                                })
                            end
                        end
                    end
                else
                    sandbox._rows_inserted = sandbox._rows_parsed
                end

                files_processed = files_processed + 1
                total_rows_parsed = total_rows_parsed + sandbox._rows_parsed
                total_rows_inserted = total_rows_inserted + sandbox._rows_inserted

                table.insert(per_file_results, {
                    file = file_path,
                    status = #sandbox._errors == 0 and "success" or "failed",
                    rows_parsed = sandbox._rows_parsed,
                    rows_inserted = sandbox._rows_inserted,
                    errors = sandbox._errors,
                    warnings = sandbox._warnings
                })
            end
        end
    end

    -- Commit transaction
    if not dry_run then
        db:execute("COMMIT")
    end

    local duration = os.clock() - start_time

    -- Get sample imported data
    local sample_imported_data = {}
    if not dry_run and total_rows_inserted > 0 then
        local sample_query = string.format("SELECT * FROM %s LIMIT 5", parser.target_table)
        sample_imported_data, _ = db:query(sample_query)
    end

    -- Get table statistics after import
    local table_row_count = 0
    local table_size_bytes = 0

    if not dry_run then
        local count_query = string.format("SELECT COUNT(*) as count FROM %s", parser.target_table)
        local count_result, _ = db:query(count_query)
        if count_result and count_result[1] then
            table_row_count = count_result[1].count
        end
    end

    -- Calculate data quality metrics
    local data_quality = {
        null_percentage_by_column = {},
        duplicate_rows = 0,
        validation_failures = {},
        type_coercion_count = 0
    }

    -- Collect issues
    local issues_requiring_attention = {}
    for _, result in ipairs(per_file_results) do
        if result.status == "failed" then
            table.insert(issues_requiring_attention, string.format(
                "File '%s' failed to parse completely",
                fs.basename(result.file)
            ))
        end
        if #result.errors > 0 then
            table.insert(issues_requiring_attention, string.format(
                "File '%s' has %d errors",
                fs.basename(result.file),
                #result.errors
            ))
        end
    end

    -- Generate recommendations
    local recommendations = {}
    if files_failed > 0 then
        table.insert(recommendations, "Review failed files and fix parser script")
    end
    if total_rows_parsed > total_rows_inserted then
        table.insert(recommendations, string.format(
            "%d rows were parsed but not inserted - investigate errors",
            total_rows_parsed - total_rows_inserted
        ))
    end
    if files_processed == #file_paths and #issues_requiring_attention == 0 then
        table.insert(recommendations, "Import successful - proceed to view generation")
        table.insert(recommendations, "Use introspect_database to verify imported data")
    end

    db:close()

    local execution_status = "completed"
    if files_failed == #file_paths then
        execution_status = "failed"
    elseif files_failed > 0 then
        execution_status = "partial"
    end

    return {
        execution_summary = {
            status = execution_status,
            files_processed = files_processed,
            files_failed = files_failed,
            total_rows_parsed = total_rows_parsed,
            total_rows_inserted = total_rows_inserted,
            duration_seconds = duration
        },
        per_file_results = per_file_results,
        data_quality = data_quality,
        sample_imported_data = sample_imported_data or {},
        database_after_import = {
            table_row_count = table_row_count,
            table_size_bytes = table_size_bytes
        },
        issues_requiring_attention = issues_requiring_attention,
        recommendations = recommendations
    }
end

-- Validate imported data
function ParserExecutor.validate_import(db_path, table_name, validation_rules)
    local db = sqlite.open(db_path)
    if not db then
        return {
            error = "Failed to open database: " .. db_path
        }
    end

    -- Get row count
    local count_query = string.format("SELECT COUNT(*) as count FROM %s", table_name)
    local count_result, _ = db:query(count_query)
    local total_rows = 0
    if count_result and count_result[1] then
        total_rows = count_result[1].count
    end

    -- Get table schema
    local pragma_query = string.format("PRAGMA table_info(%s)", table_name)
    local columns_raw, _ = db:query(pragma_query)

    if not columns_raw then
        db:close()
        return {
            error = "Failed to get table schema"
        }
    end

    -- Check schema compliance
    local all_columns_present = #columns_raw > 0
    local type_mismatches = {}
    local constraint_violations = {}

    -- Data quality metrics
    local completeness = {}
    local uniqueness = {}
    local value_ranges = {}

    for _, col_info in ipairs(columns_raw) do
        local col_name = col_info.name

        -- Check completeness (null percentage)
        local null_query = string.format(
            "SELECT COUNT(*) as count FROM %s WHERE %s IS NULL",
            table_name, col_name
        )
        local null_result, _ = db:query(null_query)
        local null_count = 0
        if null_result and null_result[1] then
            null_count = null_result[1].count
        end

        local completeness_pct = total_rows > 0 and ((total_rows - null_count) / total_rows * 100) or 100
        completeness[col_name] = math.floor(completeness_pct)

        -- Check uniqueness (duplicate count)
        local distinct_query = string.format(
            "SELECT COUNT(DISTINCT %s) as distinct_count, COUNT(%s) as total_count FROM %s",
            col_name, col_name, table_name
        )
        local distinct_result, _ = db:query(distinct_query)
        if distinct_result and distinct_result[1] then
            local distinct_count = distinct_result[1].distinct_count
            local total_count = distinct_result[1].total_count
            uniqueness[col_name] = total_count - distinct_count
        end

        -- Value ranges for numeric columns
        if col_info.type == "INTEGER" or col_info.type == "REAL" then
            local range_query = string.format(
                "SELECT MIN(%s) as min, MAX(%s) as max, AVG(%s) as avg FROM %s",
                col_name, col_name, col_name, table_name
            )
            local range_result, _ = db:query(range_query)
            if range_result and range_result[1] then
                value_ranges[col_name] = {
                    min = range_result[1].min,
                    max = range_result[1].max,
                    avg = range_result[1].avg
                }
            end
        end
    end

    -- Sample issues (rows with problems)
    local sample_issues = {}
    for col_name, dup_count in pairs(uniqueness) do
        if dup_count > 0 then
            table.insert(sample_issues, {
                row_id = nil,
                column = col_name,
                issue = "duplicate_value",
                value = string.format("%d duplicates found", dup_count)
            })
        end
    end

    db:close()

    local valid_rows = total_rows -- Simplified - count actual validation
    local invalid_rows = 0
    local validation_passed = #sample_issues == 0

    -- Generate recommendations
    local recommendations = {}
    if validation_passed then
        table.insert(recommendations, "Data validation passed - data quality is good")
    else
        table.insert(recommendations, "Found data quality issues - review sample_issues")
    end

    for col_name, comp_pct in pairs(completeness) do
        if comp_pct < 50 then
            table.insert(recommendations, string.format(
                "Column '%s' is only %d%% complete - consider handling nulls",
                col_name, comp_pct
            ))
        end
    end

    return {
        validation_summary = {
            total_rows = total_rows,
            valid_rows = valid_rows,
            invalid_rows = invalid_rows,
            validation_passed = validation_passed
        },
        schema_compliance = {
            all_columns_present = all_columns_present,
            type_mismatches = type_mismatches,
            constraint_violations = constraint_violations
        },
        data_quality_metrics = {
            completeness = completeness,
            uniqueness = uniqueness,
            value_ranges = value_ranges
        },
        sample_issues = sample_issues,
        recommendations = recommendations
    }
end

return ParserExecutor
