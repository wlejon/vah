-- Simple Chat Interface
-- A basic chat UI that uses the LM Studio client
-- Each message will eventually be represented as a node in the workflow

local LMStudioClient = require("lm_studio_client")
local markdown_parser = require("markdown_parser")

-- Create LM Studio client
local client = LMStudioClient.new("http://127.0.0.1:1234", "openai/gpt-oss-20b")

-- Chat state
local chat_state = {
    messages = {},          -- Array of {role, content, timestamp}
    is_streaming = false,   -- Whether we're currently receiving a response
    current_response = "",  -- Accumulator for streaming response
    status = "Ready",       -- Status message
    server_healthy = false  -- Whether LM Studio is responding
}

-- Bind initial state
function update_ui()
    data.bind("chat", {chat_state})
end

-- Add a message to the chat
function add_message(role, content, is_markdown)
    local message = {
        role = role,
        content = content,
        content_rml = is_markdown and markdown_parser.to_rml(content) or content,
        timestamp = os.time()
    }
    table.insert(chat_state.messages, message)
    update_ui()
end

-- Send a message to the LLM
function send_message_text(user_input)
    if not user_input or user_input == "" then
        return
    end

    -- Add user message to chat
    add_message("user", user_input)

    -- Clear input and update UI
    chat_state.is_streaming = true
    chat_state.current_response = ""
    chat_state.status = "Thinking..."
    update_ui()

    -- Build messages array for API call
    local messages = {
        {role = "system", content = "You are a helpful assistant."}
    }

    -- Add chat history (last 10 messages for context)
    local start_index = math.max(1, #chat_state.messages - 10)
    for i = start_index, #chat_state.messages do
        local msg = chat_state.messages[i]
        table.insert(messages, {
            role = msg.role,
            content = msg.content
        })
    end

    -- Send streaming request
    local accumulated = ""

    local error = client:chat_stream(messages, {
        on_chunk = function(content, finish_reason)
            if content and content ~= "" then
                accumulated = accumulated .. content

                -- Convert accumulated markdown to RML for real-time display
                local success, rml = pcall(markdown_parser.to_rml, accumulated)
                if success then
                    chat_state.current_response = rml
                    update_ui()
                else
                    print("Error parsing markdown: " .. tostring(rml))
                    -- Fallback to plain text
                    chat_state.current_response = accumulated
                    update_ui()
                end
            end

            if finish_reason then
                -- Add assistant message to chat (with markdown flag)
                if accumulated ~= "" then
                    add_message("assistant", accumulated, true)
                end

                chat_state.is_streaming = false
                chat_state.current_response = ""
                chat_state.status = chat_state.server_healthy and "Ready" or "Error - LM Studio not available"
                update_ui()
            end
        end,
        on_error = function(error_message)
            print("Chat error: " .. error_message)
            add_message("system", "Error: " .. error_message)

            chat_state.is_streaming = false
            chat_state.current_response = ""
            chat_state.status = "Error"
            update_ui()
        end,
        on_done = function()
            print("Stream completed successfully")
        end
    }, {
        temperature = 0.7,
        max_tokens = 1000
    })

    if error then
        print("Failed to start stream: " .. error)
        add_message("system", "Failed to send message: " .. error)
        chat_state.is_streaming = false
        chat_state.status = "Error"
        update_ui()
    end
end

-- Event handlers called from UI via emit()
local function on_send_message(payload)
    -- The text is passed from the RML inline script
    local input = payload.text or ""

    if input ~= "" then
        send_message_text(input)
    end
end

local function on_clear_chat(payload)
    chat_state.messages = {}
    chat_state.current_response = ""
    chat_state.is_streaming = false
    chat_state.status = chat_state.server_healthy and "Ready" or "Error - LM Studio not available"
    update_ui()
end

function startup()
    print("chat starting...")

    -- Initialize UI first
    update_ui()

    -- Check server health
    chat_state.status = "Checking LM Studio connection..."
    update_ui()

    local is_healthy, error = client:health_check()
    if is_healthy then
        print("LM Studio server is healthy")
        chat_state.server_healthy = true
        chat_state.status = "Ready - Connected to LM Studio"
        add_message("system", "Connected to LM Studio. Start chatting!")
    else
        print("LM Studio server is not responding: " .. (error or "unknown error"))
        chat_state.server_healthy = false
        chat_state.status = "Error - LM Studio not available"
        add_message("system", "Could not connect to LM Studio: " .. (error or "unknown error"))
        add_message("system", "Please ensure LM Studio is running at http://127.0.0.1:1234")
    end

    update_ui()

    -- Register event handlers
    event.register("send_message", on_send_message)
    event.register("clear_chat", on_clear_chat)

    -- Load the UI
    ui.load_document("ui/chat.rml", true, "chat")

    print("Chat ready")
end

function update(dt)
    -- Nothing needed - all updates are event-driven
end

function shutdown()
    -- no shutdown needed
end
