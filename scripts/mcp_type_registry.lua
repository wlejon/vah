-- MCP Type Registry
-- Loads and manages data type definitions for the MCP view system

local M = {}

-- Registered types
-- Maps type_name -> type_definition
local types = {}

-- Configuration
local config = nil

-- Initialize the type registry
function M.init(registry_config)
    config = registry_config
    types = {}

    print("Initializing type registry...")
    print("Types directory: " .. config.types_directory)
    print("Templates directory: " .. config.templates_directory)

    -- Scan types directory and load type definitions
    local type_files, err = fs.list_dir(config.types_directory)

    if err ~= "" then
        print("Warning: Could not scan types directory: " .. err)
        print("Type registry initialized with no types")
        return
    end

    -- Load each type definition
    local loaded_count = 0
    for _, entry in ipairs(type_files) do
        -- Only load .lua files
        if not entry.is_dir and entry.name:match("%.lua$") then
            local type_name = entry.name:match("^(.+)%.lua$")
            local module_path = config.types_directory .. "/" .. type_name

            local success, type_def = pcall(require, module_path)

            if success and type_def then
                -- Validate type definition
                if M.validate_type(type_name, type_def) then
                    types[type_name] = type_def
                    loaded_count = loaded_count + 1
                    print("  Loaded type: " .. type_name)
                else
                    print("  Warning: Invalid type definition: " .. type_name)
                end
            else
                print("  Warning: Failed to load type: " .. type_name)
                if type_def then
                    print("    Error: " .. tostring(type_def))
                end
            end
        end
    end

    print("Type registry initialized with " .. loaded_count .. " types")
end

-- Validate a type definition
function M.validate_type(type_name, type_def)
    if type(type_def) ~= "table" then
        print("    Type definition is not a table")
        return false
    end

    -- Check required fields
    if not type_def.name then
        print("    Missing required field: name")
        return false
    end

    if not type_def.plural then
        print("    Missing required field: plural")
        return false
    end

    if not type_def.query or type(type_def.query) ~= "table" then
        print("    Missing or invalid required field: query")
        return false
    end

    -- Check that query functions exist
    local required_queries = {"list", "detail", "summary", "search", "diff", "status"}
    for _, query_name in ipairs(required_queries) do
        if not type_def.query[query_name] or type(type_def.query[query_name]) ~= "function" then
            print("    Missing query function: " .. query_name)
            return false
        end
    end

    -- Tools are optional, but if present must be a table
    if type_def.tools and type(type_def.tools) ~= "table" then
        print("    Invalid tools field (must be table)")
        return false
    end

    -- Templates are optional, but if present must be a table
    if type_def.templates and type(type_def.templates) ~= "table" then
        print("    Invalid templates field (must be table)")
        return false
    end

    return true
end

-- Get a type definition by name
function M.get(type_name)
    return types[type_name]
end

-- Get all registered type names
function M.get_all_names()
    local names = {}
    for name, _ in pairs(types) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Check if a type is registered
function M.has(type_name)
    return types[type_name] ~= nil
end

-- Get the template path for a type and view
-- Returns custom template path if defined, otherwise generic template path
function M.get_template_path(type_name, view_name)
    local type_def = types[type_name]

    if type_def and type_def.templates and type_def.templates[view_name] then
        -- Type has custom template for this view
        return type_def.templates[view_name]
    end

    -- Use generic template
    return config.templates_directory .. "/" .. view_name .. ".md"
end

return M
