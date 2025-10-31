-- HTTP SSE Client Example
-- Demonstrates receiving streaming events

-- Configuration constants
local SERVER_STARTUP_DELAY = 3  -- Seconds to wait for server to start
local SERVER_URL = "http://127.0.0.1:8080/events"

local client_data = {
    status = "Status: Waiting for connection...",
    messages = 0,
    last_event = "None"
}

local message_count = 0

function update_model()
    datamodel.bind_table("http_client", {client_data})
end

function startup()
    print("Starting HTTP client...")

    -- Bind initial model immediately (before server loads UI)
    -- This ensures the client panel renders correctly from the start
    update_model()

    -- Wait for server to start accepting connections
    print(string.format("Waiting %d seconds for server to start...", SERVER_STARTUP_DELAY))
    sleep(SERVER_STARTUP_DELAY)

    client_data.status = "Status: Connecting..."
    update_model()
    print("Client attempting connection...")

    -- Connect to SSE stream
    print("Connecting to " .. SERVER_URL)

    http.get(SERVER_URL, {
        on_event = function(event_type, data)
            message_count = message_count + 1
            client_data.messages = message_count

            if event_type == "counter" then
                local msg = string.format("Count: %d, Message: %s", data.count, data.message)
                client_data.last_event = msg
                update_model()
                print("Received counter event: " .. msg)

            elseif event_type == "done" then
                print("Stream completed: " .. data.message)
                client_data.status = "Status: Stream completed"
                client_data.last_event = "Stream completed!"
                update_model()

            else
                print("Received unknown event type: " .. event_type)
            end
        end,
        on_error = function(err)
            print("Stream error: " .. err)
            client_data.status = "Status: Error - " .. err
            update_model()
        end
    })

    -- This is reached after the stream completes
    print("SSE connection closed")
    client_data.status = "Status: Disconnected"
    update_model()
end

function update(dt)
    -- Nothing to do in update loop
    -- SSE handling happens in startup (blocking)
end

function shutdown()
    print("Shutting down HTTP client...")
end
