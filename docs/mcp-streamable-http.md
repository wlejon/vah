# Model Context Protocol (MCP) - Streamable HTTP Transport

## Overview

The Model Context Protocol (MCP) is an open standard for connecting AI models to external tools and data sources. It provides a standardized way for AI systems to interact with external resources in a secure, consistent manner.

MCP uses JSON-RPC 2.0 for all communication and supports multiple transport mechanisms. This document focuses on the **Streamable HTTP transport**, which was introduced in the MCP specification version 2025-03-26 and replaced the deprecated HTTP+SSE transport from protocol version 2024-11-05.

### Key Features

- **Single Endpoint Architecture**: All MCP interactions flow through one HTTP endpoint
- **Bidirectional Communication**: Servers can send notifications and requests back to clients
- **Session Management**: Secure session handling with unique identifiers
- **Connection Resumption**: Ability to resume after broken connections
- **Dynamic Upgrades**: HTTP requests can upgrade to Server-Sent Events (SSE) when streaming is needed

## Protocol Architecture

### Transport Layers

MCP supports multiple transport mechanisms:
- **stdio**: For local server processes (standard input/output)
- **Streamable HTTP**: For remote servers (covered in this document)

The Streamable HTTP transport enables servers to handle multiple client connections independently as separate processes.

### JSON-RPC 2.0 Foundation

MCP is a stateful protocol built on JSON-RPC 2.0. All messages are UTF-8 encoded JSON and can be sent as:
- Single JSON objects
- Batched arrays of JSON objects (except during initialization)

## Message Types

MCP defines three fundamental message types following JSON-RPC 2.0:

### 1. Request Messages

Requests require a response from the receiver.

**Structure:**
```json
{
  "jsonrpc": "2.0",
  "id": "unique-id-123",
  "method": "method_name",
  "params": {}
}
```

**Required Fields:**
- `jsonrpc`: Must be "2.0"
- `id`: Unique identifier (string or number, not null)
- `method`: The method name to invoke

**Optional Fields:**
- `params`: Parameters for the method (object or array)

**Example:**
```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {
      "location": "New York"
    }
  }
}
```

### 2. Response Messages

Responses correspond to requests with matching IDs.

**Success Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "unique-id-123",
  "result": {
    "data": "response data"
  }
}
```

**Error Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "unique-id-123",
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {}
  }
}
```

**Required Fields:**
- `jsonrpc`: Must be "2.0"
- `id`: Same ID as the corresponding request
- Either `result` (for success) OR `error` (for failure), never both

### 3. Notification Messages

Notifications are one-way messages that do not expect a response.

**Structure:**
```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized",
  "params": {}
}
```

**Required Fields:**
- `jsonrpc`: Must be "2.0"
- `method`: The notification method name
- No `id` field (this distinguishes notifications from requests)

**Optional Fields:**
- `params`: Parameters for the notification

## Standard Error Codes

MCP uses standard JSON-RPC error codes:

| Code | Name | Description |
|------|------|-------------|
| -32700 | Parse Error | Invalid JSON received |
| -32600 | Invalid Request | JSON is not a valid Request object |
| -32601 | Method Not Found | Method does not exist or is not available |
| -32602 | Invalid Params | Invalid method parameter(s) |
| -32603 | Internal Error | Internal JSON-RPC error |
| -32000 to -32099 | Server Error | Reserved for implementation-defined server errors |

**MCP-Specific Error Codes:**
- `-32800`: Request cancelled
- `-32801`: Content too large

## Streamable HTTP Transport Specification

### Single Endpoint Design

The server provides ONE HTTP endpoint (the "MCP endpoint") that supports multiple HTTP methods:

- `POST`: Client sends messages to server
- `GET`: Client opens SSE stream for server messages
- `DELETE`: Client terminates session

Example endpoint: `https://example.com/mcp`

### HTTP Methods and Request Patterns

#### POST Request (Client to Server)

Used to send JSON-RPC messages from client to server.

**Headers:**
```
Content-Type: application/json
Accept: application/json, text/event-stream
Mcp-Session-Id: <session-id> (after initialization)
```

