-- MCP Client
-- Model Context Protocol client application
-- Connects to MCP server and provides UI for tool interaction

local SERVER_URL = "http://127.0.0.1:8765/mcp"
local session_id = nil
local client_status = "disconnected"  -- "disconnected", "connecting", "connected", "error"
local error_message = ""

-- Combined client data (all in one model to avoid race conditions)
-- Store tools array inside the same model
local client_data = {
    -- Status fields
    status = "disconnected",
    status_text = "Not connected",
    tools_loaded = 0,
    is_connected = 0,
    is_disconnected = 1,
    -- Tool call fields
    selected_tool = "",
    tool_input = "{}",
    result = "",
    is_calling = 0,
    -- Tools array (stored here instead of separate model)
    tools = {}
}

function update_client_data()
    -- Determine status text
    local status_text_map = {
        disconnected = "Not connected",
        connecting = "Connecting to server...",
        connected = "Connected to " .. SERVER_URL,
        error = "Error: " .. error_message
    }

    client_data.status = client_status
    client_data.status_text = status_text_map[client_status] or "Unknown"
    client_data.tools_loaded = #client_data.tools
    client_data.is_connected = (client_status == "connected") and 1 or 0
    client_data.is_disconnected = (client_status == "disconnected") and 1 or 0

    -- Bind tools separately as a table (for data-for iteration)
    data.bind("mcp_tools", client_data.tools)

    -- Bind status fields as object (tools array removed from here)
    local status_data = {
        status = client_data.status,
        status_text = client_data.status_text,
        tools_loaded = client_data.tools_loaded,
        is_connected = client_data.is_connected,
        is_disconnected = client_data.is_disconnected,
        selected_tool = client_data.selected_tool,
        tool_input = client_data.tool_input,
        result = client_data.result,
        is_calling = client_data.is_calling
    }
    data.bind_object("mcp_client_data", status_data)
end

-- Send JSON-RPC request
function send_request(method, params, callback)
    local request = {
        jsonrpc = "2.0",
        id = os.time(),
        method = method,
        params = params or {}
    }

    local headers = {
        ["Content-Type"] = "application/json"
    }

    if session_id then
        headers["Mcp-Session-Id"] = session_id
    end

    local body = json.encode(request)

    print("Sending MCP request: " .. method)

    local response, err = http.post(SERVER_URL, {
        headers = headers,
        body = body,
        timeout = 30
    })

    if err ~= "" then
        print("HTTP error: " .. err)
        if callback then
            callback(nil, err)
        end
        return
    end

    if not response then
        if callback then
            callback(nil, "No response from server")
        end
        return
    end

    -- Parse response
    local success, json_response = pcall(function()
        return json.decode(response.body)
    end)

    if not success or not json_response then
        if callback then
            callback(nil, "Failed to parse response")
        end
        return
    end

    -- Check for error in response
    if json_response.error then
        print("MCP error: " .. json_response.error.message)
        if callback then
            callback(nil, json_response.error.message)
        end
        return
    end

    -- Check for session ID in headers
    if response.headers and response.headers["mcp-session-id"] then
        session_id = response.headers["mcp-session-id"]
        print("Received session ID: " .. session_id)
    elseif response.headers and response.headers["Mcp-Session-Id"] then
        session_id = response.headers["Mcp-Session-Id"]
        print("Received session ID: " .. session_id)
    end

    if callback then
        callback(json_response.result, nil)
    end
end

-- Initialize connection
function connect_to_server()
    print("Connecting to MCP server...")
    client_status = "connecting"
    update_client_data()

    -- Send initialize request
    send_request("initialize", {
        protocolVersion = "2024-11-05",
        capabilities = {
            roots = {
                listChanged = true
            }
        },
        clientInfo = {
            name = "VahMCPClient",
            version = "1.0.0"
        }
    }, function(result, err)
        if err then
            client_status = "error"
            error_message = err
            update_client_data()

            event.trigger_global("notification_error", {
                title = "MCP Connection Failed",
                message = err
            })
            return
        end

        print("Connected to MCP server")
        print("Server: " .. result.serverInfo.name .. " v" .. result.serverInfo.version)

        -- Send initialized notification (no response expected for notifications)
        local notification = {
            jsonrpc = "2.0",
            method = "notifications/initialized",
            params = {}
        }

        local headers = {
            ["Content-Type"] = "application/json",
            ["Mcp-Session-Id"] = session_id
        }

        http.post(SERVER_URL, {
            headers = headers,
            body = json.encode(notification),
            timeout = 5
        })

        client_status = "connected"
        error_message = ""
        update_client_data()

        event.trigger_global("notification_success", {
            title = "MCP Connected",
            message = "Connected to " .. result.serverInfo.name
        })

        -- Load tools
        load_tools()
    end)
end

