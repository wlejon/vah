-- Enhanced Tool Definitions for Manufold Agent
-- Each tool returns a rich, structured VIEW of results - not just success/error
-- Think of tools as rendering information for agent consumption, like UIs for humans

local manufold_tools = {
    -- File System Exploration Tools
    {
        name = "list_files",
        description = "List all ingested files with metadata. Returns a structured view of the file collection including type distribution, size statistics, and sample paths.",
        parameters = {},
        returns = [[VIEW: {
    total_count: number,
    by_extension: {ext: count},
    by_mime_type: {mime: count},
    size_stats: {total_bytes, avg_bytes, largest_file},
    sample_files: [{path, name, extension, size, mime_type}],
    binary_vs_text: {binary_count, text_count}
}]]
    },

    {
        name = "inspect_file",
        description = "Intelligently inspect a file's contents. Automatically samples large files, detects encoding, provides structure hints. Returns a rich view of file contents suitable for analysis.",
        parameters = {
            {
                name = "path",
                type = "string",
                required = true,
                description = "Full path to the file"
            },
            {
                name = "max_bytes",
                type = "number",
                required = false,
                description = "Maximum bytes to read (default: 32768 for text, 1024 for binary)"
            }
        },
        returns = [[VIEW: {
    metadata: {path, name, extension, size, mime_type, is_binary},
    content: string (full or sampled),
    was_truncated: boolean,
    truncated_at_bytes: number,
    structure_hints: {
        has_headers: boolean,
        line_count: number,
        avg_line_length: number,
        detected_format: "csv"|"json"|"xml"|"plain",
        detected_encoding: string,
        sample_lines: [string] (first 5 and last 5 if truncated)
    },
    parsing_suggestions: [string] (hints for how to parse this file)
}]]
    },

    {
        name = "analyze_file_collection",
        description = "Analyze relationships and patterns across all ingested files. Returns insights about directory structure, naming conventions, and data relationships.",
        parameters = {},
        returns = [[VIEW: {
    directory_structure: tree of paths,
    naming_patterns: [detected patterns],
    probable_relationships: [{file1, file2, relationship_type, confidence}],
    format_consistency: {format: [files], consistency_score},
    recommendations: [string] (data modeling suggestions)
}]]
    },

    -- Database Schema Tools
    {
        name = "propose_schema",
        description = "Propose a database schema. Returns confirmation and a view of the proposed structure for validation.",
        parameters = {
            {
                name = "schema",
                type = "object",
                required = true,
                description = "Schema definition: {tables: [{name, columns: [{name, type, primary, foreign_key, nullable, default}]}], indexes: [{table, columns}]}"
            }
        },
        returns = [[VIEW: {
    status: "proposed",
    schema_summary: {
        table_count: number,
        total_columns: number,
        tables: [{name, column_count, has_primary_key, foreign_keys: []}]
    },
    validation: {
        is_valid: boolean,
        warnings: [string],
        suggestions: [string]
    },
    estimated_complexity: "simple"|"moderate"|"complex"
}]]
    },

    {
        name = "execute_schema",
        description = "Execute a proposed schema by creating tables, indexes, and constraints in the database. Returns a detailed view of what was created and any issues encountered.",
        parameters = {
            {
                name = "db_path",
                type = "string",
                required = true,
                description = "Path to SQLite database (will be created if doesn't exist)"
            }
        },
        returns = [[VIEW: {
    execution_status: "success"|"partial"|"failed",
    database_info: {path, size_bytes, created_tables, created_indexes},
    created_objects: [{
        type: "table"|"index",
        name: string,
        sql: string (the CREATE statement),
        status: "created"|"exists"|"failed",
        error: string (if failed)
    }],
    schema_verification: {verified: boolean, mismatches: []},
    ready_for_import: boolean,
    next_steps: [string] (guidance for agent)
}]]
    },

    {
        name = "introspect_database",
        description = "Examine an existing database's schema. Returns a comprehensive view of all tables, columns, indexes, and data statistics.",
        parameters = {
            {
                name = "db_path",
                type = "string",
                required = true,
                description = "Path to SQLite database"
            },
            {
                name = "include_data_stats",
                type = "boolean",
                required = false,
                description = "Include row counts and data statistics (default: true)"
            }
        },
        returns = [[VIEW: {
    database_info: {path, size_bytes, table_count, index_count},
    tables: [{
        name: string,
        columns: [{name, type, nullable, default, primary_key}],
        indexes: [{name, columns, unique}],
        foreign_keys: [{from_col, to_table, to_col}],
        row_count: number,
        data_sample: [{col: val}] (first 3 rows),
        statistics: {
            estimated_size_bytes: number,
            column_stats: [{col: name, null_count, distinct_count}]
        }
    }],
    relationships: [{from_table, to_table, via_column, cardinality}],
    health: {issues: [string], warnings: [string]},
    query_suggestions: [string] (useful queries for this schema)
}]]
    },

    -- Data Transformation Tools
    {
        name = "generate_parser",
        description = "Generate a parsing script for a specific file type. Returns the script and a view of what it will do.",
        parameters = {
            {
                name = "file_type",
                type = "string",
                required = true,
                description = "File extension (csv, json, txt, etc)"
            },
            {
                name = "script_content",
                type = "string",
                required = true,
                description = "Complete Lua script for parsing this file type"
            },
            {
                name = "target_table",
                type = "string",
                required = true,
                description = "Target database table for parsed data"
            },
            {
                name = "field_mapping",
                type = "object",
                required = true,
                description = "Mapping from file fields to table columns"
            }
        },
        returns = [[VIEW: {
    parser_info: {
        file_type: string,
        target_table: string,
        field_count: number,
        estimated_complexity: string
    },
    script_analysis: {
        line_count: number,
        has_error_handling: boolean,
        has_validation: boolean,
        functions_defined: [string]
    },
    field_mapping: [{source_field, target_column, transform}],
    validation_rules: [string],
    ready_to_execute: boolean
}]]
    },

    {
        name = "execute_parser",
        description = "Execute a parser script on ingested files. Returns detailed import results including success/failure counts, data quality metrics, and sample imported rows.",
        parameters = {
            {
                name = "parser_id",
                type = "string",
                required = true,
                description = "ID of the parser to execute (from generate_parser)"
            },
            {
                name = "file_paths",
                type = "array",
                required = true,
                description = "Array of file paths to process"
            },
            {
                name = "db_path",
                type = "string",
                required = true,
                description = "Target database path"
            },
            {
                name = "dry_run",
                type = "boolean",
                required = false,
                description = "If true, parse but don't insert (default: false)"
            }
        },
        returns = [[VIEW: {
    execution_summary: {
        status: "completed"|"partial"|"failed",
        files_processed: number,
        files_failed: number,
        total_rows_parsed: number,
        total_rows_inserted: number,
        duration_seconds: number
    },
    per_file_results: [{
        file: string,
        status: "success"|"failed",
        rows_parsed: number,
        rows_inserted: number,
        errors: [{line, error, context}],
        warnings: [string]
    }],
    data_quality: {
        null_percentage_by_column: {col: percentage},
        duplicate_rows: number,
        validation_failures: [{rule, count}],
        type_coercion_count: number
    },
    sample_imported_data: [{col: val}] (first 5 rows),
    database_after_import: {
        table_row_count: number,
        table_size_bytes: number
    },
    issues_requiring_attention: [string],
    recommendations: [string] (next steps)
}]]
    },

    {
        name = "validate_import",
        description = "Validate imported data against expected schema and business rules. Returns a comprehensive data quality report.",
        parameters = {
            {
                name = "db_path",
                type = "string",
                required = true,
                description = "Database path"
            },
            {
                name = "table_name",
                type = "string",
                required = true,
                description = "Table to validate"
            },
            {
                name = "validation_rules",
                type = "array",
                required = false,
                description = "Custom validation rules"
            }
        },
        returns = [[VIEW: {
    validation_summary: {
        total_rows: number,
        valid_rows: number,
        invalid_rows: number,
        validation_passed: boolean
    },
    schema_compliance: {
        all_columns_present: boolean,
        type_mismatches: [{column, expected, found_count}],
        constraint_violations: [{constraint, violation_count}]
    },
    data_quality_metrics: {
        completeness: {col: percentage_filled},
        uniqueness: {col: duplicate_count},
        value_ranges: {col: {min, max, avg}}
    },
    sample_issues: [{row_id, column, issue, value}],
    recommendations: [string]
}]]
    },

    -- Documentation Tools
    {
        name = "create_comprehension_doc",
        description = "Create a comprehension document. Returns confirmation and a structured view of what was documented.",
        parameters = {
            {
                name = "content",
                type = "string",
                required = true,
                description = "Markdown-formatted comprehension document"
            }
        },
        returns = [[VIEW: {
    document_summary: {
        section_count: number,
        word_count: number,
        topics_covered: [string]
    },
    key_entities_mentioned: [string],
    relationships_described: [{entity1, entity2, relationship}],
    ambiguities_noted: [string],
    ready_for_validation: boolean
}]]
    },

    -- View Generation Tools
    {
        name = "generate_view",
        description = "Generate an RML/RCSS view for data visualization. Returns the generated view code and a preview description.",
        parameters = {
            {
                name = "view_type",
                type = "string",
                required = true,
                description = "Type: 'table'|'list'|'detail'|'dashboard'|'chart'"
            },
            {
                name = "data_source",
                type = "object",
                required = true,
                description = "Data source definition: {table, columns, filters}"
            },
            {
                name = "layout_preferences",
                type = "object",
                required = false,
                description = "Layout hints: {compact, scrollable, sortable}"
            }
        },
        returns = [[VIEW: {
    generated_files: [{
        path: string,
        type: "rml"|"rcss"|"lua",
        content: string,
        line_count: number
    }],
    view_description: {
        displays_data_from: [string],
        supports_interactions: [string],
        layout_type: string,
        responsive: boolean
    },
    preview: string (text description of how it looks),
    integration_steps: [string],
    example_usage: string (how to load/use this view)
}]]
    },

    {
        name = "query_data",
        description = "Execute a SQL query and return results in a structured, agent-friendly format. Useful for validating data or generating view content.",
        parameters = {
            {
                name = "db_path",
                type = "string",
                required = true,
                description = "Database path"
            },
            {
                name = "query",
                type = "string",
                required = true,
                description = "SQL query"
            },
            {
                name = "max_rows",
                type = "number",
                required = false,
                description = "Maximum rows to return (default: 100)"
            }
        },
        returns = [[VIEW: {
    query_info: {
        executed_query: string,
        execution_time_ms: number,
        row_count: number,
        was_limited: boolean
    },
    columns: [{name, type}],
    rows: [{col: val}],
    statistics: {
        numeric_columns: {col: {min, max, avg, sum}},
        text_columns: {col: {unique_count, most_common: [(val, count)]}}
    },
    visualization_suggestions: [string] (how this data could be displayed)
}]]
    }
}

return manufold_tools
