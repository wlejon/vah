-- Workflow Editor Initialization
-- Main entry point that ties all modules together

local state_module = require("workflow_editor.state")
local colors = require("workflow_editor.colors")
local node_module = require("workflow_editor.node")
local render = require("workflow_editor.render")
local input = require("workflow_editor.input")

-- Module state
local editor = nil
local node_types = {}
local last_reload_check = 0
local reload_check_interval = 0.5
local last_workflow_sync = 0
local workflow_sync_interval = 0.1

-- Build renderable nodes from server data
local function build_nodes_from_server()
    if not editor or not data or not data.get then
        return
    end

    -- Don't refresh if we're currently dragging
    if editor.dragging_node then
        return
    end

    local workflow_nodes = data.get("workflow_nodes")
    if not workflow_nodes then
        editor.nodes = {}
        return
    end

    -- Rebuild nodes from server data with full type information for rendering
    local new_nodes = {}
    local max_id = 0

    for _, node_data in ipairs(workflow_nodes) do
        if node_data.id and node_data.type_index and node_data.x and node_data.y then
            local node_type = node_types[node_data.type_index]
            if node_type then
                local node = {
                    id = node_data.id,
                    x = node_data.x,
                    y = node_data.y,
                    type_index = node_data.type_index,
                    name = node_type.name,
                    color = nvg.rgba(
                        node_type.color_r or 128,
                        node_type.color_g or 128,
                        node_type.color_b or 128,
                        node_type.color_a or 255
                    ),
                    inputs = node_type.inputs or {},
                    outputs = node_type.outputs or {},
                }
                table.insert(new_nodes, node)
                max_id = math.max(max_id, node_data.id)
            end
        end
    end

    editor.nodes = new_nodes
    editor.next_node_id = max_id + 1
end

-- Get connections from server data
local function get_connections_from_server()
    if not data or not data.get then
        return {}
    end

    -- Don't refresh if we're currently dragging
    if editor.dragging_node then
        return editor.connections or {}
    end

    local workflow_connections = data.get("workflow_connections")
    return workflow_connections or {}
end

-- Reload node types from data store
local function reload_node_types()
    if not data or not data.get then
        print("[Workflow Editor] data.get() not available")
        return
    end

    local new_node_types = data.get("node_types") or {}

    -- Update existing nodes in the scene to match their new type definitions
    node_module.update_from_types(editor, new_node_types)

    -- Update the node_types table
    node_types = new_node_types
end

-- Initialize the workflow editor
local function initialize()
    -- Create editor state
    editor = state_module.create()

    -- Load node types from data store
    if data and data.get then
        node_types = data.get("node_types") or {}
    else
        print("[Workflow Editor] data.get() not available")
    end
end

-- Main render function
local function render_workflow(nvg_ctx, canvas_x, canvas_y, canvas_w, canvas_h, time)
    -- Initialize on first render
    if not editor then
        initialize()
    end

    -- Periodically check if node types were updated
    if time - last_reload_check > reload_check_interval then
        reload_node_types()
        last_reload_check = time
    end

    -- Refresh from server when not dragging
    build_nodes_from_server()
    editor.connections = get_connections_from_server()

    -- Store canvas position for mouse coordinate conversion
    editor.canvas_x = canvas_x
    editor.canvas_y = canvas_y

    -- NanoVG renders in canvas-local coordinates, starting at (canvas_x, canvas_y)
    local x, y, w, h = canvas_x, canvas_y, canvas_w, canvas_h

    -- Draw background
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, w, h)
    nvg.fillColor(nvg_ctx, colors.background)
    nvg.fill(nvg_ctx)

    -- Draw grid
    render.draw_grid(nvg_ctx, editor, colors, x, y, w, h)

    -- Apply canvas transform for nodes and connections
    nvg.save(nvg_ctx)
    nvg.translate(nvg_ctx, x + editor.pan_x, y + editor.pan_y)
    nvg.scale(nvg_ctx, editor.zoom, editor.zoom)

    -- Draw connections behind nodes
    render.draw_connections(nvg_ctx, editor, colors)

    -- Draw nodes
    render.draw_nodes(nvg_ctx, editor, colors)

    nvg.restore(nvg_ctx)

    -- Draw node creation menu (in screen space, but relative to canvas)
    render.draw_node_menu(nvg_ctx, editor, colors, node_types)

    -- Draw UI overlay (in screen space)
    nvg.fontSize(nvg_ctx, 12.0)
    nvg.fontFace(nvg_ctx, "roboto")
    nvg.textAlign(nvg_ctx, nvg.ALIGN_LEFT + nvg.ALIGN_TOP)
    nvg.fillColor(nvg_ctx, colors.text_dim)
    nvg.text(nvg_ctx, x + 10, y + 10,
            "Workflow Editor  |  Nodes: " .. #editor.nodes ..
            "  |  Zoom: " .. string.format("%.1f", editor.zoom * 100) .. "%")

    nvg.text(nvg_ctx, x + 10, y + 26,
            "Left: Select/Drag  |  Middle: Pan  |  Right: Create menu  |  Delete: Remove  |  1-7: Quick create")
end

-- Removed sync_to_bindings - client doesn't have data.bind()
-- Server is source of truth, client just reads via data.get()

-- Mouse click handler
local function handle_workflow_click(button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
    if not editor then return end
    input.handle_click(editor, node_types, button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
    -- No sync needed - input handlers trigger events to server
end

-- Mouse move handler
local function handle_workflow_move(mouse_x, mouse_y, canvas_x, canvas_y, button_left, button_middle, button_right)
    if not editor then return end
    input.handle_move(editor, mouse_x, mouse_y, canvas_x, canvas_y, button_left, button_middle, button_right)
    -- No sync during drag - update is sent on mouse release
end

-- Mouse scroll handler
local function handle_workflow_scroll(wheel_x, wheel_y)
    if not editor then return end
    input.handle_scroll(editor, wheel_x, wheel_y)
end

-- Keyboard handler
local function handle_workflow_key(key, key_down)
    if not editor then return end
    input.handle_key(editor, node_types, key, key_down)
    -- No sync needed - input handlers trigger events to server
end

-- Expose editor instance globally for custom integrations (must be done in render function)
_G.get_workflow_editor = function() return editor end

-- Export public API
return {
    -- Render and input handlers (for RML)
    render_workflow = render_workflow,
    handle_workflow_click = handle_workflow_click,
    handle_workflow_move = handle_workflow_move,
    handle_workflow_scroll = handle_workflow_scroll,
    handle_workflow_key = handle_workflow_key,
}