**Request Body:**
- Single JSON-RPC message, OR
- Batched array of JSON-RPC messages

**Response Scenarios:**

| Scenario | Status Code | Response Type | Content-Type |
|----------|-------------|---------------|--------------|
| Notifications/responses only | 202 Accepted | No body | - |
| Invalid input | 4xx error | Optional JSON-RPC error | application/json |
| Contains requests (streaming) | 200 OK | SSE stream | text/event-stream |
| Contains requests (immediate) | 200 OK | Single JSON object | application/json |

#### GET Request (Server Listening)

Opens a Server-Sent Events (SSE) stream for receiving server-initiated messages.

**Headers:**
```
Accept: text/event-stream
Mcp-Session-Id: <session-id> (if session exists)
Last-Event-ID: <event-id> (for resuming connections)
```

**Response:**
- `200 OK` with `Content-Type: text/event-stream` (SSE stream)
- `405 Method Not Allowed` if server doesn't support GET

**Purpose:**
- Server sends requests and notifications unrelated to concurrent client requests
- Used for resuming broken connections with message replay

#### DELETE Request (Session Termination)

Explicitly terminates a session.

**Headers:**
```
Mcp-Session-Id: <session-id>
```

**Response:**
- `200 OK` or `204 No Content` on success
- `404 Not Found` if session doesn't exist

### Session Management

#### Session Initialization

During the initialization handshake, the server MAY assign a session ID:

**Server Response Header:**
```
Mcp-Session-Id: <unique-session-id>
```

**Session ID Requirements:**
- Must be globally unique and cryptographically secure
- Examples: UUID, JWT, cryptographic hash
- Must contain only visible ASCII characters (0x21 to 0x7E)

#### Subsequent Requests

If a session ID was provided during initialization:
- Clients MUST include `Mcp-Session-Id` header on all subsequent requests
- Servers MAY reject requests without proper session headers (HTTP 400)

#### Session Termination

**Server-Initiated:**
- Server responds with `404 Not Found` to client requests
- Client MUST initiate a new session if it wishes to continue

**Client-Initiated:**
- Send HTTP DELETE to MCP endpoint with `Mcp-Session-Id` header

### Connection Resumption and Message Replay

MCP supports resuming broken connections to prevent message loss.

#### Event ID Tracking

Servers MAY attach `id` fields to SSE events (per SSE standard):

```
id: event-123
data: {"jsonrpc":"2.0","method":"notification/message","params":{}}

```

**Event ID Requirements:**
- Must be globally unique within a session or per-client basis
- Assigned per-stream to act as a cursor within that stream

#### Reconnection Protocol

When resuming after disconnection:

1. Client issues HTTP GET to MCP endpoint
2. Include `Last-Event-ID` header with last received event ID
3. Server MAY replay messages sent after that event ID
4. Only messages from the same stream are replayed

**Example:**
```
GET /mcp HTTP/1.1
Accept: text/event-stream
Mcp-Session-Id: session-abc-123
Last-Event-ID: event-456
```

### Server-Sent Events (SSE) Stream Behavior

MCP uses SSE for server-to-client message streaming with two distinct patterns:

#### During Request Processing (POST Response)

When a client POST contains requests:

1. Server responds with SSE stream (`Content-Type: text/event-stream`)
2. Stream includes one response per request (may be batched)
3. Server MAY send requests/notifications before responses
4. Stream closes after all responses sent (unless server keeps it open)

**Important:** Stream disconnection does NOT signal request cancellation. Use explicit `CancelledNotification` instead.

#### Listening Stream (GET Request)

When client opens GET stream:

1. Server sends requests and notifications unrelated to concurrent client requests
2. Server MUST NOT send responses unless resuming a previous stream
3. Either party may close the stream at any time

### SSE Message Format

SSE uses UTF-8 text with newline-separated fields:

```
event: message
id: event-123
data: {"jsonrpc":"2.0","method":"notification/progress","params":{}}

```

