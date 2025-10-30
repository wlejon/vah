-- MCP Server
-- Model Context Protocol server implementation
-- Provides tools and resources via JSON-RPC 2.0 over HTTP
-- Now uses HttpServer directly (runs on Lua thread)

-- Load configuration
local config = require("mcp_config")

-- Configuration constants
local SESSION_TIMEOUT = 3600  -- Session timeout in seconds (1 hour)
local MAX_SESSIONS = 100  -- Maximum number of concurrent sessions
local MAX_RECENT_ACTIONS = 10  -- Maximum number of recent actions to track per session
local SESSION_CLEANUP_INTERVAL = 60  -- Seconds between session cleanup checks

local sessions = {}
local server_status = "stopped"  -- "stopped", "running"
local time_since_cleanup = 0.0  -- Track time since last session cleanup
local http_server = nil  -- HttpServer instance

-- Server capabilities (from config)
local capabilities = config.capabilities

-- Server info (from config)
local server_info = config.info

-- Supported protocol version (from config)
local PROTOCOL_VERSION = config.server.protocol_version

-- Tool definitions (all tools registered upfront)
-- Maps tool_name -> {name, description, inputSchema, handler}
local tool_definitions = {}

-- Type registry (loaded on startup)
local type_registry = nil

function update_ui_state()
    -- Status text for display
    local status_text
    if server_status == "running" then
        status_text = "Running on " .. config.server.host .. ":" .. config.server.port
    elseif server_status == "starting" then
        status_text = "Starting..."
    elseif server_status == "stopping" then
        status_text = "Stopping..."
    else
        status_text = "Stopped"
    end

    -- Send status update to menu
    event.trigger_global("menu_update_status", {
        menu_id = "mcp",
        status = server_status,
        status_text = status_text
    })
end

-- Generate cryptographically random session ID
function generate_session_id()
    local timestamp = os.time()
    local random_part = ""

    -- Generate random hex string (16 characters = 64 bits of randomness)
    for i = 1, 16 do
        random_part = random_part .. string.format("%x", math.random(0, 15))
    end

    return string.format("session-%d-%s", timestamp, random_part)
end

-- Register a tool definition
function register_tool(name, description, input_schema, handler)
    tool_definitions[name] = {
        name = name,
        description = description,
        inputSchema = input_schema,
        handler = handler
    }
    print("Registered MCP tool: " .. name)
end

-- Get all tool definitions as list
function get_all_tools()
    local tool_list = {}
    for _, tool_def in pairs(tool_definitions) do
        table.insert(tool_list, {
            name = tool_def.name,
            description = tool_def.description,
            inputSchema = tool_def.inputSchema
        })
    end
    return tool_list
end

-- Add action to session history
function add_recent_action(session, action_text)
    if not session.recent_actions then
        session.recent_actions = {}
    end

    table.insert(session.recent_actions, {
        action = action_text,
        timestamp = os.time()
    })

    -- Keep only last N actions
    if #session.recent_actions > MAX_RECENT_ACTIONS then
        table.remove(session.recent_actions, 1)
    end

    -- Update last activity timestamp
    session.last_activity = os.time()
end

