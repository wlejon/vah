-- View Generator
-- Generate views by configuring templates and binding data (no hardcoded RML strings)

local ViewGenerator = {}

-- Replace placeholders in template content
local function apply_template_substitutions(content, substitutions)
    for key, value in pairs(substitutions) do
        content = content:gsub("{" .. key .. "}", value)
    end
    return content
end

-- Generate a table view using template
local function generate_table_view(data_source, layout_prefs)
    local table_name = data_source.table
    local columns = data_source.columns or {}
    local db_path = data_source.db_path or "data.db"

    -- Read template
    local template_content, err = fs.read_file("ui/templates/table_view.rml")
    if not template_content then
        return nil, "Failed to read template: " .. (err or "unknown error")
    end

    -- Build table headers
    local headers = {}
    for _, col in ipairs(columns) do
        table.insert(headers, string.format("<th>%s</th>", col))
    end

    -- Build table cells
    local cells = {}
    for _, col in ipairs(columns) do
        table.insert(cells, string.format("<td>{{row.%s}}</td>", col))
    end

    -- Apply substitutions to template
    local rml = apply_template_substitutions(template_content, {
        title = table_name,
        model_name = table_name,
        table_headers = table.concat(headers, "\n                    "),
        table_cells = table.concat(cells, "\n                    ")
    })

    -- Generate Lua loader script (just data binding, no markup)
    local lua_script = string.format([[-- View loader for %s
-- Queries database and binds data to template

function startup()
    print("Loading %s view")

    -- Query data from database
    local db = sqlite.open("%s")
    if not db then
        print("Failed to open database")
        return
    end

    -- Get data
    local query = "SELECT %s FROM %s LIMIT 100"
    local rows, err = db:query(query)
    if not rows then
        print("Query failed: " .. (err or "unknown"))
        db:close()
        return
    end

    -- Get row count
    local count_query = "SELECT COUNT(*) as count FROM %s"
    local count_result, _ = db:query(count_query)
    local row_count = 0
    if count_result and count_result[1] then
        row_count = count_result[1].count
    end

    db:close()

    -- Bind data to view (template handles rendering)
    data.bind("%s_data", rows)
    data.bind_object("%s_stats", {row_count = row_count})

    -- Load view
    ui.load_document("ui/generated/%s_view.rml", true)

    print("%s view loaded: " .. #rows .. " rows")
end

function update(dt)
    -- Periodic refresh could go here
end

function shutdown()
    print("%s view closed")
end
]], table_name, table_name, db_path, table.concat(columns, ", "), table_name,
    table_name, table_name, table_name, table_name, table_name, table_name)

    return {rml = rml, lua = lua_script}
end

-- Generate a list view using template
local function generate_list_view(data_source, layout_prefs)
    local table_name = data_source.table
    local display_field = data_source.columns[1] or "name"
    local id_field = "id"

    -- Read template
    local template_content, err = fs.read_file("ui/templates/list_view.rml")
    if not template_content then
        return nil, "Failed to read template: " .. (err or "unknown error")
    end

    -- Apply substitutions
    local rml = apply_template_substitutions(template_content, {
        title = table_name .. " List",
        model_name = table_name,
        display_field = display_field,
        id_field = id_field
    })

    -- Generate minimal Lua script
    local lua_script = string.format([[-- List view loader for %s

function startup()
    local db = sqlite.open("%s")
    if not db then
        print("Failed to open database")
        return
    end

    local rows, _ = db:query("SELECT * FROM %s LIMIT 100")
    db:close()

    if rows then
        data.bind("%s_data", rows)
        ui.load_document("ui/generated/%s_list.rml", true)
    end
end

function update(dt) end
function shutdown() end
]], table_name, data_source.db_path or "data.db", table_name, table_name, table_name)

    return {rml = rml, lua = lua_script}
end

-- Generate a detail view using template
local function generate_detail_view(data_source, layout_prefs)
    local table_name = data_source.table
    local columns = data_source.columns or {}

    -- Read template
    local template_content, err = fs.read_file("ui/templates/detail_view.rml")
    if not template_content then
        return nil, "Failed to read template: " .. (err or "unknown error")
    end

    -- Build detail fields
    local fields = {}
    for _, col in ipairs(columns) do
        table.insert(fields, string.format([[
            <div class="detail-field">
                <div class="field-label">%s:</div>
                <div class="field-value">{{item.%s}}</div>
            </div>]], col, col))
    end

    -- Apply substitutions
    local rml = apply_template_substitutions(template_content, {
        title = table_name .. " Detail",
        model_name = table_name,
        detail_fields = table.concat(fields, "\n            ")
    })

    -- Generate minimal Lua script
    local lua_script = string.format([[-- Detail view loader for %s

function startup()
    local db = sqlite.open("%s")
    if not db then
        print("Failed to open database")
        return
    end

    local rows, _ = db:query("SELECT * FROM %s LIMIT 1")
    db:close()

    if rows and #rows > 0 then
        data.bind("%s_detail", rows)
        ui.load_document("ui/generated/%s_detail.rml", true)
    end
end

function update(dt) end
function shutdown() end
]], table_name, data_source.db_path or "data.db", table_name, table_name, table_name)

    return {rml = rml, lua = lua_script}
end

-- Generate a dashboard view using template
local function generate_dashboard_view(data_source, layout_prefs)
    local table_name = data_source.table

    -- Read template
    local template_content, err = fs.read_file("ui/templates/dashboard_view.rml")
    if not template_content then
        return nil, "Failed to read template: " .. (err or "unknown error")
    end

    -- Apply substitutions
    local rml = apply_template_substitutions(template_content, {
        title = table_name .. " Dashboard"
    })

    -- Generate Lua script that calculates statistics
    local lua_script = string.format([[-- Dashboard view for %s

function startup()
    local db = sqlite.open("%s")
    if not db then
        print("Failed to open database")
        return
    end

    -- Calculate statistics
    local stats = {}

    -- Total rows
    local count_result, _ = db:query("SELECT COUNT(*) as count FROM %s")
    if count_result and count_result[1] then
        table.insert(stats, {
            label = "Total Records",
            value = tostring(count_result[1].count)
        })
    end

    -- Add more statistics as needed
    -- Example: SELECT COUNT(DISTINCT column) for other metrics

    db:close()

    -- Bind statistics to view
    data.bind("dashboard_stats", stats)
    ui.load_document("ui/generated/%s_dashboard.rml", true)
end

function update(dt) end
function shutdown() end
]], table_name, data_source.db_path or "data.db", table_name, table_name)

    return {rml = rml, lua = lua_script}
end

-- Main view generation function
function ViewGenerator.generate_view(view_type, data_source, layout_prefs)
    layout_prefs = layout_prefs or {}

    local generated, error_msg

    if view_type == "table" then
        generated, error_msg = generate_table_view(data_source, layout_prefs)
    elseif view_type == "list" then
        generated, error_msg = generate_list_view(data_source, layout_prefs)
    elseif view_type == "detail" then
        generated, error_msg = generate_detail_view(data_source, layout_prefs)
    elseif view_type == "dashboard" then
        generated, error_msg = generate_dashboard_view(data_source, layout_prefs)
    else
        return {
            error = "Unknown view type: " .. view_type,
            supported_types = {"table", "list", "detail", "dashboard"}
        }
    end

    if not generated then
        return {
            error = error_msg or "Failed to generate view",
            supported_types = {"table", "list", "detail", "dashboard"}
        }
    end

    -- Count lines
    local rml_line_count = 0
    for _ in generated.rml:gmatch("\n") do
        rml_line_count = rml_line_count + 1
    end

    local lua_line_count = 0
    if generated.lua ~= "" then
        for _ in generated.lua:gmatch("\n") do
            lua_line_count = lua_line_count + 1
        end
    end

    -- Determine file names
    local rml_filename, lua_filename
    if view_type == "list" then
        rml_filename = string.format("%s_list.rml", data_source.table)
        lua_filename = string.format("%s_list.lua", data_source.table)
    elseif view_type == "detail" then
        rml_filename = string.format("%s_detail.rml", data_source.table)
        lua_filename = string.format("%s_detail.lua", data_source.table)
    elseif view_type == "dashboard" then
        rml_filename = string.format("%s_dashboard.rml", data_source.table)
        lua_filename = string.format("%s_dashboard.lua", data_source.table)
    else
        rml_filename = string.format("%s_view.rml", data_source.table)
        lua_filename = string.format("%s_view.lua", data_source.table)
    end

    -- Build file list
    local generated_files = {
        {
            path = "ui/generated/" .. rml_filename,
            type = "rml",
            content = generated.rml,
            line_count = rml_line_count
        }
    }

    if generated.lua ~= "" then
        table.insert(generated_files, {
            path = "scripts/generated/" .. lua_filename,
            type = "lua",
            content = generated.lua,
            line_count = lua_line_count
        })
    end

    -- View description
    local view_description = {
        displays_data_from = {data_source.table},
        supports_interactions = {},
        layout_type = view_type,
        responsive = view_type ~= "table"
    }

    if view_type == "table" then
        view_description.supports_interactions = {"row_hover", "row_select"}
    elseif view_type == "list" then
        view_description.supports_interactions = {"item_select", "item_hover"}
    end

    -- Preview description
    local preview = string.format(
        "A %s view for '%s' using template ui/templates/%s_view.rml. Data is bound at runtime via Lua script.",
        view_type,
        data_source.table,
        view_type
    )

    -- Integration steps
    local integration_steps = {}
    table.insert(integration_steps, "1. Generated files are saved automatically")
    table.insert(integration_steps, "2. RML template styling is in ui/templates/" .. view_type .. "_view.rcss")
    table.insert(integration_steps, "3. Spawn Lua thread to load: command.spawn_thread('scripts/generated/" .. lua_filename .. "')")

    -- Example usage
    local example_usage = "command.spawn_thread('scripts/generated/" .. lua_filename .. "')"

    return {
        generated_files = generated_files,
        view_description = view_description,
        preview = preview,
        integration_steps = integration_steps,
        example_usage = example_usage
    }
end

return ViewGenerator
