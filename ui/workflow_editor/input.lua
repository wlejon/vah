-- Workflow Editor Input Handling
-- Mouse and keyboard event handlers

local M = {}

local node_module = require("workflow_editor.node")
local connection = require("workflow_editor.connection")
local transform = require("workflow_editor.transform")

-- Mouse click handler (called on button down/up events only)
-- Button: 0=left, 1=right, 2=middle
function M.handle_click(editor, node_types, button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
    -- Update mouse position relative to canvas
    editor.mouse_x = mouse_x - canvas_x
    editor.mouse_y = mouse_y - canvas_y

    local world_x, world_y = transform.screen_to_world(editor, editor.mouse_x, editor.mouse_y)

    -- Track button state
    local was_down = editor.mouse_buttons[button + 1]
    editor.mouse_buttons[button + 1] = button_down

    -- LEFT MOUSE BUTTON - Node interaction, connections, selection
    if button == 0 then
        if button_down and not was_down then
            -- Left button press
            editor.mouse_drag_start_x = editor.mouse_x
            editor.mouse_drag_start_y = editor.mouse_y

            -- Check node menu click
            if editor.show_node_menu then
                local menu_width = 200
                local item_height = 30

                for i = 1, #node_types do
                    local item_y = editor.node_menu_y + 5 + (i - 1) * item_height
                    if editor.mouse_x >= editor.node_menu_x and
                       editor.mouse_x <= editor.node_menu_x + menu_width and
                       editor.mouse_y >= item_y and
                       editor.mouse_y <= item_y + item_height then
                        local create_world_x, create_world_y = transform.screen_to_world(
                            editor, editor.node_menu_x, editor.node_menu_y)
                        local new_node = node_module.create(editor, node_types, create_world_x, create_world_y, i)
                        if new_node then
                            -- Trigger node created event
                            emit('workflow_node_created', {
                                node_id = new_node.id,
                                type_index = new_node.type_index,
                                x = new_node.x,
                                y = new_node.y
                            })
                        end
                        editor.show_node_menu = false
                        return
                    end
                end
                editor.show_node_menu = false
                return
            end

            -- Check port interaction
            editor.hovered_port = nil
            for _, node in ipairs(editor.nodes) do
                local port = node_module.get_port_at_position(editor, node, world_x, world_y)
                if port then
                    editor.hovered_port = port
                    editor.dragging_connection = port
                    return
                end
            end

            -- Check node interaction
            editor.dragging_node = nil
            for i = #editor.nodes, 1, -1 do
                local node = editor.nodes[i]
                if node_module.is_point_inside(editor, node, world_x, world_y) then
                    editor.dragging_node = node
                    editor.selected_node = node.id
                    editor.mouse_drag_start_x = world_x - node.x
                    editor.mouse_drag_start_y = world_y - node.y
                    return
                end
            end

            -- Nothing clicked - deselect
            editor.selected_node = nil

        elseif not button_down and was_down then
            -- Left button release

            -- If we were dragging a node, update DataStore immediately and trigger server event
            if editor.dragging_node then
                -- Find the row in workflow_nodes that matches this node_id
                local workflow_nodes = data.get("workflow_nodes")
                if workflow_nodes then
                    for i, node in ipairs(workflow_nodes) do
                        if node.id == editor.dragging_node.id then
                            -- Update this row in the DataStore immediately
                            data.update_row("workflow_nodes", i, {
                                x = editor.dragging_node.x,
                                y = editor.dragging_node.y
                            })
                            break
                        end
                    end
                end

                -- Trigger server event to persist to database
                emit('workflow_node_moved', {
                    node_id = editor.dragging_node.id,
                    x = editor.dragging_node.x,
                    y = editor.dragging_node.y
                })
            end

            if editor.dragging_connection then
                -- Complete connection
                for _, node in ipairs(editor.nodes) do
                    local target_port = node_module.get_port_at_position(editor, node, world_x, world_y)
                    if target_port and target_port.node_id ~= editor.dragging_connection.node_id then
                        if target_port.is_output ~= editor.dragging_connection.is_output then
                            local from_node, from_port, to_node, to_port
                            if editor.dragging_connection.is_output then
                                from_node = editor.dragging_connection.node_id
                                from_port = editor.dragging_connection.port_index
                                to_node = target_port.node_id
                                to_port = target_port.port_index
                            else
                                from_node = target_port.node_id
                                from_port = target_port.port_index
                                to_node = editor.dragging_connection.node_id
                                to_port = editor.dragging_connection.port_index
                            end
                            local success = connection.add(editor, from_node, from_port, to_node, to_port)
                            if success then
                                -- Trigger connection added event
                                emit('workflow_connection_added', {
                                    from_node = from_node,
                                    from_port = from_port,
                                    to_node = to_node,
                                    to_port = to_port
                                })
                            end
                        end
                        break
                    end
                end
                editor.dragging_connection = nil
            end

            editor.dragging_node = nil
        end

    -- MIDDLE MOUSE BUTTON - Canvas panning
    elseif button == 1 then
        if button_down and not was_down then
            -- Middle button press
            editor.mouse_drag_start_x = editor.mouse_x
            editor.mouse_drag_start_y = editor.mouse_y
            editor.panning_canvas = true

        elseif not button_down and was_down then
            -- Middle button release
            editor.panning_canvas = false
        end

    -- RIGHT MOUSE BUTTON - Context menu
    elseif button == 2 then
        if button_down and not was_down then
            -- Right button press - open node creation menu
            editor.show_node_menu = true
            editor.node_menu_x = editor.mouse_x
            editor.node_menu_y = editor.mouse_y
        end
    end

    -- Update hover state (for any button/no button)
    if not editor.dragging_node and not editor.dragging_connection then
        editor.hovered_node = nil
        editor.hovered_port = nil

        for i = #editor.nodes, 1, -1 do
            local node = editor.nodes[i]
            if node_module.is_point_inside(editor, node, world_x, world_y) then
                editor.hovered_node = node.id
                local port = node_module.get_port_at_position(editor, node, world_x, world_y)
                if port then
                    editor.hovered_port = port
                end
                break
            end
        end
    end
end

-- Mouse move handler (called on all mouse movement)
function M.handle_move(editor, mouse_x, mouse_y, canvas_x, canvas_y, button_left, button_middle, button_right)
    -- Update mouse position relative to canvas
    editor.mouse_x = mouse_x - canvas_x
    editor.mouse_y = mouse_y - canvas_y

    local world_x, world_y = transform.screen_to_world(editor, editor.mouse_x, editor.mouse_y)

    -- Handle dragging if left button is pressed
    if button_left then
        if editor.dragging_node then
            editor.dragging_node.x = world_x - editor.mouse_drag_start_x
            editor.dragging_node.y = world_y - editor.mouse_drag_start_y
        end
    end

    -- Handle canvas panning if middle button is pressed
    if button_middle then
        if editor.panning_canvas then
            editor.pan_x = editor.pan_x + (editor.mouse_x - editor.mouse_drag_start_x)
            editor.pan_y = editor.pan_y + (editor.mouse_y - editor.mouse_drag_start_y)
            editor.mouse_drag_start_x = editor.mouse_x
            editor.mouse_drag_start_y = editor.mouse_y
        end
    end

    -- Update hover state when not dragging
    if not editor.dragging_node and not editor.dragging_connection then
        editor.hovered_node = nil
        editor.hovered_port = nil

        for i = #editor.nodes, 1, -1 do
            local node = editor.nodes[i]
            if node_module.is_point_inside(editor, node, world_x, world_y) then
                editor.hovered_node = node.id
                local port = node_module.get_port_at_position(editor, node, world_x, world_y)
                if port then
                    editor.hovered_port = port
                end
                break
            end
        end
    end
end

-- Mouse scroll handler (mouse wheel zoom)
function M.handle_scroll(editor, wheel_x, wheel_y)
    -- Zoom in/out with mouse wheel
    -- Negative wheel_y = scroll up = zoom in
    -- Positive wheel_y = scroll down = zoom out
    local zoom_factor = 1.1

    if wheel_y < 0 then
        -- Zoom in
        editor.zoom = math.min(editor.zoom * zoom_factor, 3.0)
    elseif wheel_y > 0 then
        -- Zoom out
        editor.zoom = math.max(editor.zoom / zoom_factor, 0.3)
    end
end

-- Keyboard handler
function M.handle_key(editor, node_types, key, key_down)
    if not key_down then
        return
    end

    -- Delete selected node
    if key == "delete" or key == "backspace" then
        if editor.selected_node then
            local deleted_node_id = editor.selected_node

            -- Remove connections involving this node
            connection.remove_for_node(editor, editor.selected_node)

            -- Remove node
            for i, node in ipairs(editor.nodes) do
                if node.id == editor.selected_node then
                    table.remove(editor.nodes, i)
                    break
                end
            end

            editor.selected_node = nil

            -- Trigger node deleted event
            emit('workflow_node_deleted', {node_id = deleted_node_id})
        end
    end

    -- Reset view
    if key == "r" then
        editor.pan_x = 0
        editor.pan_y = 0
        editor.zoom = 1.0
    end

    -- Zoom in/out
    if key == "=" or key == "equals" then
        editor.zoom = math.min(editor.zoom * 1.2, 3.0)
    elseif key == "minus" then
        editor.zoom = math.max(editor.zoom / 1.2, 0.3)
    end

    -- Open node creation menu
    if key == "tab" or key == "space" then
        editor.show_node_menu = not editor.show_node_menu
        if editor.show_node_menu then
            editor.node_menu_x = editor.mouse_x
            editor.node_menu_y = editor.mouse_y
        end
    end

    -- Quick create nodes with number keys
    local node_type_index = tonumber(key)
    if node_type_index and node_type_index >= 1 and node_type_index <= #node_types then
        local world_x, world_y = transform.screen_to_world(editor, editor.mouse_x, editor.mouse_y)
        local new_node = node_module.create(editor, node_types, world_x, world_y, node_type_index)
        if new_node then
            editor.selected_node = new_node.id
            -- Trigger node created event
            emit('workflow_node_created', {
                node_id = new_node.id,
                type_index = new_node.type_index,
                x = new_node.x,
                y = new_node.y
            })
        end
    end
end

return M
