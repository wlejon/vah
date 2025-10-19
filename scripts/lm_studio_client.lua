-- LM Studio Client
-- Comprehensive client for LM Studio's OpenAI-compatible API
-- Server: http://127.0.0.1:1234
-- Default model: openai/gpt-oss-20b

local LMStudioClient = {}
LMStudioClient.__index = LMStudioClient

-- Create a new LM Studio client
-- @param base_url (optional) Base URL for LM Studio server (default: http://127.0.0.1:1234)
-- @param model (optional) Model to use (default: openai/gpt-oss-20b)
function LMStudioClient.new(base_url, model)
    local self = setmetatable({}, LMStudioClient)
    self.base_url = base_url or "http://127.0.0.1:1234"
    self.model = model or "openai/gpt-oss-20b"
    self.default_timeout = 300  -- 5 minutes for long responses
    return self
end

-- Make a chat completion request (non-streaming)
-- @param messages Array of message objects with {role, content}
-- @param options (optional) Table with:
--   - temperature (number): Sampling temperature (0-2, default 0.7)
--   - max_tokens (number): Maximum tokens to generate
--   - top_p (number): Nucleus sampling (0-1, default 1.0)
--   - frequency_penalty (number): Frequency penalty (0-2, default 0)
--   - presence_penalty (number): Presence penalty (0-2, default 0)
--   - stop (string or array): Stop sequences
--   - timeout (number): Request timeout in seconds
-- @return response, error
function LMStudioClient:chat(messages, options)
    options = options or {}

    -- Build request body
    local request_body = {
        model = self.model,
        messages = messages,
        stream = false
    }

    -- Add optional parameters
    if options.temperature then
        request_body.temperature = options.temperature
    end
    if options.max_tokens then
        request_body.max_tokens = options.max_tokens
    end
    if options.top_p then
        request_body.top_p = options.top_p
    end
    if options.frequency_penalty then
        request_body.frequency_penalty = options.frequency_penalty
    end
    if options.presence_penalty then
        request_body.presence_penalty = options.presence_penalty
    end
    if options.stop then
        request_body.stop = options.stop
    end

    -- Encode request as JSON
    local request_json = json.encode(request_body)

    -- Make POST request
    local response, error = http.post(self.base_url .. "/v1/chat/completions", {
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = request_json,
        timeout = options.timeout or self.default_timeout
    })

    if error and error ~= "" then
        return nil, error
    end

    if not response then
        return nil, "No response from server"
    end

    -- Check status code
    if response.status ~= 200 then
        return nil, "HTTP error: " .. response.status .. " - " .. (response.body or "")
    end

    -- Parse response JSON
    local success, parsed = pcall(json.decode, response.body)
    if not success then
        return nil, "Failed to parse response JSON: " .. tostring(parsed)
    end

    return parsed, nil
end

-- Make a streaming chat completion request
-- @param messages Array of message objects with {role, content}
-- @param callbacks Table with:
--   - on_chunk (required): function(delta_content, finish_reason) - called for each content chunk
--   - on_error (optional): function(error_message) - called on error
--   - on_done (optional): function() - called when stream completes
-- @param options (optional) Same as chat() options
-- @return error (nil on success)
function LMStudioClient:chat_stream(messages, callbacks, options)
    if not callbacks or not callbacks.on_chunk then
        return "on_chunk callback is required for streaming"
    end

    options = options or {}

    -- Build request body
    local request_body = {
        model = self.model,
        messages = messages,
        stream = true
    }

    -- Add optional parameters
    if options.temperature then
        request_body.temperature = options.temperature
    end
    if options.max_tokens then
        request_body.max_tokens = options.max_tokens
    end
    if options.top_p then
        request_body.top_p = options.top_p
    end
    if options.frequency_penalty then
        request_body.frequency_penalty = options.frequency_penalty
    end
    if options.presence_penalty then
        request_body.presence_penalty = options.presence_penalty
    end
    if options.stop then
        request_body.stop = options.stop
    end

    -- Encode request as JSON
    local request_json = json.encode(request_body)

    -- Buffer for accumulating incomplete SSE data
    local buffer = ""

    -- Make streaming POST request
    http.post(self.base_url .. "/v1/chat/completions", {
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "text/event-stream"
        },
        body = request_json,
        timeout = options.timeout or self.default_timeout,
        on_event = function(event_type, data)
            if event_type == "message" or event_type == "data" then
                -- The C++ HttpBindings already parses JSON for us, so data is a table
                if type(data) == "table" then
                    -- Data is already parsed as a Lua table
                    if data.choices and data.choices[1] then
                        local delta = data.choices[1].delta
                        local finish_reason = data.choices[1].finish_reason

                        if delta and delta.content then
                            callbacks.on_chunk(delta.content, finish_reason)
                        elseif finish_reason then
                            callbacks.on_chunk("", finish_reason)
                        end
                    end
                elseif type(data) == "string" then
                    -- Fallback: data is a string (e.g., "[DONE]")
                    if data == "[DONE]" then
                        if callbacks.on_done then
                            callbacks.on_done()
                        end
                        return
                    end

                    -- Try to parse as JSON
                    local success, chunk = pcall(json.decode, data)
                    if success and chunk.choices and chunk.choices[1] then
                        local delta = chunk.choices[1].delta
                        local finish_reason = chunk.choices[1].finish_reason

                        if delta and delta.content then
                            callbacks.on_chunk(delta.content, finish_reason)
                        elseif finish_reason then
                            callbacks.on_chunk("", finish_reason)
                        end
                    end
                end
            end
        end,
        on_error = function(error_message)
            if callbacks.on_error then
                callbacks.on_error(error_message)
            end
        end
    })

    return nil
