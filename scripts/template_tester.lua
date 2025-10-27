-- Template Tester
-- Interactive testing UI for markdown template renderer

local renderer = require("template_renderer")
local markdown_parser = require("markdown_parser")

-- Load template from file
local function load_template(path)
    local content, err = fs.read(path)
    if err ~= "" then
        print("Error loading template: " .. err)
        return ""
    end
    return content
end

-- Initial example data showcasing all template features
local example_data = {
    type = "Contacts",
    total = 3,
    recent_action = "Created contact 'Jane Smith'",
    timestamp = "2025-01-15 14:30:00",
    data = {
        total = 150,
        page = 1,
        total_pages = 15,
        limit = 10,
        items = {
            {id = 1, name = "Alice Johnson", email = "alice@example.com", status = "active", age = 30},
            {id = 2, name = "Bob Smith", email = "bob@example.com", status = "active", age = 25},
            {id = 3, name = "Charlie Brown", email = "charlie@example.com", status = "inactive", age = 35}
        }
    },
    metadata = {
        database = "contacts.db",
        table_name = "contacts",
        last_modified = "2025-01-15"
    },
    has_recent_activity = true,
    stats = {
        active_count = 125,
        inactive_count = 25
    }
}

-- Load initial example template from file
local example_template = load_template("ui/templates/example_template.md")

-- Current state
local current_json = ""
local current_template = ""
local current_data = example_data

-- Output model
local output_data = {
    content = "",
    parsed_rml = "",
    error = ""
}

function render_template()
    -- Parse JSON data
    local template_data = nil
    local parse_ok, parse_result = pcall(json.decode, current_json)

    if not parse_ok then
        output_data.error = "JSON Parse Error: " .. tostring(parse_result)
        output_data.content = ""
        data.bind("output", {output_data})
        return
    end

    template_data = parse_result

    -- Render template
    local render_ok, render_result = pcall(renderer.render, current_template, template_data)

    if not render_ok then
        output_data.error = "Template Error: " .. tostring(render_result)
        output_data.content = ""
        output_data.parsed_rml = ""

        -- Clear rendered RML panel
        ui.set_element_text("rml_rendered_content", "")
    else
        output_data.error = ""
        output_data.content = render_result

        -- Parse markdown to RML
        local parse_ok, parse_result = pcall(markdown_parser.to_rml, render_result)
        if not parse_ok then
            output_data.error = "Markdown Parse Error: " .. tostring(parse_result)
            output_data.parsed_rml = ""

            -- Clear rendered RML panel
            ui.set_element_text("rml_rendered_content", "")
        else
            output_data.parsed_rml = parse_result

            -- Inject the RML into the fourth panel for rendering
            ui.set_element_text("rml_rendered_content", parse_result)
        end
    end

    data.bind("output", {output_data})
end

function startup()
    print("Template Tester started (thread_id: " .. thread_id .. ")")

    -- Convert example data to pretty JSON
    current_json = json.encode_pretty(example_data)
    current_template = example_template

    -- Register event handlers
    event.register("render", function(payload)
        print("Rendering template...")
        render_template()
    end)

    event.register("json_modified", function(payload)
        current_json = payload.content or ""
        render_template()
    end)

    event.register("template_modified", function(payload)
        current_template = payload.content or ""
        render_template()
    end)

    -- Register handler for document reload (hot reload)
    event.register("document_reloaded", function(payload)
        print("Document reloaded, restoring TextEditor content...")
        -- Re-populate the text editors with current data
        ui.set_texteditor_content("json_editor", current_json)
        ui.set_texteditor_content("template_editor", current_template)
        ui.set_texteditor_editable("json_editor", true)
        ui.set_texteditor_editable("template_editor", true)
    end)

    -- Initialize output with initial render
    render_template()

    -- Load UI
    ui.load_document("ui/template_tester.rml", true, "template_tester")

    -- Set initial content in editors
    ui.set_texteditor_content("json_editor", current_json)
    ui.set_texteditor_content("template_editor", current_template)

    -- Make editors editable
    ui.set_texteditor_editable("json_editor", true)
    ui.set_texteditor_editable("template_editor", true)

    print("Template Tester ready. Modify JSON/Template to see live updates.")
end

function update(dt)
    -- Nothing to do
end

function shutdown()
    print("Template Tester shutting down")
end