**Fields:**
- `event`: Event type (optional)
- `id`: Unique event identifier (optional, for resumption)
- `data`: Message payload (typically JSON-RPC message)
- `retry`: Reconnection time in milliseconds (optional)

Each message ends with a blank line.

### Multiple Concurrent Connections

- Clients MAY maintain multiple simultaneous SSE streams
- Each server message routes to only ONE stream
- Server MUST NOT broadcast the same message across multiple streams
- Stream resumability mitigates message loss risks

## Protocol Lifecycle

MCP connections follow a strict three-phase lifecycle:

### 1. Initialization Phase

The initialization phase MUST occur first and involves mutual capability discovery.

#### Step 1: Client Sends Initialize Request

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "roots": {
        "listChanged": true
      },
      "sampling": {}
    },
    "clientInfo": {
      "name": "MyClient",
      "version": "1.0.0"
    }
  }
}
```

**Important Constraints:**
- The initialize request MUST NOT be part of a JSON-RPC batch
- Client SHOULD NOT send other requests (except pings) before receiving the response

#### Step 2: Server Responds

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "logging": {},
      "prompts": {
        "listChanged": true
      },
      "resources": {
        "subscribe": true,
        "listChanged": true
      },
      "tools": {
        "listChanged": true
      }
    },
    "serverInfo": {
      "name": "MyServer",
      "version": "1.0.0"
    },
    "instructions": "Optional usage instructions"
  }
}
```

**Response Headers:**
```
Content-Type: application/json
Mcp-Session-Id: <unique-session-id> (optional)
```

#### Step 3: Client Sends Initialized Notification

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized",
  "params": {}
}
```

**Server Response:**
```
HTTP/1.1 202 Accepted
```

After this notification, the session is ready for normal operations.

### 2. Operation Phase

Normal protocol communication according to negotiated capabilities.

#### Protocol Version Negotiation

- Client requests its supported version in initialize request
- If server supports it, both use that version
- Otherwise, server proposes alternative version it supports
- Client unable to support server's version should disconnect

#### Capability Exchange

Both parties exchange supported capabilities during initialization:

**Client Capabilities:**
- `roots`: Support for listing and monitoring workspace roots
- `sampling`: Support for LLM sampling requests

**Server Capabilities:**
- `logging`: Support for server logging to client
- `prompts`: Support for prompt templates
- `resources`: Support for resources (files, data sources)
- `tools`: Support for executable tools
- `completions`: Support for auto-completion

### 3. Shutdown Phase

Transport-dependent termination:

**For Streamable HTTP:**
- Close associated HTTP connections
- Send DELETE request to terminate session explicitly

**Timeout Handling:**
- Implementations should establish request timeouts
- When exceeded, senders should issue cancellation notifications
- Progress notifications may reset timeout clocks

## Standard MCP Methods

### Discovery Methods

#### tools/list

List all available tools.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "get_weather",
        "description": "Get current weather for a location",
        "inputSchema": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "City name"
            }
          },
          "required": ["location"]
        }
      }
    ]
  }
}
```

#### resources/list

List all available resources.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "resources/list",
  "params": {}
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "resources": [
      {
        "uri": "file:///data/config.json",
        "name": "Configuration",
        "description": "Application configuration",
        "mimeType": "application/json"
      }
    ]
  }
}
```

### Invocation Methods

#### tools/call

Invoke a specific tool.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {
      "location": "New York"
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Current weather in New York: 72°F, Sunny"
      }
    ]
  }
}
```

#### resources/read

Read a specific resource.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "resources/read",
  "params": {
    "uri": "file:///data/config.json"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "contents": [
      {
        "uri": "file:///data/config.json",
        "mimeType": "application/json",
        "text": "{\"setting\":\"value\"}"
      }
    ]
  }
}
```

## Implementation Guide

### Server Implementation in Lua

Here's a conceptual approach for implementing an MCP Streamable HTTP server in Lua:

#### 1. HTTP Server Setup

```lua
-- Pseudo-code for MCP server structure
local mcp_server = {
    endpoint = "/mcp",
    sessions = {},  -- Session storage: { [session_id] = { ... } }
    capabilities = {
        tools = { listChanged = true },
        resources = { subscribe = true, listChanged = true }
    }
}

