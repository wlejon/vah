-- Streaming Data Generator
-- Continuously generates varied data types and updates the UI in real-time

-- State variables
local frame_count = 0
local message_count = 0
local start_time = os.time()

-- Data generation state
local cpu_load = 45.0
local mem_usage = 60.0
local active_threads = 3
local events = {}

-- Random data generators
local event_types = {"INFO", "WARN", "ERROR", "SUCCESS"}
local event_messages = {
    "Connection established",
    "Data packet received",
    "Cache invalidated",
    "Request processed",
    "Timeout detected",
    "Resource allocated",
    "Task completed",
    "Buffer flushed"
}

local data_sources = {
    "sensor_alpha",
    "sensor_beta",
    "sensor_gamma",
    "node_01",
    "node_02",
    "agent_worker"
}

-- Helper functions
function random_float(min, max)
    return min + (math.random() * (max - min))
end

function random_int(min, max)
    return math.floor(random_float(min, max + 0.999))
end

function random_choice(list)
    return list[random_int(1, #list)]
end

function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

-- Generate a random event
function generate_event()
    local elapsed = os.time() - start_time
    local event_type = random_choice(event_types)
    local message = random_choice(event_messages)
    local source = random_choice(data_sources)

    return {
        timestamp = format_time(elapsed),
        type = event_type,
        message = message,
        source = source
    }
end

-- Update system metrics
function update_metrics()
    message_count = message_count + random_int(1, 10)

    -- Calculate messages per second
    local elapsed = os.time() - start_time
    if elapsed == 0 then elapsed = 1 end
    local rate = math.floor(message_count / elapsed)

    ui.set_element_text("metric_threads", tostring(active_threads))
    ui.set_element_text("metric_rate", tostring(rate))
    ui.set_element_text("metric_total", tostring(message_count))
end

-- Update resource usage with smooth variation
function update_resources()
    -- Simulate CPU load variation (smooth random walk)
    cpu_load = cpu_load + random_float(-5, 5)
    cpu_load = math.max(10, math.min(95, cpu_load))

    -- Simulate memory usage variation
    mem_usage = mem_usage + random_float(-3, 3)
    mem_usage = math.max(20, math.min(90, mem_usage))

    -- Update UI
    ui.set_element_text("cpu_value", string.format("%.1f%%", cpu_load))
    ui.set_element_text("cpu_bar", string.format('<div class="bar-fill" style="width: %.1f%%;"></div>', cpu_load))

    ui.set_element_text("mem_value", string.format("%.1f%%", mem_usage))
    ui.set_element_text("mem_bar", string.format('<div class="bar-fill" style="width: %.1f%%;"></div>', mem_usage))
end

-- Update live data stream
function update_data_stream()
    local rows = ""

    -- Generate 5 data rows with varied content
    for i = 1, 5 do
        local source = random_choice(data_sources)
        local value = random_float(0, 100)
        local timestamp = format_time(os.time() - start_time)
        rows = rows .. string.format('<div class="data-row">[%s] %s: %.2f</div>', timestamp, source, value)
    end

    ui.set_element_text("data_stream", rows)
end

-- Update event log (keep last 10 events)
function update_event_log()
    -- Add new event occasionally (30% chance per frame)
    if math.random() < 0.3 then
        local event = generate_event()
        table.insert(events, 1, event)

        -- Keep only last 10 events
        if #events > 10 then
            table.remove(events)
        end
    end

    -- Build event log HTML
    local log_html = ""
    for _, event in ipairs(events) do
        local status_class = "status-good"
        if event.type == "WARN" then
            status_class = "status-warn"
        elseif event.type == "ERROR" then
            status_class = "status-error"
        end

        log_html = log_html .. string.format(
            '<div class="event-entry"><span class="event-timestamp">[%s]</span> <span class="event-type %s">%s</span> <span>%s from %s</span></div>',
            event.timestamp,
            status_class,
            event.type,
            event.message,
            event.source
        )
    end

    ui.set_element_text("event_log", log_html)
end

-- Occasionally change thread count to simulate activity
function update_thread_count()
    if frame_count % 90 == 0 then  -- Every 3 seconds
        active_threads = random_int(1, 8)
    end
end

-- Startup function
function startup()
    print("Data stream thread started (thread_id: " .. thread_id .. ")")
    math.randomseed(os.time() + thread_id)

    -- Initialize with first event
    table.insert(events, {
        timestamp = "00:00:00",
        type = "INFO",
        message = "Data stream started",
        source = "system"
    })
end

-- Update function (called at 30hz)
function update(dt)
    frame_count = frame_count + 1

    -- Update different components at different rates
    update_metrics()
    update_resources()

    -- Update data stream every 5 frames (~6 times per second)
    if frame_count % 5 == 0 then
        update_data_stream()
    end

    -- Update event log every 15 frames (~2 times per second)
    if frame_count % 15 == 0 then
        update_event_log()
    end

    -- Update thread count occasionally
    update_thread_count()
end

-- Shutdown function
function shutdown()
    print("Data stream thread shutting down")
end
