-- MCP Server
-- Model Context Protocol server implementation
-- Provides tools and resources via JSON-RPC 2.0 over HTTP with SSE

local server = nil
local sessions = {}
local next_session_id = 1
local server_status = "stopped"  -- "stopped", "starting", "running", "stopping"

-- Server capabilities
local capabilities = {
    tools = {
        listChanged = true
    }
}

-- Server info
local server_info = {
    name = "VahMCPServer",
    version = "1.0.0"
}

-- Supported protocol version
local PROTOCOL_VERSION = "2024-11-05"

-- MCP endpoint
local MCP_ENDPOINT = "/mcp"

-- Server port
local SERVER_PORT = 8765
local SERVER_HOST = "127.0.0.1"

-- Tool registry
local tools = {}

function update_ui_state()
    -- Determine status color
    local color_map = {
        stopped = "red",
        starting = "yellow",
        running = "green",
        stopping = "yellow"
    }

    local status_color = color_map[server_status] or "red"

    -- Status text for display
    local status_text
    if server_status == "running" then
        status_text = "Running on " .. SERVER_HOST .. ":" .. SERVER_PORT
    elseif server_status == "starting" then
        status_text = "Starting..."
    elseif server_status == "stopping" then
        status_text = "Stopping..."
    else
        status_text = "Stopped"
    end

    -- Send status update to menu (which owns the mcp_status data model)
    event.trigger_global("mcp_status_update", {
        status = server_status,
        status_text = status_text,
        status_color = status_color,
        is_stopped = (server_status == "stopped") and 1 or 0,
        is_running = (server_status == "running") and 1 or 0
    })
end

-- Generate session ID
function generate_session_id()
    local id = "session-" .. next_session_id
    next_session_id = next_session_id + 1
    return id
end

