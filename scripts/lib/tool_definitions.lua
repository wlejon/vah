-- Tool Definitions
-- Model-agnostic tool definitions for the Manufold agent system
-- These definitions are translated to model-specific formats by adapters

local tool_definitions = {
    {
        name = "list_files",
        description = "Lists all files that have been ingested into the current session.",
        parameters = {},
        returns = "JSON array of file objects with name, path, size, and type fields."
    },
    {
        name = "read_file",
        description = "Reads the complete contents of a specific file.",
        parameters = {
            {
                name = "path",
                type = "string",
                required = true,
                description = "Full path to the file to read"
            }
        },
        returns = "File contents as a string."
    },
    {
        name = "create_comprehension_doc",
        description = "Creates a comprehension document describing what the data represents.",
        parameters = {
            {
                name = "content",
                type = "string",
                required = true,
                description = "Markdown-formatted comprehension document"
            }
        },
        returns = "Confirmation message."
    },
    {
        name = "propose_schema",
        description = "Proposes a database schema for the ingested data.",
        parameters = {
            {
                name = "schema",
                type = "object",
                required = true,
                description = "Schema definition with tables array, each containing name and columns"
            }
        },
        returns = "Confirmation message."
    },
    {
        name = "generate_parser",
        description = "Generates a parsing script for a specific file type.",
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
                description = "Lua script code for parsing the file type"
            }
        },
        returns = "Confirmation message."
    }
}

return tool_definitions