-- Disconnect from server
function disconnect_from_server()
    print("Disconnecting from MCP server...")

    if session_id then
        -- Send DELETE request to terminate session
        local headers = {
            ["Mcp-Session-Id"] = session_id
        }

        -- Note: http.delete is not implemented, so we'll just clear local state
        -- In a full implementation, we'd send a DELETE request here
    end

    session_id = nil
    client_data.tools = {}
    client_status = "disconnected"
    error_message = ""
    client_data.result = ""

    update_client_data()

    event.trigger_global("notification_info", {
        title = "MCP Disconnected",
        message = "Disconnected from server"
    })
end

-- Load available tools
function load_tools()
    print("Loading tools from MCP server...")

    send_request("tools/list", {}, function(result, err)
        if err then
            print("Failed to load tools: " .. err)
            event.trigger_global("notification_error", {
                title = "Failed to Load Tools",
                message = err
            })
            return
        end

        client_data.tools = result.tools or {}
        print("Loaded " .. #client_data.tools .. " tools")

        update_client_data()
    end)
end

-- Call a tool
function call_tool(tool_name, arguments)
    print("Calling tool: " .. tool_name)

    client_data.is_calling = 1
    client_data.result = "Calling tool..."
    update_client_data()

    -- Update result editor
    ui.set_texteditor_content("result_editor", "Calling tool...")

    send_request("tools/call", {
        name = tool_name,
        arguments = arguments
    }, function(result, err)
        client_data.is_calling = 0

        if err then
            client_data.result = "Error: " .. err
            update_client_data()

            -- Update result editor
            ui.set_texteditor_content("result_editor", "Error: " .. err)

            event.trigger_global("notification_error", {
                title = "Tool Call Failed",
                message = err
            })
            return
        end

        -- Extract text content
        local text_content = ""
        if result.content and type(result.content) == "table" then
            for _, item in ipairs(result.content) do
                if item.type == "text" then
                    text_content = text_content .. item.text
                end
            end
        end

        client_data.result = text_content
        update_client_data()

        -- Update result editor
        ui.set_texteditor_content("result_editor", text_content)

        print("Tool result: " .. text_content)
    end)
end

-- Register event handlers
function register_events()
    -- Connect/disconnect
    event.register("mcp_connect", function(payload)
        connect_to_server()
    end)

    event.register("mcp_disconnect", function(payload)
        disconnect_from_server()
    end)

    -- Reload tools
    event.register("mcp_reload_tools", function(payload)
        if client_status == "connected" then
            load_tools()
        end
    end)

    -- Select tool
    event.register("mcp_select_tool", function(payload)
        if payload.tool_name then
            client_data.selected_tool = payload.tool_name

            -- Find tool to get input schema
            for _, tool in ipairs(client_data.tools) do
                if tool.name == payload.tool_name then
                    -- Generate sample input from schema
                    local sample_input = {}
                    if tool.inputSchema and tool.inputSchema.properties then
                        for prop_name, prop_schema in pairs(tool.inputSchema.properties) do
                            if prop_schema.type == "string" then
                                sample_input[prop_name] = ""
                            elseif prop_schema.type == "number" then
                                sample_input[prop_name] = 0
                            elseif prop_schema.type == "boolean" then
                                sample_input[prop_name] = false
                            end
                        end
                    end

                    client_data.tool_input = json.encode(sample_input)
                    client_data.result = ""
                    break
                end
            end

            update_client_data()
        end
    end)

    -- Handle texteditor modifications
    event.register("tool_input_modified", function(payload)
        client_data.tool_input = payload.content or "{}"
        update_client_data()
    end)

    -- Note: Texteditor keybinding commands (copy, paste, cut, select_all, undo, redo)
    -- are now handled globally in C++ (RmlUiBridge::ProcessKeyboardEvent)
    -- No need to register handlers in each Lua script!

    -- Call tool
    event.register("mcp_call_tool", function(payload)
        if client_data.selected_tool == "" then
            event.trigger_global("notification_warning", {
                title = "No Tool Selected",
                message = "Please select a tool first"
            })
            return
        end

        -- Use stored tool_input instead of payload
        local input_json = client_data.tool_input or "{}"

        -- Parse tool input
        local success, arguments = pcall(function()
            return json.decode(input_json)
        end)

        if not success or not arguments then
            event.trigger_global("notification_error", {
                title = "Invalid Input",
                message = "Tool input must be valid JSON"
            })
            return
        end

        call_tool(client_data.selected_tool, arguments)
    end)
end

function startup()
    print("MCP Client started")

    -- Initialize data model FIRST (single model now)
    update_client_data()

    -- Register events
    register_events()

    -- Load UI
    ui.load_document("ui/mcp_client.rml", true, "mcp_client")

    -- Initialize texteditors
    ui.set_texteditor_content("tool_input_editor", client_data.tool_input)
    ui.set_texteditor_editable("tool_input_editor", true)

    ui.set_texteditor_content("result_editor", "")
    ui.set_texteditor_editable("result_editor", false)

    print("MCP Client ready")
end

function update(dt)
    -- Nothing to do in update loop
end

function shutdown()
    print("MCP Client shutting down")

    -- Disconnect if connected
    if client_status == "connected" then
        disconnect_from_server()
    end
end