-- Clean up expired sessions
function cleanup_expired_sessions()
    local current_time = os.time()
    local expired_sessions = {}

    -- Find expired sessions
    for session_id, session in pairs(sessions) do
        local last_activity = session.last_activity or session.created_at
        if current_time - last_activity > SESSION_TIMEOUT then
            table.insert(expired_sessions, session_id)
        end
    end

    -- Remove expired sessions
    for _, session_id in ipairs(expired_sessions) do
        sessions[session_id] = nil
        print("Session expired: " .. session_id)
    end

    if #expired_sessions > 0 then
        print(string.format("Cleaned up %d expired session(s)", #expired_sessions))
    end
end

-- Check if we've reached max sessions limit
function check_session_limit()
    local count = 0
    for _ in pairs(sessions) do
        count = count + 1
    end

    if count >= MAX_SESSIONS then
        -- Clean up expired sessions first
        cleanup_expired_sessions()

        -- Recount
        count = 0
        for _ in pairs(sessions) do
            count = count + 1
        end

        -- If still at limit, remove oldest session
        if count >= MAX_SESSIONS then
            local oldest_id = nil
            local oldest_time = math.huge

            for session_id, session in pairs(sessions) do
                local last_activity = session.last_activity or session.created_at
                if last_activity < oldest_time then
                    oldest_time = last_activity
                    oldest_id = session_id
                end
            end

            if oldest_id then
                sessions[oldest_id] = nil
                print("Removed oldest session to make room: " .. oldest_id)
            end
        end
    end
end

-- JSON-RPC error response
function json_rpc_error(id, code, message, data)
    local response = {
        jsonrpc = "2.0",
        id = id,
        error = {
            code = code,
            message = message
        }
    }

    if data then
        response.error.data = data
    end

    return response
end

-- JSON-RPC success response
function json_rpc_success(id, result)
    return {
        jsonrpc = "2.0",
        id = id,
        result = result
    }
end

-- Handle initialize request
function handle_initialize(message, session_id)
    local params = message.params or {}
    local client_version = params.protocolVersion

    -- Check protocol version
    if client_version ~= PROTOCOL_VERSION then
        return json_rpc_error(
            message.id,
            -32602,
            "Unsupported protocol version. Server supports: " .. PROTOCOL_VERSION
        )
    end

    -- Check session limit before creating new session
    check_session_limit()

    -- Create session
    local current_time = os.time()
    local session = {
        client_capabilities = params.capabilities or {},
        client_info = params.clientInfo or {},
        initialized = false,
        created_at = current_time,
        last_activity = current_time,
        recent_actions = {}
    }

    sessions[session_id] = session

    -- Build response
    return json_rpc_success(message.id, {
        protocolVersion = PROTOCOL_VERSION,
        capabilities = capabilities,
        serverInfo = server_info,
        instructions = "MCP server running in Vah. All tools are available."
    })
end

-- Handle notifications/initialized
function handle_initialized(session)
    if session then
        session.initialized = true
        print("Session initialized")
    end
end

-- Handle tools/list request
function handle_tools_list(message, session)
    if not session then
        -- No session yet, return empty list
        return json_rpc_success(message.id, {tools = {}})
    end

    local tool_list = get_all_tools()

    return json_rpc_success(message.id, {
        tools = tool_list
    })
end

-- Handle tools/call request
function handle_tools_call(message, session)
    local params = message.params or {}
    local tool_name = params.name
    local arguments = params.arguments or {}

    if not tool_name then
        return json_rpc_error(message.id, -32602, "Missing tool name")
    end

    if not session then
        return json_rpc_error(message.id, -32600, "No active session")
    end

    local tool = tool_definitions[tool_name]
    if not tool then
        return json_rpc_error(message.id, -32601, "Tool not found: " .. tool_name)
    end

    -- Call tool handler with session context
    local success, result = pcall(tool.handler, arguments, session)

    if not success then
        -- Include detailed error context in the error response
        return json_rpc_error(message.id, -32603, "Tool execution error", {
            message = tostring(result),
            tool = tool_name,
            arguments = arguments
        })
    end

    return json_rpc_success(message.id, {
        content = {
            {
                type = "text",
                text = result
            }
        }
    })
end

-- Handle JSON-RPC request
function handle_request(message, session)
    local method = message.method

    -- Update session activity
    if session then
        session.last_activity = os.time()
    end

    if method == "tools/list" then
        return handle_tools_list(message, session)
    elseif method == "tools/call" then
        return handle_tools_call(message, session)
    else
        return json_rpc_error(message.id, -32601, "Method not found: " .. method)
    end
end

-- Handle JSON-RPC notification
function handle_notification(message, session)
    local method = message.method

    if method == "notifications/initialized" then
        handle_initialized(session)
    elseif method == "notifications/cancelled" then
        -- Handle cancellation
        print("Request cancelled: " .. tostring(message.params and message.params.requestId))
    end
end

-- Validate JSON-RPC request ID
function validate_request_id(id)
    -- JSON-RPC 2.0 spec: id MUST be a String, Number, or NULL value
    local id_type = type(id)
    return id_type == "string" or id_type == "number" or id == nil
end

-- Handle MCP POST request
function handle_mcp_post(req)
    -- Parse JSON-RPC message
    local message
    local parse_success, parse_error = pcall(function()
        message = json.decode(req.body)
    end)

    if not parse_success or not message then
        local err_response = json_rpc_error(nil, -32700, "Parse error")
        return {
            status = 400,
            headers = {["Content-Type"] = "application/json"},
            body = json.encode(err_response)
        }
    end

    -- Validate request ID if present
    if message.id ~= nil and not validate_request_id(message.id) then
        local err_response = json_rpc_error(nil, -32600, "Invalid Request: ID must be string, number, or null")
        return {
            status = 400,
            headers = {["Content-Type"] = "application/json"},
            body = json.encode(err_response)
        }
    end

    -- Get or create session
    local session_id = req.headers["mcp-session-id"] or req.headers["Mcp-Session-Id"]
    local session = nil
    local is_initialize = (message.method == "initialize")

    if is_initialize then
        -- Generate new session ID for initialize
        session_id = generate_session_id()
    else
        -- Require session for non-initialize requests
        if not session_id then
            local err_response = json_rpc_error(message.id, -32600, "Missing session ID")
            return {
                status = 400,
                headers = {["Content-Type"] = "application/json"},
                body = json.encode(err_response)
            }
        end

        session = sessions[session_id]
        if not session then
            local err_response = json_rpc_error(message.id, -32600, "Invalid session ID")
            return {
                status = 400,
                headers = {["Content-Type"] = "application/json"},
                body = json.encode(err_response)
            }
        end
    end

    -- Handle message based on type
    local response

    if message.method == "initialize" then
        response = handle_initialize(message, session_id)
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "application/json",
                ["Mcp-Session-Id"] = session_id
            },
            body = json.encode(response)
        }
    elseif message.id then
        -- Request - needs response
        response = handle_request(message, session)
        return {
            status = 200,
            headers = {["Content-Type"] = "application/json"},
            body = json.encode(response)
        }
    else
        -- Notification - no response needed
        handle_notification(message, session)
        return {
            status = 202,
            headers = {["Content-Type"] = "application/json"},
            body = ""
        }
    end