function mcp_server:generate_session_id()
    -- Generate cryptographically secure UUID or random string
    -- Must contain only ASCII 0x21 to 0x7E
    return generate_uuid()  -- Implementation needed
end

function mcp_server:handle_request(method, path, headers, body)
    if path ~= self.endpoint then
        return 404, "Not Found"
    end

    if method == "POST" then
        return self:handle_post(headers, body)
    elseif method == "GET" then
        return self:handle_get(headers)
    elseif method == "DELETE" then
        return self:handle_delete(headers)
    else
        return 405, "Method Not Allowed"
    end
end
```

#### 2. POST Handler (Client Messages)

```lua
function mcp_server:handle_post(headers, body)
    -- Parse JSON-RPC message
    local message = parse_json(body)
    if not message then
        return 400, json_rpc_error(-32700, "Parse error")
    end

    -- Check session
    local session_id = headers["Mcp-Session-Id"]
    local session = session_id and self.sessions[session_id]

    -- Handle message based on type
    if message.method == "initialize" then
        return self:handle_initialize(message)
    elseif not session and message.method ~= "initialize" then
        return 400, json_rpc_error(-32600, "Not initialized")
    elseif message.id then
        -- Request - needs response
        return self:handle_rpc_request(session, message)
    else
        -- Notification - no response needed
        self:handle_notification(session, message)
        return 202, nil  -- Accepted, no body
    end
end
```

#### 3. Initialize Handler

```lua
function mcp_server:handle_initialize(message)
    local params = message.params

    -- Check protocol version
    local client_version = params.protocolVersion
    local supported_version = "2024-11-05"

    if client_version ~= supported_version then
        return 400, {
            jsonrpc = "2.0",
            id = message.id,
            error = {
                code = -32602,
                message = "Unsupported protocol version"
            }
        }
    end

    -- Create session
    local session_id = self:generate_session_id()
    self.sessions[session_id] = {
        client_capabilities = params.capabilities,
        client_info = params.clientInfo,
        initialized = false
    }

    -- Build response
    local response = {
        jsonrpc = "2.0",
        id = message.id,
        result = {
            protocolVersion = supported_version,
            capabilities = self.capabilities,
            serverInfo = {
                name = "LuaMCPServer",
                version = "1.0.0"
            }
        }
    }

    return 200, response, { ["Mcp-Session-Id"] = session_id }
end
```

#### 4. Notification Handler

```lua
function mcp_server:handle_notification(session, message)
    if message.method == "notifications/initialized" then
        session.initialized = true
        -- Server is now ready for normal operations
    elseif message.method == "notifications/cancelled" then
        local request_id = message.params.requestId
        -- Cancel pending request with this ID
        self:cancel_request(session, request_id)
    end
end
```

#### 5. Request Handler

```lua
function mcp_server:handle_rpc_request(session, message)
    local method = message.method
    local params = message.params or {}

    -- Route to appropriate handler
    if method == "tools/list" then
        return self:list_tools(message.id)
    elseif method == "tools/call" then
        return self:call_tool(message.id, params)
    elseif method == "resources/list" then
        return self:list_resources(message.id)
    elseif method == "resources/read" then
        return self:read_resource(message.id, params)
    else
        return 200, {
            jsonrpc = "2.0",
            id = message.id,
            error = {
                code = -32601,
                message = "Method not found"
            }
        }
    end
end

function mcp_server:list_tools(request_id)
    local response = {
        jsonrpc = "2.0",
        id = request_id,
        result = {
            tools = {
                {
                    name = "example_tool",
                    description = "An example tool",
                    inputSchema = {
                        type = "object",
                        properties = {
                            input = { type = "string" }
                        }
                    }
                }
            }
        }
    }
    return 200, response
