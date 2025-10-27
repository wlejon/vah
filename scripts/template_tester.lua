-- Template Tester
-- Interactive testing UI for markdown template renderer

local renderer = require("template_renderer")

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

-- Initial example template showcasing all features
local example_template = [[
# {{type}} Database View

{{#if recent_action}}
**Recent Activity:** {{recent_action}}
**Timestamp:** {{timestamp}}

{{/if}}
## Overview

- **Total Records:** {{data.total}}
- **Current Page:** {{data.page}} of {{data.total_pages}}
- **Database:** {{metadata.database}}
- **Table:** {{metadata.table_name}}

{{#if has_recent_activity}}
## Statistics

{{#each stats}}
- **{{@key}}:** {{@value}}
{{/each}}
{{/if}}

## Contact List

{{#each data.items}}
{{#if @first}}
| ID | Name | Email | Status | Age |
|----|------|-------|--------|-----|
{{/if}}
| {{id}} | {{name}} | {{email}} | {{status}} | {{age}} |
{{/each}}

---

Page {{data.page}} of {{data.total_pages}} (showing {{data.limit}} per page)
]]

-- Current state
local current_json = ""
local current_template = ""
local current_data = example_data

-- Output model
local output_data = {
    content = "",
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
    else
        output_data.error = ""
        output_data.content = render_result
    end

    data.bind("output", {output_data})
end

function startup()
    print("Template Tester started (thread_id: " .. thread_id .. ")")

    -- Convert example data to JSON
    current_json = json.encode(example_data)
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
