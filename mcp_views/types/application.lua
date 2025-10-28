-- Application Type Definition
-- Provides views for running applications and threads

-- Helper to make blocking call from async API
-- This works because the thread's update() loop continues running at 30hz
local function thread_list_sync()
    if not thread or not thread.list then
        return {}  -- API not available
    end

    local result = nil

    thread.list(function(err, response)
        if err then
            result = {error = err, threads = {}}
        else
            result = response
        end
    end)

    -- Busy-wait for response (manually process responses during wait)
    local timeout = 100  -- iterations
    local count = 0
    while result == nil and count < timeout do
        process_responses()  -- Process any pending responses
        sleep(0.001)  -- 1ms
        count = count + 1
    end

    if result == nil then
        return {}  -- Timeout
    end

    -- Convert numeric-keyed table to array
    local threads = result.threads or {}
    local threads_array = {}
    for i = 1, 100 do  -- Assume max 100 threads
        local key = tostring(i)
        if threads[key] then
            table.insert(threads_array, threads[key])
        else
            break  -- No more threads
        end
    end

    return threads_array
end

-- Helper to get info for specific thread
local function thread_get_info_sync(thread_id)
    if not thread or not thread.get_info then
        return nil
    end

    local result = nil

    thread.get_info(tonumber(thread_id), function(err, response)
        if err then
            result = {error = err}
        else
            result = response
        end
    end)

    -- Busy-wait for response
    local timeout = 100
    local count = 0
    while result == nil and count < timeout do
        process_responses()  -- Process any pending responses
        sleep(0.001)
        count = count + 1
    end

    return result
end

return {
    name = "Application",
    plural = "Applications",

    -- Query functions for each view type
    query = {
        -- List all running applications/threads
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            local offset = (page - 1) * limit

            -- Get running threads
            local threads = {}
            local thread_list = thread_list_sync()

            for _, t in ipairs(thread_list) do
                table.insert(threads, {
                    thread_id = tostring(t.thread_id or ""),
                    name = t.script_path and t.script_path:match("([^/\\]+)$") or "Unknown",
                    script_path = t.script_path or "",
                    status = t.status or "running",
                    uptime = math.floor(t.uptime or 0)
                })
            end

            -- Sort by thread_id
            table.sort(threads, function(a, b)
                return tonumber(a.thread_id) < tonumber(b.thread_id)
            end)

            -- Paginate
            local total = #threads
            local total_pages = math.max(1, math.ceil(total / limit))
            local items = {}

            local start_idx = offset + 1
            local end_idx = math.min(offset + limit, total)

            for i = start_idx, end_idx do
                table.insert(items, threads[i])
            end

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit
            }
        end,

        -- View application/thread details
        detail = function(context)
            local thread_id = context.id

            if not thread_id then
                error("Missing thread ID")
            end

            -- Get thread info
            local info = thread_get_info_sync(thread_id)

            if not info or info.error then
                error("Thread not found: " .. thread_id)
            end

            return {
                id = tostring(info.thread_id or thread_id),
                thread_id = tostring(info.thread_id or thread_id),
                name = info.script_path and info.script_path:match("([^/\\]+)$") or "Unknown",
                script_path = info.script_path or "",
                status = info.status or "unknown",
                uptime = math.floor(info.uptime or 0)
            }
        end,

        -- Summary statistics for all applications
        summary = function(context)
            local thread_list = thread_list_sync()

            local total = #thread_list
            local running = 0
            local paused = 0
            local stopped = 0
            local errors = 0

            for _, t in ipairs(thread_list) do
                local status = t.status or "unknown"
                if status == "running" or status == "starting" then
                    running = running + 1
                elseif status == "paused" then
                    paused = paused + 1
                elseif status == "stopped" or status == "stopping" then
                    stopped = stopped + 1
                elseif status == "error" then
                    errors = errors + 1
                end
            end

            return {
                total = total,
                running = running,
                paused = paused,
                stopped = stopped,
                errors = errors
            }
        end,

        -- Search applications by name or path
        search = function(context)
            local query = context.query or ""
            local thread_list = thread_list_sync()

            local results = {}

            for _, t in ipairs(thread_list) do
                local script_path = t.script_path or ""
                local name = script_path:match("([^/\\]+)$") or ""

                if name:lower():find(query:lower(), 1, true) or
                   script_path:lower():find(query:lower(), 1, true) then
                    table.insert(results, {
                        thread_id = tostring(t.thread_id or ""),
                        name = name,
                        script_path = script_path,
                        status = t.status or "unknown",
                        uptime = math.floor(t.uptime or 0)
                    })
                end
            end

            return {
                items = results,
                total = #results,
                query = query
            }
        end,

        -- Diff view (not supported for applications)
        diff = function(context)
            return {
                supported = false,
                message = "Diff view is not supported for applications"
            }
        end,

        -- Status view (overall system status)
        status = function(context)
            local thread_list = thread_list_sync()

            return {
                system_status = "ok",
                total_applications = #thread_list,
                timestamp = os.time()
            }
        end
    },

    -- Action tools (future: start_thread, stop_thread, restart_thread)
    tools = {},

    -- Custom templates (uses generic templates for now)
    templates = {}
}
