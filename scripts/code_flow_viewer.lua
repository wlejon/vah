-- Code Flow Viewer
-- Visualize code flow diagrams using the workflow editor canvas
-- This runs in its own Lua thread - it can only communicate with the main thread
-- via command queues and data binding

-- Database connection
local database = nil

-- Current state
local visualizations = {}
local current_visualization = nil
local current_data = nil
local node_types_data = {}
local last_selected_node = nil

-- Load available visualizations from database
local function load_visualizations()
    if not database then
        print("ERROR: Database not initialized")
        return {}
    end

    local result, error = database:query([[
        SELECT id, name, description, app_name
        FROM flows
        ORDER BY name
    ]])

    if error ~= "" then
        print("ERROR: Failed to load visualizations: " .. error)
        return {}
    end

    local viz_list = {}
    for _, row in ipairs(result or {}) do
        table.insert(viz_list, {
            id = row.app_name,
            name = row.name,
            description = row.description or ""
        })
    end

    return viz_list
end

-- Auto-layout algorithm: hierarchical layout based on graph structure
local function auto_layout_nodes(nodes, connections)
    if #nodes == 0 then return nodes end

    -- Build adjacency maps
    local incoming = {}  -- node_id -> count of incoming connections
    local outgoing = {}  -- node_id -> list of target node_ids

    for _, node in ipairs(nodes) do
        incoming[node.id] = 0
        outgoing[node.id] = {}
    end

    for _, conn in ipairs(connections) do
        incoming[conn.to_node] = (incoming[conn.to_node] or 0) + 1
        if not outgoing[conn.from_node] then
            outgoing[conn.from_node] = {}
        end
        table.insert(outgoing[conn.from_node], conn.to_node)
    end

    -- Assign nodes to layers using BFS from entry points
    local layers = {}
    local node_layer = {}
    local visited = {}
    local queue = {}

    -- Start with nodes that have no incoming connections (entry points)
    for _, node in ipairs(nodes) do
        if incoming[node.id] == 0 then
            table.insert(queue, {id = node.id, layer = 0})
            visited[node.id] = true
        end
    end

    -- If no entry points (circular graph), start from first node
    if #queue == 0 then
        table.insert(queue, {id = nodes[1].id, layer = 0})
        visited[nodes[1].id] = true
    end

    -- BFS to assign layers
    while #queue > 0 do
        local current = table.remove(queue, 1)
        local layer = current.layer

        -- Add to layer
        if not layers[layer] then
            layers[layer] = {}
        end
        table.insert(layers[layer], current.id)
        node_layer[current.id] = layer

        -- Process outgoing connections
        for _, target_id in ipairs(outgoing[current.id] or {}) do
            if not visited[target_id] then
                visited[target_id] = true
                table.insert(queue, {id = target_id, layer = layer + 1})
            end
        end
    end

    -- Handle any unvisited nodes (disconnected components)
    local max_layer = 0
    for layer, _ in pairs(layers) do
        max_layer = math.max(max_layer, layer)
    end

    for _, node in ipairs(nodes) do
        if not visited[node.id] then
            max_layer = max_layer + 1
            layers[max_layer] = {node.id}
            node_layer[node.id] = max_layer
        end
    end

    -- Layout constants
    local LAYER_SPACING = 300  -- Vertical spacing between layers
    local NODE_SPACING = 250   -- Horizontal spacing between nodes in same layer
    local START_X = 100
    local START_Y = 100

    -- Position nodes based on layers
    local positioned_nodes = {}
    for _, node in ipairs(nodes) do
        local layer = node_layer[node.id]
        local layer_nodes = layers[layer]
        local index_in_layer = 0

        for i, id in ipairs(layer_nodes) do
            if id == node.id then
                index_in_layer = i - 1
                break
            end
        end

        -- Center the layer horizontally
        local layer_width = (#layer_nodes - 1) * NODE_SPACING
        local offset = -layer_width / 2

        table.insert(positioned_nodes, {
            id = node.id,
            type_index = node.type_index,
            x = START_X + offset + (index_in_layer * NODE_SPACING),
            y = START_Y + (layer * LAYER_SPACING),
            label = node.label
        })
    end

    return positioned_nodes
end

-- Load a visualization from database
local function load_visualization(viz_id)
    if not database then
        print("ERROR: Database not initialized")
        return false
    end

    -- Find the visualization
    local viz = nil
    for _, v in ipairs(visualizations) do
        if v.id == viz_id then
            viz = v
            break
        end
    end

    if not viz then
        print("ERROR: Visualization not found: " .. viz_id)
        return false
    end

    print("Loading visualization: " .. viz.name)

    -- Get flow_id (using parameterized query for safety)
    local flow_result, flow_error = database:query(
        "SELECT id, name, description FROM flows WHERE app_name = ?",
        viz_id
    )

    if flow_error ~= "" then
        print("ERROR: Database query error: " .. flow_error)
        return false
    end

    if not flow_result or #flow_result == 0 then
        print("ERROR: Flow not found for app_name: " .. viz_id)
        return false
    end

    local flow = flow_result[1]
    local flow_id = flow.id

    -- Load node types
    local node_types_result, nt_error = database:query([[
        SELECT id, name, type, color_r, color_g, color_b, color_a,
               file_location, description, details
        FROM node_types
        WHERE flow_id = ?
        ORDER BY id
    ]], flow_id)

    if nt_error ~= "" then
        print("ERROR: Failed to load node types: " .. nt_error)
        return false
    end

    -- Load ports for all node types
    local ports_result, ports_error = database:query([[
        SELECT node_type_id, port_name, port_type, port_index
        FROM ports
        WHERE node_type_id IN (SELECT id FROM node_types WHERE flow_id = ?)
        ORDER BY node_type_id, port_type, port_index
    ]], flow_id)

    if ports_error ~= "" then
        print("ERROR: Failed to load ports: " .. ports_error)
        return false
    end

    -- Load nodes
    local nodes_result, nodes_error = database:query([[
        SELECT n.id, n.node_type_id, n.label, n.x, n.y,
               nt.name as type_name
        FROM nodes n
        JOIN node_types nt ON n.node_type_id = nt.id
        WHERE n.flow_id = ?
        ORDER BY n.id
    ]], flow_id)

    if nodes_error ~= "" then
        print("ERROR: Failed to load nodes: " .. nodes_error)
        return false
    end

    -- Load connections
    local connections_result, conn_error = database:query([[
        SELECT from_node_id, to_node_id, label
        FROM connections
        WHERE flow_id = ?
        ORDER BY id
    ]], flow_id)

    if conn_error ~= "" then
        print("ERROR: Failed to load connections: " .. conn_error)
        return false
    end

    -- Build workflow data structure
    local workflow_data = {
        name = flow.name,
        description = flow.description or "",
        node_types = {},
        nodes = {},
        connections = {}
    }

    -- Organize ports by node_type_id
    local ports_by_type = {}
    for _, port in ipairs(ports_result or {}) do
        if not ports_by_type[port.node_type_id] then
            ports_by_type[port.node_type_id] = {inputs = {}, outputs = {}}
        end

        if port.port_type == "input" then
            -- Insert at the correct index (port_index is 0-based)
            ports_by_type[port.node_type_id].inputs[port.port_index + 1] = port.port_name
        elseif port.port_type == "output" then
            ports_by_type[port.node_type_id].outputs[port.port_index + 1] = port.port_name
        end
    end

    -- Build node types array (indexed by database id for lookup)
    local node_type_id_to_index = {}
    for _, nt in ipairs(node_types_result or {}) do
        local index = #workflow_data.node_types + 1
        node_type_id_to_index[nt.id] = index

        -- Get ports for this node type from database
        local ports = ports_by_type[nt.id] or {inputs = {}, outputs = {}}

        table.insert(workflow_data.node_types, {
            name = nt.name,
            type = nt.type,
            color_r = nt.color_r or 128,
            color_g = nt.color_g or 128,
            color_b = nt.color_b or 128,
            color_a = nt.color_a or 255,
            file = nt.file_location or "",
            description = nt.description or "",
            details = nt.details or "",
            inputs = ports.inputs,
            outputs = ports.outputs
        })
    end

    -- Build nodes array (remember db id to array index mapping)
    local node_db_id_to_array_id = {}
    for _, node in ipairs(nodes_result or {}) do
        local type_index = node_type_id_to_index[node.node_type_id]
        if type_index then
            local array_id = #workflow_data.nodes + 1
            node_db_id_to_array_id[node.id] = array_id
            table.insert(workflow_data.nodes, {
                id = array_id,
                type_index = type_index,
                x = node.x or 0,
                y = node.y or 0,
                label = node.label or node.type_name
            })
        end
    end

    -- Build connections array
    for _, conn in ipairs(connections_result or {}) do
        local from_id = node_db_id_to_array_id[conn.from_node_id]
        local to_id = node_db_id_to_array_id[conn.to_node_id]
        if from_id and to_id then
            table.insert(workflow_data.connections, {
                from_node = from_id,
                from_port = 1,
                to_node = to_id,
                to_port = 1,
                label = conn.label
            })
        end
    end

    current_visualization = viz
    current_data = workflow_data

    -- Extract node types
    node_types_data = {}
    if workflow_data.node_types then
        for i, nt in ipairs(workflow_data.node_types) do
            table.insert(node_types_data, {
                id = i,  -- Use index as ID for visualization mode
                name = nt.name,
                color_r = nt.color_r or 128,
                color_g = nt.color_g or 128,
                color_b = nt.color_b or 128,
                color_a = nt.color_a or 255,
                inputs = nt.inputs or {},
                outputs = nt.outputs or {}
            })
        end
    end

    -- Bind node types to UI (must happen first)
    data.bind("node_types", node_types_data)

    -- Prepare workflow data
    local nodes = {}
    local connections = {}

    if workflow_data.nodes then
        for _, node in ipairs(workflow_data.nodes) do
            -- Get node type
            local node_type = node_types_data[node.type_index]
            if node_type then
                -- Replace literal \n with actual newlines
                local label = node.label
                if label then
                    label = label:gsub("\\n", "\n")
                end

                table.insert(nodes, {
                    id = node.id,
                    type_index = node.type_index,
                    x = node.x or 0,
                    y = node.y or 0,
                    label = label  -- Custom label for visualization
                })
            end
        end
    end

    if workflow_data.connections then
        for _, conn in ipairs(workflow_data.connections) do
            table.insert(connections, {
                from_node = conn.from_node,
                from_port = conn.from_port,
                to_node = conn.to_node,
                to_port = conn.to_port
            })
        end
    end

    -- Apply auto-layout algorithm to position nodes optimally
    nodes = auto_layout_nodes(nodes, connections)

    -- Bind workflow data
    data.bind("workflow_nodes", nodes)
    data.bind("workflow_connections", connections)

    -- Bind metadata
    data.bind("active_visualization", {{
        name = workflow_data.name or "Untitled",
        description = workflow_data.description or ""
    }})

    -- Clear selected node info when loading new visualization
    data.bind("selected_node_info", {})
    last_selected_node = nil

    -- Trigger reload in the workflow editor canvas
    data.bind("workflow_reload_trigger", {timestamp = os.time()})
    return true
end

-- Build node info for selected node
local function build_node_info(node_id)
    if not current_data then return {} end

    -- Find the node
    local node = nil
    for _, n in ipairs(current_data.nodes) do
        if n.id == node_id then
            node = n
            break
        end
    end

    if not node then return {} end

    -- Get node type
    local node_type = current_data.node_types[node.type_index]
    if not node_type then return {} end

    -- Build connections
    local connections_to = {}
    local connections_from = {}

    for _, conn in ipairs(current_data.connections) do
        if conn.from_node == node_id then
            -- Find target node name
            for _, n in ipairs(current_data.nodes) do
                if n.id == conn.to_node then
                    local target_type = current_data.node_types[n.type_index]
                    if target_type then
                        table.insert(connections_to, target_type.name)
                    end
                    break
                end
            end
        end
        if conn.to_node == node_id then
            -- Find source node name
            for _, n in ipairs(current_data.nodes) do
                if n.id == conn.from_node then
                    local source_type = current_data.node_types[n.type_index]
                    if source_type then
                        table.insert(connections_from, source_type.name)
                    end
                    break
                end
            end
        end
    end

    -- Build info structure
    return {{
        name = node_type.name or "Unknown",
        type = (node.label or node_type.name or "Node"),
        file = node_type.file or "",
        description = node_type.description or "",
        details = node_type.details or "",
        connections_to = connections_to,
        connections_to_count = #connections_to,
        connections_from = connections_from,
        connections_from_count = #connections_from
    }}
end

-- Check for selected node changes (removed - handled by events now)

function startup()
    print("Code Flow Viewer started (thread_id: " .. thread_id .. ")")

    -- Check if database exists, if not initialize it
    local db_exists = fs.exists("data/code_flows.db")
    if not db_exists then
        print("Database not found, initializing...")

        -- Open/create database
        local init_db, init_error = db.open("data/code_flows.db")
        if init_error ~= "" then
            print("ERROR: Failed to create database: " .. init_error)
            return
        end

        -- Read and execute schema
        local schema_sql, schema_err = fs.read_file("data/code_flows_schema.sql")
        if schema_err ~= "" then
            print("ERROR: Failed to read schema: " .. schema_err)
            init_db:close()
            return
        end

        local success, exec_error = init_db:execute(schema_sql)
        if not success then
            print("ERROR: Failed to create schema: " .. exec_error)
            init_db:close()
            return
        end

        -- Read and execute tetris population
        local tetris_sql, tetris_err = fs.read_file("data/populate_tetris_flow.sql")
        if tetris_err ~= "" then
            print("ERROR: Failed to read tetris data: " .. tetris_err)
            init_db:close()
            return
        end

        print("Executing tetris population SQL...")

        -- Split the SQL into statements (execute one big SQL doesn't always work properly)
        -- Execute each section separately to ensure proper commits
        local statements = {}
        local current = ""
        for line in tetris_sql:gmatch("[^\r\n]+") do
            if line:match("^%s*%-%-") then
                -- Skip comments
            elseif line:match(";%s*$") then
                -- End of statement
                current = current .. line
                table.insert(statements, current)
                current = ""
            else
                current = current .. line .. "\n"
            end
        end

        -- Execute each statement
        for i, stmt in ipairs(statements) do
            if stmt:match("%S") then  -- Skip empty statements
                success, exec_error = init_db:execute(stmt)
                if not success then
                    print("ERROR: Failed to execute statement " .. i .. ": " .. exec_error)
                    print("Statement: " .. stmt:sub(1, 100))
                    init_db:close()
                    return
                end
            end
        end

        print("Tetris data populated (" .. #statements .. " statements)")

        -- Verify data was inserted
        local verify_result, verify_error = init_db:query("SELECT COUNT(*) as count FROM flows")
        if verify_result and #verify_result > 0 then
            print("Flows in database: " .. tostring(verify_result[1].count))

            -- Also check if we can query by app_name
            local test_result, test_error = init_db:query("SELECT id, app_name FROM flows WHERE app_name = 'tetris'")
            if test_result and #test_result > 0 then
                print("Found tetris flow with id: " .. tostring(test_result[1].id))
            else
                print("WARNING: Cannot find tetris by app_name: " .. tostring(test_error))
                -- List all flows
                local all_flows, _ = init_db:query("SELECT id, app_name FROM flows")
                if all_flows then
                    print("All flows in database:")
                    for _, f in ipairs(all_flows) do
                        print("  - id=" .. tostring(f.id) .. ", app_name=" .. tostring(f.app_name))
                    end
                end
            end
        else
            print("WARNING: Could not verify flow count: " .. tostring(verify_error))
        end

        -- Don't close! Keep using this database handle
        database = init_db
        print("Database initialized successfully")
    else
        -- Database already exists, open it
        local db, db_error = db.open("data/code_flows.db")
        if db_error ~= "" then
            print("ERROR: Failed to open database: " .. db_error)
            return
        end
        database = db
    end

    print("Code flows database opened")

    -- Load visualizations from database
    visualizations = load_visualizations()
    print("Loaded " .. #visualizations .. " visualizations")

    -- Bind visualization list
    data.bind("visualizations", visualizations)

    -- Bind empty selected_node_info initially (required before UI loads)
    data.bind("selected_node_info", {})

    -- Load first visualization by default (BEFORE loading UI)
    if #visualizations > 0 then
        load_visualization(visualizations[1].id)
    else
        print("ERROR: No visualizations found in database")
        return
    end

    -- Register event handler for visualization selection
    event.register("select_visualization", function(payload)
        -- Get the visualization id from the payload
        local selected_id = payload.id
        if selected_id and selected_id ~= "" then
            print("Loading visualization: " .. selected_id)
            load_visualization(selected_id)
        else
            print("ERROR: No visualization id selected")
        end
    end)

    -- Register event handler for node selection
    event.register("node_selected", function(payload)
        local node_id = payload.node_id
        if node_id then
            print("Node selected: " .. tostring(node_id))
            local info = build_node_info(node_id)
            data.bind("selected_node_info", info)
            last_selected_node = node_id
        end
    end)

    -- Register event handler for node deselection
    event.register("node_deselected", function(payload)
        print("Node deselected")
        data.bind("selected_node_info", {})
        last_selected_node = nil
    end)

    -- Load UI (after all data is bound)
    ui.load_document("ui/code_flow_viewer.rml", true, "code_flow_viewer")
end

function update(dt)
    -- Nothing to update - node selection handled by events
end

function shutdown()
    if database then
        database:close()
        print("Code flows database closed")
    end
    print("Code Flow Viewer shutting down")
end