end

-- Handle MCP GET request
function handle_mcp_get(req)
    local session_id = req.headers["mcp-session-id"] or req.headers["Mcp-Session-Id"]

    if session_id then
        -- TODO: Implement SSE stream for server-initiated messages
        return {
            status = 501,
            headers = {["Content-Type"] = "text/plain"},
            body = "SSE streaming not yet implemented"
        }
    else
        -- Health check response
        return {
            status = 200,
            headers = {["Content-Type"] = "application/json"},
            body = json.encode({
                name = server_info.name,
                version = server_info.version,
                status = "running"
            })
        }
    end
end

-- Handle MCP DELETE request
function handle_mcp_delete(req)
    local session_id = req.headers["mcp-session-id"] or req.headers["Mcp-Session-Id"]

    if not session_id then
        return {
            status = 400,
            headers = {["Content-Type"] = "text/plain"},
            body = "Missing session ID"
        }
    end

    local session = sessions[session_id]
    if not session then
        return {
            status = 404,
            headers = {["Content-Type"] = "text/plain"},
            body = "Session not found"
        }
    end

    -- Remove session
    sessions[session_id] = nil
    print("Session terminated: " .. session_id)

    return {
        status = 204,
        headers = {["Content-Type"] = "text/plain"},
        body = ""
    }
end

-- Start the MCP server
function start_server()
    if server_status ~= "stopped" then
        print("Server already running or starting")
        return
    end

    print("Starting MCP server...")
    server_status = "running"
    update_ui_state()

    -- Create HTTP server
    print("Creating HttpServer instance...")
    http_server = HttpServer.new()
    print("HttpServer created successfully")

    -- Setup routes
    print("Setting up POST route...")
    http_server:route("POST", "/mcp", handle_mcp_post)
    print("Setting up GET route...")
    http_server:route("GET", "/mcp", handle_mcp_get)
    print("Setting up DELETE route...")
    http_server:route("DELETE", "/mcp", handle_mcp_delete)

    print("MCP server configured, starting to listen on " .. config.server.host .. ":" .. config.server.port)

    -- Send notification
    event.trigger_global("notification_success", {
        title = "MCP Server Starting",
        message = "Server will listen on " .. config.server.host .. ":" .. config.server.port
    })

    -- This blocks the Lua thread (intentional)
    local success, err = http_server:listen(config.server.host, config.server.port)

    if not success then
        print("Failed to start MCP server: " .. (err or "unknown error"))
        server_status = "stopped"
        update_ui_state()

        event.trigger_global("notification_error", {
            title = "MCP Server Failed",
            message = "Failed to start: " .. (err or "unknown error")
        })
    else
        print("MCP server stopped normally")
        server_status = "stopped"
        update_ui_state()
    end
