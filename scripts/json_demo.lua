-- JSON Demo
-- Reads JSON file, parses it, and displays in a visual format

local data = nil

function load_json_data()
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
    data = parsed
    return true
end

function render_projects()
    if not data or not data.projects then
        return ""
    end

    local html = ""

    for _, project in ipairs(data.projects) do
        local status_class = "status-active"
        if project.status == "planned" then
            status_class = "status-planned"
        end

        html = html .. '<div class="project-card">'
        html = html .. string.format('<div class="project-header">')
        html = html .. string.format('<h3>%s</h3>', project.name)
        html = html .. string.format('<span class="project-status %s">%s</span>', status_class, project.status)
        html = html .. '</div>'
        html = html .. string.format('<p class="project-desc">%s</p>', project.description)
        html = html .. '<div class="project-meta">'
        html = html .. string.format('<span class="meta-item">👥 %d members</span>', project.members)

        -- Tags
        local tags_html = ""
        for _, tag in ipairs(project.tags) do
            tags_html = tags_html .. string.format('<span class="tag">%s</span>', tag)
        end
        html = html .. string.format('<div class="tags">%s</div>', tags_html)

        html = html .. '</div>'
        html = html .. '</div>'
    end

    return html
end

function render_statistics()
    if not data or not data.statistics then
        return ""
    end

    local stats = data.statistics
    local html = ""

    html = html .. '<div class="stat-item">'
    html = html .. '<div class="stat-value">' .. stats.total_projects .. '</div>'
    html = html .. '<div class="stat-label">Total Projects</div>'
    html = html .. '</div>'

    html = html .. '<div class="stat-item">'
    html = html .. '<div class="stat-value">' .. stats.active_projects .. '</div>'
    html = html .. '<div class="stat-label">Active</div>'
    html = html .. '</div>'

    html = html .. '<div class="stat-item">'
    html = html .. '<div class="stat-value">' .. stats.total_members .. '</div>'
    html = html .. '<div class="stat-label">Total Members</div>'
    html = html .. '</div>'

    return html
end

function update_display()
    if not data then
        return
    end

    ui.set_element_text("projects_container", render_projects())
    ui.set_element_text("stats_container", render_statistics())

    if data.statistics and data.statistics.last_updated then
        ui.set_element_text("last_updated", "Last updated: " .. data.statistics.last_updated)
    end
end

function startup()
    print("JSON demo started (thread_id: " .. thread_id .. ")")

    -- Load UI
    ui.load_document("ui/json_demo.rml")

    -- Load and parse JSON data
    if load_json_data() then
        -- Display the data
        update_display()
    else
        ui.set_element_text("projects_container", '<div class="error">Failed to load JSON data</div>')
    end
end

function update(dt)
    -- Nothing to update continuously
end

function shutdown()
    print("JSON demo shutting down")
end
