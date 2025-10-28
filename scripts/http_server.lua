-- HTTP SSE Server Example
-- Demonstrates streaming events via Server-Sent Events

-- Configuration constants
local SERVER_HOST = "127.0.0.1"
local SERVER_PORT = 8080
local STREAM_EVENT_COUNT = 30  -- Number of events to send in the stream
local STREAM_EVENT_DELAY = 1  -- Seconds between stream events
local UI_STARTUP_DELAY = 0.1  -- Seconds to wait for UI data binding

local server = nil
local message_count = 0
local server_running = false

local server_data = {
    status = "Status: Initializing...",
    messages = 0
}

function update_model()
    data.bind("http_server", {server_data})
end

function startup()
    print("Starting HTTP server...")

    -- Initial bind
    update_model()

    -- Wait briefly for client thread to bind its initial model
    -- (prevents race condition where UI loads before client model exists)
    sleep(UI_STARTUP_DELAY)

    -- Load UI
    ui.load_document("ui/http_demo.rml", true, "http_demo")

    -- Update status before blocking
    server_data.status = "Status: Starting server..."
    update_model()

    -- Create server
    server = HttpServer.new()

    -- Setup SSE endpoint
    server:route("GET", "/events", function(req)
        print("Client connected to SSE stream")

        return {
            status = 200,
            headers = {
                ["Cache-Control"] = "no-cache",
                ["Connection"] = "keep-alive"
            },
            stream = function(send)
                -- Send events with delay
                -- This blocks on the server thread (which is this LuaThread)
                for i = 1, STREAM_EVENT_COUNT do
                    local data = json.encode({
                        count = i,
                        timestamp = os.time(),
                        message = "Event number " .. i
                    })

                    -- send(event_type, data) returns false if connection closed
                    if not send("counter", data) then
                        print("Connection closed, exiting stream")
                        return
                    end

                    message_count = message_count + 1
                    server_data.messages = message_count
                    update_model()

                    -- Sleep between events
                    sleep(STREAM_EVENT_DELAY)
                end

                -- Send completion event
                send("done", json.encode({message = "Stream complete"}))
                print("SSE stream completed")
            end
        }
    end)

    -- Update UI before blocking
    server_data.status = string.format("Status: Listening on http://%s:%d", SERVER_HOST, SERVER_PORT)
    update_model()

    -- Start server (this blocks until server is stopped)
    print("Calling server:listen() - this will block...")
    local success, err = server:listen(SERVER_HOST, SERVER_PORT)

    -- This is only reached when server stops
    print("Server listen() returned: success=" .. tostring(success))

    if success then
        print("Server stopped normally")
    else
        print("Server stopped with error: " .. (err or "unknown"))
    end
end

function update(dt)
    -- Nothing to do in update loop
    -- Server handles requests on its own thread
end

function shutdown()
    print("Shutting down HTTP server...")

    if server then
        server:stop()
        server_running = false
    end

    print("Server stopped")
end