end

-- Stop the MCP server
function stop_server()
    if server_status ~= "running" then
        print("Server not running")
        return
    end

    print("Stopping MCP server...")

    if http_server then
        http_server:stop()
    end

    -- Note: server_status will be set to "stopped" when listen() returns

    -- Clear sessions
    sessions = {}

    event.trigger_global("notification_info", {
        title = "MCP Server Stopped",
        message = "Server has been shut down"
    })
end

-- Register event handlers for menu
function register_events()
    -- Local events (from UI)
    event.register("mcp_start_server", function(payload)
        local success, err = pcall(start_server)
        if not success then
            print("ERROR starting MCP server: " .. tostring(err))
        end
    end)

    event.register("mcp_stop_server", function(payload)
        local success, err = pcall(stop_server)
        if not success then
            print("ERROR stopping MCP server: " .. tostring(err))
        end
    end)

    -- Global events
    event.register_global("mcp_start_server", function(payload)
        local success, err = pcall(start_server)
        if not success then
            print("ERROR starting MCP server (global): " .. tostring(err))
        end
    end)

    event.register_global("mcp_stop_server", function(payload)
        local success, err = pcall(stop_server)
        if not success then
            print("ERROR stopping MCP server (global): " .. tostring(err))
        end
    end)
end

-- Register built-in test tools
function register_builtin_tools()
    -- Simple echo tool (for testing)
    register_tool(
        "echo",
        "Echoes back the input message",
        {
            type = "object",
            properties = {
                message = {
                    type = "string",
                    description = "The message to echo"
                }
            },
            required = {"message"}
        },
        function(args, session)
            return "Echo: " .. (args.message or "")
        end
    )

    -- Get time tool (for testing)
    register_tool(
        "get_time",
        "Returns the current server time",
        {
            type = "object",
            properties = {}
        },
        function(args, session)
            return "Current time: " .. os.date("%Y-%m-%d %H:%M:%S")
        end
    )
end

function startup()
    print("MCP server system starting...")

    -- Load type registry
    type_registry = require("mcp_type_registry")
    type_registry.init(config.type_registry)
    print("Type registry initialized")

    -- Register all tools upfront (no session-based filtering)
    -- Load navigation tools
    local navigation = require(config.navigation_tools)
    navigation.register(register_tool, type_registry, nil)  -- No update_context needed
    print("Navigation tools registered")

    -- Register type-specific action tools
    for _, type_name in ipairs(type_registry.get_all_names()) do
        local type_def = type_registry.get(type_name)
        if type_def and type_def.tools then
            for _, tool in ipairs(type_def.tools) do
                register_tool(tool.name, tool.description, tool.inputSchema, tool.handler)
            end
        end
    end

    -- Register events
    register_events()

    -- Register built-in test tools (temporary, for backward compatibility)
    register_builtin_tools()

    print("MCP server system ready (use start command to launch server)")
end

function update(dt)
    -- Periodically clean up expired sessions
    if server_status == "running" then
        time_since_cleanup = time_since_cleanup + dt
        if time_since_cleanup >= SESSION_CLEANUP_INTERVAL then
            cleanup_expired_sessions()
            time_since_cleanup = 0.0
        end
    end
end

function shutdown()
    print("MCP server system shutting down...")

    -- Stop server if running
    if server_status == "running" then
        stop_server()
    end

    print("MCP server system shut down")
end

-- Called when menu system is ready
function menu_ready()
    -- Register MCP menu with status indicator
    event.trigger_global("menu_register", {
        menu_id = "mcp",
        label = "MCP",
        position = 2,
        status_indicator = true,
        items = {
            {item_id = "start", label = "Start Server", action = "mcp_start_server", show_when_status = "stopped"},
            {item_id = "stop", label = "Stop Server", action = "mcp_stop_server", show_when_status = "running"}
        }
    })

    -- Send initial status
    update_ui_state()
end

-- Export API for programmatic access
return {
    start = start_server,
    stop = stop_server,
    register_tool = register_tool,
    is_running = function() return server_status == "running" end,
    get_status = function() return server_status end,
    get_url = function() return "http://" .. config.server.host .. ":" .. config.server.port .. "/mcp" end
}
