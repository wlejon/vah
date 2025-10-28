-- MCP Navigation Tools
-- Core navigation tools that work across all data types

local M = {}

-- Configuration constants
local DEFAULT_PAGE_LIMIT = 10  -- Default number of items per page for list queries

-- Template renderer
local renderer = require("template_renderer")

-- Type registry reference (set during registration)
local type_registry = nil

-- Session context updater (set during registration)
local update_context_fn = nil

-- Helper to load and render template
local function render_view(template_path, data)
    -- Load template
    local template_content, err = fs.read_file(template_path)
    if err ~= "" then
        return "Error loading template: " .. err
    end

    -- Render template with data
    local success, result = pcall(renderer.render, template_content, data)
    if not success then
        return "Error rendering template: " .. tostring(result)
    end

    -- Trim leading/trailing whitespace
    result = result:gsub("^%s+", ""):gsub("%s+$", "")

    return result
end

-- Helper to get recent action text
local function get_recent_action(session)
    if not session.recent_actions or #session.recent_actions == 0 then
        return nil
    end

    local latest = session.recent_actions[#session.recent_actions]
    return latest.action
end

-- List tool: View collections of items
local function tool_list(args, session)
    local type_name = args.type
    local context = args.context or {}
    local page = args.page or 1
    local limit = args.limit or DEFAULT_PAGE_LIMIT

    if not type_name then
        return "Error: Missing required parameter 'type'"
    end

    if not type_registry.has(type_name) then
        return "Error: Unknown type '" .. type_name .. "'"
    end

    local type_def = type_registry.get(type_name)

    -- Build query context
    local query_context = {
        page = page,
        limit = limit
    }

    -- Merge additional context
    for k, v in pairs(context) do
        query_context[k] = v
    end

    -- Query data from type
    local success, query_result = pcall(type_def.query.list, query_context)
    if not success then
        return "Error querying data: " .. tostring(query_result)
    end

    -- Build template data
    local template_data = {
        type = type_def.plural or type_def.name,
        view = "list",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        data = query_result,
        context = query_context,
        recent_action = get_recent_action(session)
    }

    -- Render template
    local template_path = type_registry.get_template_path(type_name, "list")
    local rendered = render_view(template_path, template_data)

    -- Update session context
    if update_context_fn then
        update_context_fn(session, type_name, "list", nil, query_context)
    end

    return rendered
end

-- Detail tool: View single entity
local function tool_detail(args, session)
    local type_name = args.type
    local id = args.id
    local context = args.context or {}

    if not type_name then
        return "Error: Missing required parameter 'type'"
    end

    if not id then
        return "Error: Missing required parameter 'id'"
    end

    if not type_registry.has(type_name) then
        return "Error: Unknown type '" .. type_name .. "'"
    end

    local type_def = type_registry.get(type_name)

    -- Build query context
    local query_context = {
        id = id
    }

    -- Merge additional context
    for k, v in pairs(context) do
        query_context[k] = v
    end

    -- Query data from type
    local success, query_result = pcall(type_def.query.detail, query_context)
    if not success then
        return "Error querying data: " .. tostring(query_result)
    end

    -- Build template data
    local template_data = {
        type = type_def.name,
        view = "detail",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        data = query_result,
        context = query_context,
        recent_action = get_recent_action(session)
    }

    -- Render template
    local template_path = type_registry.get_template_path(type_name, "detail")
    local rendered = render_view(template_path, template_data)

    -- Update session context
    if update_context_fn then
        update_context_fn(session, type_name, "detail", id, query_context)
    end

    return rendered
end

-- Summary tool: View aggregates
local function tool_summary(args, session)
    local type_name = args.type
    local context = args.context or {}

    if not type_name then
        return "Error: Missing required parameter 'type'"
    end

    if not type_registry.has(type_name) then
        return "Error: Unknown type '" .. type_name .. "'"
    end

    local type_def = type_registry.get(type_name)

    -- Build query context
    local query_context = {}

    -- Merge additional context
    for k, v in pairs(context) do
        query_context[k] = v
    end

    -- Query data from type
    local success, query_result = pcall(type_def.query.summary, query_context)
    if not success then
        return "Error querying data: " .. tostring(query_result)
    end

    -- Build template data
    local template_data = {
        type = type_def.plural or type_def.name,
        view = "summary",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        data = query_result,
        context = query_context,
        recent_action = get_recent_action(session)
    }

    -- Render template
    local template_path = type_registry.get_template_path(type_name, "summary")
    local rendered = render_view(template_path, template_data)

    -- Update session context
    if update_context_fn then
        update_context_fn(session, type_name, "summary", nil, query_context)
    end

    return rendered
end

-- Search tool: Search within type
local function tool_search(args, session)
    local query = args.query
    local type_name = args.type
    local context = args.context or {}

    if not query then
        return "Error: Missing required parameter 'query'"
    end

    if not type_name then
        return "Error: Missing required parameter 'type'"
    end

    if not type_registry.has(type_name) then
        return "Error: Unknown type '" .. type_name .. "'"
    end

    local type_def = type_registry.get(type_name)

    -- Build query context
    local query_context = {
        query = query
    }

    -- Merge additional context
    for k, v in pairs(context) do
        query_context[k] = v
    end

    -- Query data from type
    local success, query_result = pcall(type_def.query.search, query_context)
    if not success then
        return "Error querying data: " .. tostring(query_result)
    end

    -- Build template data
    local template_data = {
        type = type_def.plural or type_def.name,
        view = "search",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        data = query_result,
        context = query_context,
        recent_action = get_recent_action(session)
    }

    -- Render template
    local template_path = type_registry.get_template_path(type_name, "search")
    local rendered = render_view(template_path, template_data)

    -- Update session context
    if update_context_fn then
        update_context_fn(session, type_name, "search", nil, query_context)
    end

    return rendered
end

-- Diff tool: Compare versions
local function tool_diff(args, session)
    local type_name = args.type
    local id = args.id
    local context = args.context or {}

    if not type_name then
        return "Error: Missing required parameter 'type'"
    end

    if not id then
        return "Error: Missing required parameter 'id'"
    end

    if not type_registry.has(type_name) then
        return "Error: Unknown type '" .. type_name .. "'"
    end

    local type_def = type_registry.get(type_name)

    -- Build query context
    local query_context = {
        id = id
    }

    -- Merge additional context
    for k, v in pairs(context) do
        query_context[k] = v
    end

    -- Query data from type
    local success, query_result = pcall(type_def.query.diff, query_context)
    if not success then
        return "Error querying data: " .. tostring(query_result)
    end

    -- Build template data
    local template_data = {
        type = type_def.name,
        view = "diff",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        data = query_result,
        context = query_context,
        recent_action = get_recent_action(session)
    }

    -- Render template
    local template_path = type_registry.get_template_path(type_name, "diff")
    local rendered = render_view(template_path, template_data)

    -- Update session context (keep current context for diff)
    -- Don't change navigation context when viewing diff

    return rendered
end

-- Status tool: Application-wide status
local function tool_status(args, session)
    -- Collect global application status
    local status_data = {
        app = "Vah",
        version = "0.1.0",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        mcp_server = "running",
        threads = {}
    }

    -- TODO: Collect status from running threads
    -- For now, return basic status

    -- Build template data
    local template_data = {
        type = "System",
        view = "status",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        data = status_data,
        context = {},
        recent_action = get_recent_action(session)
    }

    -- Render template
    local template_path = type_registry.get_template_path("system", "status")

    -- Fallback to generic status template
    local generic_template = "mcp_views/templates/status.md"
    local content, read_err = fs.read_file(template_path)
    if read_err ~= "" or content == "" then
        template_path = generic_template
    end

    local rendered = render_view(template_path, template_data)

    -- Status doesn't change navigation context
    return rendered
end

-- Register all navigation tools
function M.register(register_fn, registry, update_context)
    type_registry = registry
    update_context_fn = update_context

    -- Build available types list for descriptions
    local available_types = registry.get_all_names()
    local types_list = table.concat(available_types, ", ")
    local types_description = "The data type to list. Available types: " .. types_list

    -- List tool
    register_fn(
        "list",
        "List items of a specific type with pagination",
        {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    description = types_description
                },
                page = {
                    type = "number",
                    description = "Page number (default: 1)"
                },
                limit = {
                    type = "number",
                    description = "Items per page (default: 10)"
                },
                context = {
                    type = "object",
                    description = "Additional context parameters (e.g., directory for files)"
                }
            },
            required = {"type"}
        },
        tool_list
    )

    -- Detail tool
    register_fn(
        "detail",
        "View detailed information about a specific item",
        {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    description = types_description
                },
                id = {
                    type = "string",
                    description = "The item ID or identifier (e.g., file path, database path)"
                },
                context = {
                    type = "object",
                    description = "Additional context parameters"
                }
            },
            required = {"type", "id"}
        },
        tool_detail
    )

    -- Summary tool
    register_fn(
        "summary",
        "View aggregate statistics and summary information",
        {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    description = types_description
                },
                context = {
                    type = "object",
                    description = "Additional context parameters (e.g., directory for files)"
                }
            },
            required = {"type"}
        },
        tool_summary
    )

    -- Search tool
    register_fn(
        "search",
        "Search within a specific data type",
        {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    description = types_description
                },
                query = {
                    type = "string",
                    description = "The search query"
                },
                context = {
                    type = "object",
                    description = "Additional context parameters (e.g., directory for files)"
                }
            },
            required = {"type", "query"}
        },
        tool_search
    )

    -- Diff tool
    register_fn(
        "diff",
        "Compare versions or show changes for an item",
        {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    description = types_description
                },
                id = {
                    type = "string",
                    description = "The item ID or identifier"
                },
                context = {
                    type = "object",
                    description = "Additional context (e.g., version numbers)"
                }
            },
            required = {"type", "id"}
        },
        tool_diff
    )

    -- Status tool
    register_fn(
        "status",
        "Get current system and application status",
        {
            type = "object",
            properties = {}
        },
        tool_status
    )

    print("Navigation tools registered: list, detail, summary, search, diff, status")
end

return M