end
```

#### 6. SSE Stream Handler (GET)

```lua
function mcp_server:handle_get(headers)
    local session_id = headers["Mcp-Session-Id"]
    local last_event_id = headers["Last-Event-ID"]

    if not session_id then
        return 400, "Missing session ID"
    end

    local session = self.sessions[session_id]
    if not session then
        return 404, "Session not found"
    end

    -- Create SSE stream
    local stream = create_sse_stream()

    -- If resuming, replay messages after last_event_id
    if last_event_id then
        self:replay_events(stream, session, last_event_id)
    end

    -- Keep stream open for server-initiated messages
    session.stream = stream

    return 200, stream, { ["Content-Type"] = "text/event-stream" }
end

function mcp_server:send_sse_event(stream, event_id, data)
    local sse_message = ""
    if event_id then
        sse_message = sse_message .. "id: " .. event_id .. "\n"
    end
    sse_message = sse_message .. "data: " .. encode_json(data) .. "\n\n"
    stream:write(sse_message)
end
```

#### 7. Session Termination (DELETE)

```lua
function mcp_server:handle_delete(headers)
    local session_id = headers["Mcp-Session-Id"]

    if not session_id then
        return 400, "Missing session ID"
    end

    local session = self.sessions[session_id]
    if not session then
        return 404, "Session not found"
    end

    -- Clean up session
    if session.stream then
        session.stream:close()
    end
    self.sessions[session_id] = nil

    return 204, nil  -- No content
end
```

### Client Implementation in Lua

Here's a conceptual approach for implementing an MCP Streamable HTTP client in Lua:

#### 1. Client Structure

```lua
local mcp_client = {
    server_url = nil,
    session_id = nil,
    capabilities = {
        roots = { listChanged = true },
        sampling = {}
    },
    pending_requests = {},  -- { [id] = callback }
    next_id = 1
}

function mcp_client:new(server_url)
    local obj = {
        server_url = server_url,
        session_id = nil,
        pending_requests = {},
        next_id = 1
    }
    setmetatable(obj, { __index = self })
    return obj
end
```

#### 2. Initialize Connection

```lua
function mcp_client:initialize()
    local request = {
        jsonrpc = "2.0",
        id = self:get_next_id(),
        method = "initialize",
        params = {
            protocolVersion = "2024-11-05",
            capabilities = self.capabilities,
            clientInfo = {
                name = "LuaMCPClient",
                version = "1.0.0"
            }
        }
    }

    local status, response, headers = self:http_post(request)

    if status ~= 200 then
        return false, "Initialize failed: " .. status
    end

    if response.error then
        return false, response.error.message
    end

    -- Store session ID if provided
    self.session_id = headers["Mcp-Session-Id"]
    self.server_capabilities = response.result.capabilities

    -- Send initialized notification
    local notification = {
        jsonrpc = "2.0",
        method = "notifications/initialized",
        params = {}
    }

    self:http_post(notification)

    return true
end
```

#### 3. HTTP POST Helper

```lua
function mcp_client:http_post(message)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json, text/event-stream"
    }

    if self.session_id then
        headers["Mcp-Session-Id"] = self.session_id
    end

    local body = encode_json(message)

    -- Use HTTP library to POST
    local response_status, response_body, response_headers =
        http_request("POST", self.server_url, headers, body)

    if response_body and #response_body > 0 then
        local response_data = parse_json(response_body)
        return response_status, response_data, response_headers
    else
        return response_status, nil, response_headers
    end
end
```

#### 4. Request Methods

```lua
function mcp_client:get_next_id()
    local id = self.next_id
    self.next_id = self.next_id + 1
    return id
end

function mcp_client:send_request(method, params, callback)
    local request = {
        jsonrpc = "2.0",
        id = self:get_next_id(),
        method = method,
        params = params or {}
    }

    if callback then
        self.pending_requests[request.id] = callback
    end

    local status, response, headers = self:http_post(request)

    -- Handle immediate response
    if response and response.id == request.id then
        if callback then
            callback(response.error, response.result)
            self.pending_requests[request.id] = nil
        end
        return response.result, response.error
    end

    -- Handle SSE stream response
    if headers["Content-Type"] == "text/event-stream" then
        self:handle_sse_stream(status, response)
    end

    return nil, nil  -- Async, callback will be called