-- Register a tool
function register_tool(name, description, input_schema, handler)
    tools[name] = {
        name = name,
        description = description,
        inputSchema = input_schema,
        handler = handler
    }
    print("Registered MCP tool: " .. name)
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

    -- Create session
    sessions[session_id] = {
        client_capabilities = params.capabilities or {},
        client_info = params.clientInfo or {},
        initialized = false,
        created_at = os.time()
    }

    -- Build response
    return json_rpc_success(message.id, {
        protocolVersion = PROTOCOL_VERSION,
        capabilities = capabilities,
        serverInfo = server_info,
        instructions = "MCP server running in Vah. Use tools/list to see available tools."
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
function handle_tools_list(message)
    local tool_list = {}

    for name, tool in pairs(tools) do
        table.insert(tool_list, {
            name = tool.name,
            description = tool.description,
            inputSchema = tool.inputSchema
        })
    end

    return json_rpc_success(message.id, {
        tools = tool_list
    })
end

-- Handle tools/call request
function handle_tools_call(message)
    local params = message.params or {}
    local tool_name = params.name
    local arguments = params.arguments or {}

    if not tool_name then
        return json_rpc_error(message.id, -32602, "Missing tool name")
    end

    local tool = tools[tool_name]
    if not tool then
        return json_rpc_error(message.id, -32601, "Tool not found: " .. tool_name)
    end

    -- Call tool handler
    local success, result = pcall(tool.handler, arguments)

    if not success then
        return json_rpc_error(message.id, -32603, "Tool execution error: " .. tostring(result))
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

    if method == "tools/list" then
        return handle_tools_list(message)
    elseif method == "tools/call" then
        return handle_tools_call(message)
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
        local response_headers = {
            ["Content-Type"] = "application/json",
            ["Mcp-Session-Id"] = session_id
        }
        return {
            status = 200,
            headers = response_headers,
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
            headers = {},
            body = ""
        }
    end
end

-- Handle MCP DELETE request (session termination)
function handle_mcp_delete(req)
    local session_id = req.headers["mcp-session-id"] or req.headers["Mcp-Session-Id"]

    if not session_id then
        return {
            status = 400,
            headers = {},
            body = "Missing session ID"
        }
    end

    local session = sessions[session_id]
    if not session then
        return {
            status = 404,
            headers = {},
            body = "Session not found"
        }
    end

    -- Remove session
    sessions[session_id] = nil
    print("Session terminated: " .. session_id)

    return {
        status = 204,
        headers = {},
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
    server_status = "starting"
    update_ui_state()

    -- Create server
    server = HttpServer.new()

    -- Setup MCP endpoint
    server:route("POST", MCP_ENDPOINT, handle_mcp_post)
    server:route("DELETE", MCP_ENDPOINT, handle_mcp_delete)

    -- Mark as running before blocking
    server_status = "running"
    update_ui_state()

    print("MCP server listening on " .. SERVER_HOST .. ":" .. SERVER_PORT)

    -- Send notification
    event.trigger_global("notification_success", {
        title = "MCP Server Started",
        message = "Server listening on " .. SERVER_HOST .. ":" .. SERVER_PORT
    })

    -- Start server (this blocks until server is stopped)
    local success, err = server:listen(SERVER_HOST, SERVER_PORT)

    -- This is only reached when server stops
    print("MCP server listen() returned: success=" .. tostring(success))

    if not success and err then
        print("Server error: " .. err)
        event.trigger_global("notification_error", {
            title = "MCP Server Error",
            message = err
        })
    end

    server_status = "stopped"
    update_ui_state()
end

-- Stop the MCP server
function stop_server()
    if server_status ~= "running" then
        print("Server not running")
        return
    end

    print("Stopping MCP server...")
    server_status = "stopping"
    update_ui_state()

    if server then
        server:stop()
    end

    -- Clear sessions
    sessions = {}

    event.trigger_global("notification_info", {
        title = "MCP Server Stopped",
        message = "Server has been shut down"
    })

    server_status = "stopped"
    update_ui_state()
end

-- Register event handlers
function register_events()
    -- Local events (from UI)
    event.register("mcp_start_server", function(payload)
        start_server()
    end)

    event.register("mcp_stop_server", function(payload)
        stop_server()
    end)

    -- Global events
    event.register_global("mcp_start_server", function(payload)
        start_server()
    end)

    event.register_global("mcp_stop_server", function(payload)
        stop_server()
    end)
end

-- Register built-in test tools
function register_builtin_tools()
    -- Simple echo tool
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
        function(args)
            return "Echo: " .. (args.message or "")
        end
    )

    -- Get time tool
    register_tool(
        "get_time",
        "Returns the current server time",
        {
            type = "object",
            properties = {}
        },
        function(args)
            return "Current time: " .. os.date("%Y-%m-%d %H:%M:%S")
        end
    )

    -- Calculator tool
    register_tool(
        "calculate",
        "Performs basic arithmetic calculations",
        {
            type = "object",
            properties = {
                operation = {
                    type = "string",
                    description = "Operation: add, subtract, multiply, divide",
                    enum = {"add", "subtract", "multiply", "divide"}
                },
                a = {
                    type = "number",
                    description = "First operand"
                },
                b = {
                    type = "number",
                    description = "Second operand"
                }
            },
            required = {"operation", "a", "b"}
        },
        function(args)
            local a = tonumber(args.a)
            local b = tonumber(args.b)
            local op = args.operation

            if not a or not b then
                return "Error: Invalid numbers"
            end

            local result
            if op == "add" then
                result = a + b
            elseif op == "subtract" then
                result = a - b
            elseif op == "multiply" then
                result = a * b
            elseif op == "divide" then
                if b == 0 then
                    return "Error: Division by zero"
                end
                result = a / b
            else
                return "Error: Unknown operation"
            end

            return string.format("%s %s %s = %s", tostring(a), op, tostring(b), tostring(result))
        end
    )
end

function startup()
    print("MCP server system starting...")

    -- Register events
    register_events()

    -- Register built-in tools
    register_builtin_tools()

    -- Initialize UI state
    update_ui_state()

    print("MCP server system ready (use start command to launch server)")
end

function update(dt)
    -- Nothing to do in update loop
    -- Server handles requests on its own
end

function shutdown()
    print("MCP server system shutting down...")

    -- Stop server if running
    if server_status == "running" then
        stop_server()
    end

    print("MCP server system shut down")
end

-- Export API for programmatic access
return {
    start = start_server,
    stop = stop_server,
    register_tool = register_tool,
    is_running = function() return server_status == "running" end,
    get_status = function() return server_status end,
    get_url = function() return "http://" .. SERVER_HOST .. ":" .. SERVER_PORT .. MCP_ENDPOINT end
}
