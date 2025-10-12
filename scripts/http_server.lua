-- HTTP SSE Server Example
-- Demonstrates streaming events via Server-Sent Events

local server = nil
local message_count = 0
local server_running = false

function startup()
    print("Starting HTTP server...")

    -- Load UI
    ui.load_document("ui/http_demo.rml", true, "http_demo")

    -- Update status before blocking
    ui.set_element_text("server-status", "Status: Starting server...")

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
                for i = 1, 30 do
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
                    ui.set_element_text("server-messages", "Messages sent: " .. message_count)

                    -- Sleep for 1 second
                    sleep(1)
                end

                -- Send completion event
                send("done", json.encode({message = "Stream complete"}))
                print("SSE stream completed")
            end
        }
    end)

    -- Update UI before blocking
    ui.set_element_text("server-status", "Status: Listening on http://127.0.0.1:8080")

    -- Start server (this blocks until server is stopped)
    print("Calling server:listen() - this will block...")
    local success, err = server:listen("127.0.0.1", 8080)

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
