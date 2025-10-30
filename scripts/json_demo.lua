-- JSON Demo
-- Reads JSON file, parses it, and displays in a visual format

function load_and_bind_json()
    -- Read the JSON file
    local json_text, read_error = fs.read_file("data/sample_data.json")
    if read_error ~= "" then
        print("Error reading JSON file: " .. read_error)
        return false
    end

    print("Successfully read JSON file (" .. #json_text .. " bytes)")

    -- Parse JSON
    local parsed, parse_error = json.decode(json_text)
    if parse_error ~= "" then
        print("Error parsing JSON: " .. parse_error)
        return false
    end

    print("Successfully parsed JSON")

    -- Prepare data for binding
    local json_model = {
        stats = {
            total_projects = parsed.statistics and parsed.statistics.total_projects or 0,
            active_projects = parsed.statistics and parsed.statistics.active_projects or 0,
            total_members = parsed.statistics and parsed.statistics.total_members or 0
        },
        projects = parsed.projects or {},
        last_updated = parsed.statistics and parsed.statistics.last_updated or "Unknown"
    }

    -- Bind to data model
    datamodel.bind_table("jsondata", {json_model})
    return true
end

function startup()
    print("JSON demo started (thread_id: " .. thread_id .. ")")

    -- Load and bind JSON data (must happen before loading UI)
    if not load_and_bind_json() then
        print("Failed to load JSON data")
    end

    -- Load UI (will automatically bind to data model)
    ui.load_document("ui/json_demo.rml", true, "json_demo")
end

function update(dt)
    -- Nothing to update continuously
end

function shutdown()
    print("JSON demo shutting down")
end
