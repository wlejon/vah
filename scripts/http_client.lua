-- HTTP SSE Client Example
-- Demonstrates receiving streaming events

local message_count = 0
local last_event_data = ""

function startup()
    print("Starting HTTP client...")

    -- Wait for server to start accepting connections
    print("Waiting 3 seconds for server to start...")
    sleep(3)

    ui.set_element_text("client-status", "Status: Connecting...")
    print("Client attempting connection...")

    -- Connect to SSE stream
    print("Connecting to http://127.0.0.1:8080/events")

    http.get("http://127.0.0.1:8080/events", {
        on_event = function(event_type, data)
            message_count = message_count + 1

            -- Update UI with event information
            ui.set_element_text("client-messages", "Messages received: " .. message_count)

            if event_type == "counter" then
                -- data is a table (parsed from JSON)
                local msg = string.format("Count: %d, Message: %s", data.count, data.message)
                last_event_data = msg
                ui.set_element_text("client-last-event", "Last event: " .. msg)
                print("Received counter event: " .. msg)

            elseif event_type == "done" then
                print("Stream completed: " .. data.message)
                ui.set_element_text("client-status", "Status: Stream completed")
                ui.set_element_text("client-last-event", "Stream completed!")

            else
                print("Received unknown event type: " .. event_type)
            end
        end,
        on_error = function(err)
            print("Stream error: " .. err)
            ui.set_element_text("client-status", "Status: Error - " .. err)
        end
    })

    -- This is reached after the stream completes
    print("SSE connection closed")
    ui.set_element_text("client-status", "Status: Disconnected")
end

function update(dt)
    -- Nothing to do in update loop
    -- SSE handling happens in startup (blocking)
end

function shutdown()
    print("Shutting down HTTP client...")
end