end

function mcp_client:list_tools(callback)
    return self:send_request("tools/list", {}, callback)
end

function mcp_client:call_tool(tool_name, arguments, callback)
    return self:send_request("tools/call", {
        name = tool_name,
        arguments = arguments
    }, callback)
end

function mcp_client:list_resources(callback)
    return self:send_request("resources/list", {}, callback)
end

function mcp_client:read_resource(uri, callback)
    return self:send_request("resources/read", {
        uri = uri
    }, callback)
end
```

#### 5. SSE Stream Handling

```lua
function mcp_client:handle_sse_stream(status, stream)
    -- Read SSE events from stream
    local event_buffer = ""
    local current_event_id = nil

    while true do
        local line = stream:read_line()
        if not line then break end

        if line == "" then
            -- Empty line = end of event
            if #event_buffer > 0 then
                local message = parse_json(event_buffer)
                self:handle_stream_message(message)
                event_buffer = ""
            end
        elseif line:match("^id: ") then
            current_event_id = line:sub(5)
        elseif line:match("^data: ") then
            event_buffer = event_buffer .. line:sub(7)
        end
    end
end

function mcp_client:handle_stream_message(message)
    if message.id then
        -- Response to our request
        local callback = self.pending_requests[message.id]
        if callback then
            callback(message.error, message.result)
            self.pending_requests[message.id] = nil
        end
    elseif message.method then
        -- Server-initiated request or notification
        self:handle_server_message(message)
    end
end
```

#### 6. Listening Stream (GET)

```lua
function mcp_client:open_listening_stream()
    local headers = {
        ["Accept"] = "text/event-stream"
    }

    if self.session_id then
        headers["Mcp-Session-Id"] = self.session_id
    end

    local status, stream = http_get(self.server_url, headers)

    if status ~= 200 then
        return false, "Failed to open stream"
    end

    -- Process stream in background
    self:process_stream_async(stream)

    return true
end
```

#### 7. Connection Resumption

```lua
function mcp_client:resume_connection(last_event_id)
    local headers = {
        ["Accept"] = "text/event-stream",
        ["Mcp-Session-Id"] = self.session_id,
        ["Last-Event-ID"] = last_event_id
    }

    local status, stream = http_get(self.server_url, headers)

    if status == 404 then
        -- Session expired, reinitialize
        return self:initialize()
    end

    if status ~= 200 then
        return false, "Failed to resume"
    end

    self:process_stream_async(stream)
    return true
end
```

#### 8. Cleanup

```lua
function mcp_client:close()
    if not self.session_id then
        return
    end

    local headers = {
        ["Mcp-Session-Id"] = self.session_id
    }

    http_delete(self.server_url, headers)

    self.session_id = nil
    self.pending_requests = {}