end

-- Get list of available models
-- @return models, error - Array of model objects or nil and error
function LMStudioClient:list_models()
    local response, error = http.get(self.base_url .. "/v1/models", {
        timeout = 10
    })

    if error and error ~= "" then
        return nil, error
    end

    if not response then
        return nil, "No response from server"
    end

    if response.status ~= 200 then
        return nil, "HTTP error: " .. response.status
    end

    local success, parsed = pcall(json.decode, response.body)
    if not success then
        return nil, "Failed to parse response JSON: " .. tostring(parsed)
    end

    return parsed.data, nil
end

-- Get information about a specific model
-- @param model_id Model identifier (default: uses client's default model)
-- @return model_info, error
function LMStudioClient:get_model(model_id)
    model_id = model_id or self.model

    local response, error = http.get(self.base_url .. "/v1/models/" .. model_id, {
        timeout = 10
    })

    if error and error ~= "" then
        return nil, error
    end

    if not response then
        return nil, "No response from server"
    end

    if response.status ~= 200 then
        return nil, "HTTP error: " .. response.status
    end

    local success, parsed = pcall(json.decode, response.body)
    if not success then
        return nil, "Failed to parse response JSON: " .. tostring(parsed)
    end

    return parsed, nil
end

-- Create a simple completion (text generation)
-- @param prompt The text prompt
-- @param options (optional) Same options as chat()
-- @return response, error
function LMStudioClient:complete(prompt, options)
    -- Convert simple prompt to chat format
    local messages = {
        {role = "user", content = prompt}
    }
    return self:chat(messages, options)
end

-- Create a streaming completion (text generation)
-- @param prompt The text prompt
-- @param callbacks Same callbacks as chat_stream()
-- @param options (optional) Same options as chat()
-- @return error
function LMStudioClient:complete_stream(prompt, callbacks, options)
    -- Convert simple prompt to chat format
    local messages = {
        {role = "user", content = prompt}
    }
    return self:chat_stream(messages, callbacks, options)
end

-- Health check - verify the server is running and accessible
-- @return is_healthy, error
function LMStudioClient:health_check()
    local response, error = http.get(self.base_url .. "/v1/models", {
        timeout = 5
    })

    if error and error ~= "" then
        return false, error
    end

    if not response then
        return false, "No response from server"
    end

    return response.status == 200, nil
end

-- Export the module
return LMStudioClient