end
```

## Security Considerations

### 1. Session Security

- Session IDs MUST be cryptographically secure (UUID, JWT, or cryptographic hash)
- Use HTTPS in production to prevent session hijacking
- Implement session expiration and cleanup
- Validate session IDs on every request

### 2. Origin Validation

- Servers MUST validate the `Origin` header to prevent DNS rebinding attacks
- Reject requests from unexpected origins
- Use CORS policies appropriately

### 3. Local Server Binding

- Local servers should bind to `127.0.0.1` (localhost) instead of `0.0.0.0`
- Prevents external network access to local services
- Use firewall rules for additional protection

### 4. Authentication

- Implement proper authentication for all connections
- Consider using API keys, OAuth tokens, or JWT
- Include authentication tokens in request headers
- Validate on every request

### 5. Input Validation

- Validate all JSON-RPC messages
- Check parameter types and schemas
- Sanitize tool arguments
- Implement rate limiting

### 6. Resource Access Control

- Implement proper access control for resources
- Validate URIs and file paths
- Prevent directory traversal attacks
- Limit resource sizes

## Practical Implementation Tips

### 1. Message Batching

For efficiency, batch multiple messages when possible:

```json
[
  {"jsonrpc":"2.0","id":1,"method":"tools/list"},
  {"jsonrpc":"2.0","id":2,"method":"resources/list"}
]
```

**Important:** Do NOT batch the initialize request.

### 2. Timeout Management

- Set reasonable timeouts for requests (e.g., 30-60 seconds)
- Send progress notifications for long-running operations
- Progress notifications can reset timeout clocks
- Implement absolute maximum timeouts

### 3. Connection Recovery

- Track last received event ID
- Implement automatic reconnection on connection loss
- Use `Last-Event-ID` header to resume
- Handle 404 responses by reinitializing

### 4. Error Handling

- Always check for error responses
- Log errors for debugging
- Provide meaningful error messages
- Handle network failures gracefully

### 5. Testing

Test scenarios to implement:
- Basic initialization handshake
- Request/response cycles
- Notification handling
- Connection interruption and resumption
- Session expiration
- Invalid requests and error cases
- Concurrent requests
- Long-running operations

### 6. Lua-Specific Considerations

When implementing in Lua:

- Use a robust HTTP library (e.g., lua-http, LuaSocket + LuaSec)
- Implement JSON encoding/decoding (e.g., cjson, dkjson)
- Handle UTF-8 properly (Lua strings are byte arrays)
- Consider using LuaJIT for better performance
- Implement coroutines for async operations
- Use proper error handling with pcall/xpcall

### 7. Debugging

Enable debug logging for:
- All HTTP requests/responses
- Message parsing
- Session lifecycle events
- Error conditions
- SSE stream events

## Example Message Flow

Here's a complete example of a typical MCP session:

```
1. Client → Server (POST):
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {"roots": {"listChanged": true}},
    "clientInfo": {"name": "MyClient", "version": "1.0.0"}
  }
}

2. Server → Client (200 OK):
Headers: Mcp-Session-Id: abc-123-def
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {"tools": {"listChanged": true}},
    "serverInfo": {"name": "MyServer", "version": "1.0.0"}
  }
}

3. Client → Server (POST):
Headers: Mcp-Session-Id: abc-123-def
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized",
  "params": {}
}

4. Server → Client (202 Accepted)

5. Client → Server (POST):
Headers: Mcp-Session-Id: abc-123-def
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}

6. Server → Client (200 OK):
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "get_weather",
        "description": "Get weather for location",
        "inputSchema": {
          "type": "object",
          "properties": {"location": {"type": "string"}},
          "required": ["location"]
        }
      }
    ]
  }
}

7. Client → Server (POST):
Headers: Mcp-Session-Id: abc-123-def
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {"location": "New York"}
  }
}

8. Server → Client (200 OK, text/event-stream):
id: evt-1
data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"tok-1","progress":50,"total":100}}

id: evt-2
data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Weather: 72°F, Sunny"}]}}

9. Client → Server (DELETE):
Headers: Mcp-Session-Id: abc-123-def

10. Server → Client (204 No Content)
```

## Summary

The MCP Streamable HTTP transport provides:

1. **Unified Communication**: Single endpoint for all interactions
2. **Bidirectional**: Both client and server can initiate messages
3. **Session Management**: Secure, resumable sessions
4. **Flexible Response**: Immediate JSON or streaming SSE based on needs
5. **Standard Protocol**: Built on JSON-RPC 2.0 and SSE standards
6. **Robust Error Handling**: Standard error codes and graceful degradation

This transport is ideal for remote MCP servers and enables sophisticated AI agent interactions with external tools and data sources in a standardized, secure manner.

## References

- MCP Specification (2025-03-26): https://modelcontextprotocol.io/specification/2025-03-26/basic/transports
- JSON-RPC 2.0 Specification: https://www.jsonrpc.org/specification
- Server-Sent Events Standard: https://html.spec.whatwg.org/multipage/server-sent-events.html
- MCP GitHub Repository: https://github.com/modelcontextprotocol
