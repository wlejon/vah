-- Vehicle Builder: Physics-based puzzle game
-- Build vehicles from physics components to traverse challenging terrain

local world = nil
local terrain_bodies = {}
local placed_components = {}
local joints = {}
local selected_component_type = nil
local game_state = "building" -- building, testing, success, failure
local camera_x = 0
local camera_y = 0
local camera_zoom = 20 -- pixels per meter

-- Component definitions
local component_types = {
    {
        id = "wheel_small",
        name = "Small Wheel",
        description = "Light wheel, good for speed",
        create = function(x, y)
            local body = world:create_body(physics.DYNAMIC, x, y, 0)
            body:add_circle_fixture(0.5, 0, 0, 1.0, 0.8, 0.3)
            return {
                body = body,
                type = "wheel_small",
                radius = 0.5,
                render_type = "circle"
            }
        end
    },
    {
        id = "wheel_large",
        name = "Large Wheel",
        description = "Heavy wheel, good for obstacles",
        create = function(x, y)
            local body = world:create_body(physics.DYNAMIC, x, y, 0)
            body:add_circle_fixture(1.0, 0, 0, 2.0, 0.9, 0.3)
            return {
                body = body,
                type = "wheel_large",
                radius = 1.0,
                render_type = "circle"
            }
        end
    },
    {
        id = "box_small",
        name = "Small Box",
        description = "Light structural component",
        create = function(x, y)
            local body = world:create_body(physics.DYNAMIC, x, y, 0)
            body:add_box_fixture(0.5, 0.5, 1.0, 0.5, 0.1)
            return {
                body = body,
                type = "box_small",
                half_width = 0.5,
                half_height = 0.5,
                render_type = "box"
            }
        end
    },
    {
        id = "box_large",
        name = "Large Box",
        description = "Heavy structural component",
        create = function(x, y)
            local body = world:create_body(physics.DYNAMIC, x, y, 0)
            body:add_box_fixture(1.0, 0.8, 2.0, 0.5, 0.1)
            return {
                body = body,
                type = "box_large",
                half_width = 1.0,
                half_height = 0.8,
                render_type = "box"
            }
        end
    },
    {
        id = "plank",
        name = "Plank",
        description = "Long thin beam for structure",
        create = function(x, y)
            local body = world:create_body(physics.DYNAMIC, x, y, 0)
            body:add_box_fixture(1.5, 0.2, 1.5, 0.5, 0.1)
            return {
                body = body,
                type = "plank",
                half_width = 1.5,
                half_height = 0.2,
                render_type = "box"
            }
        end
    },
    {
        id = "motor",
        name = "Motor",
        description = "Powered wheel drive",
        create = function(x, y)
            local body = world:create_body(physics.DYNAMIC, x, y, 0)
            body:add_circle_fixture(0.6, 0, 0, 1.5, 0.9, 0.2)
            return {
                body = body,
                type = "motor",
                radius = 0.6,
                render_type = "circle",
                is_motor = true,
                motor_speed = 10.0
            }
        end
    }
}

-- Terrain configuration
local terrain_segments = {
    {x1 = -5, y1 = -3, x2 = 10, y2 = -3},   -- Flat start
    {x1 = 10, y1 = -3, x2 = 15, y2 = -1},   -- Small hill up
    {x1 = 15, y1 = -1, x2 = 20, y2 = -2},   -- Down
    {x1 = 20, y1 = -2, x2 = 25, y2 = 0},    -- Big hill up
    {x1 = 25, y1 = 0, x2 = 30, y2 = -1},    -- Down
    {x1 = 30, y1 = -1, x2 = 32, y2 = -1},   -- Gap (will be separate)
    {x1 = 34, y1 = -2, x2 = 40, y2 = -2},   -- After gap
    {x1 = 40, y1 = -2, x2 = 50, y2 = -4},   -- Final stretch
}

local goal_x = 48
local start_zone = {x = 2, y = 0, width = 6, height = 4}

function startup()
    print("Vehicle Builder starting...")

    -- Create physics world
    local world_result, error_msg = physics.create_world(0, -10)
    if not world_result then
        print("Failed to create physics world: " .. error_msg)
        return
    end
    world = world_result

    -- Create terrain
    create_terrain()

    -- Initialize camera at start zone
    camera_x = start_zone.x + start_zone.width / 2
    camera_y = 0

    -- Select first component by default
    selected_component_type = component_types[1].id

    -- Initialize data bindings BEFORE loading UI
    update_bindings()

    -- Load UI
    ui.load_document("ui/apps/vehicle_builder/vehicle_builder.rml", true, "vehicle_builder")

    -- Register event handlers
    event.register("vb_select_component", function(payload)
        selected_component_type = payload.component_id
        print("Selected component: " .. selected_component_type)
    end)

    event.register("vb_place_component", function(payload)
        if game_state == "building" then
            place_component(payload.world_x, payload.world_y)
        end
    end)

    event.register("vb_start_test", function(payload)
        start_test()
    end)

    event.register("vb_reset", function(payload)
        reset_vehicle()
    end)

    event.register("vb_apply_motor", function(payload)
        apply_motor_torque()
    end)

    print("Vehicle Builder ready! Build your vehicle in the start zone (left side).")
end

function create_terrain()
    -- Create terrain segments
    for i, segment in ipairs(terrain_segments) do
        -- Skip gap segments (disconnected terrain)
        if segment.x2 - segment.x1 > 1.5 then
            local center_x = (segment.x1 + segment.x2) / 2
            local center_y = (segment.y1 + segment.y2) / 2
            local length = math.sqrt((segment.x2 - segment.x1)^2 + (segment.y2 - segment.y1)^2)
            local angle = math.atan(segment.y2 - segment.y1, segment.x2 - segment.x1)

            local terrain = world:create_body(physics.STATIC, center_x, center_y, angle)
            terrain:add_box_fixture(length / 2, 0.2, 0, 0.6, 0)

            table.insert(terrain_bodies, {
                body = terrain,
                x1 = segment.x1,
                y1 = segment.y1,
                x2 = segment.x2,
                y2 = segment.y2
            })
        end
    end

    -- Create goal marker (static sensor)
    local goal_marker = world:create_body(physics.STATIC, goal_x, 2, 0)
    goal_marker:add_box_fixture(0.5, 3, 0, 0, 0)
    table.insert(terrain_bodies, {
        body = goal_marker,
        is_goal = true,
        x = goal_x,
        y = 2
    })
end

function place_component(world_x, world_y)
    -- Check if in build zone (start area)
    if world_x < start_zone.x or world_x > start_zone.x + start_zone.width or
       world_y < start_zone.y - start_zone.height or world_y > start_zone.y then
        print("Can only place components in the start zone!")
        return
    end

    -- Find component type
    local comp_def = nil
    for _, def in ipairs(component_types) do
        if def.id == selected_component_type then
            comp_def = def
            break
        end
    end

    if not comp_def then
        print("No component selected!")
        return
    end

    -- Create component
    local component = comp_def.create(world_x, world_y)
    component.id = #placed_components + 1
    table.insert(placed_components, component)

    print("Placed " .. comp_def.name .. " at (" .. world_x .. ", " .. world_y .. ")")

    -- Auto-connect to nearby components with joints
    try_auto_connect(component)
end

function try_auto_connect(new_component)
    local connect_distance = 1.5 -- Maximum distance to auto-connect

    local new_info = new_component.body:get_info()
    local new_pos = {x = new_info.pos_x, y = new_info.pos_y}

    for _, existing in ipairs(placed_components) do
        if existing.id ~= new_component.id then
            local exist_info = existing.body:get_info()
            local exist_pos = {x = exist_info.pos_x, y = exist_info.pos_y}

            local dx = new_pos.x - exist_pos.x
            local dy = new_pos.y - exist_pos.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance < connect_distance then
                create_joint(new_component, existing, new_pos, exist_pos)
            end
        end
    end
end

function create_joint(comp1, comp2, pos1, pos2)
    -- Create a revolute joint at the midpoint
    local anchor_x = (pos1.x + pos2.x) / 2
    local anchor_y = (pos1.y + pos2.y) / 2

    -- Check if either is a motor - if so, create motorized joint
    local is_motor = comp1.is_motor or comp2.is_motor
    local motor_speed = 0
    if comp1.is_motor then motor_speed = comp1.motor_speed end
    if comp2.is_motor then motor_speed = comp2.motor_speed end

    -- For now, we'll track joints but Box2D joint API isn't exposed yet
    -- We'll simulate them by constraining positions in update loop
    table.insert(joints, {
        comp1 = comp1,
        comp2 = comp2,
        anchor_x = anchor_x,
        anchor_y = anchor_y,
        is_motor = is_motor,
        motor_speed = motor_speed,
        max_force = 1000, -- Joint breaks above this force
        broken = false
    })

    print("Created joint between components at (" .. anchor_x .. ", " .. anchor_y .. ")")
end

function start_test()
    if #placed_components == 0 then
        print("Place some components first!")
        return
    end

    game_state = "testing"
    print("Test started! Use Motor button to apply torque.")
end

function reset_vehicle()
    -- Destroy all placed components
    for _, component in ipairs(placed_components) do
        component.body:destroy()
    end
    placed_components = {}
    joints = {}

    game_state = "building"
    camera_x = start_zone.x + start_zone.width / 2
    camera_y = 0

    print("Vehicle reset. Build again!")
end

function apply_motor_torque()
    if game_state ~= "testing" then
        return
    end

    -- Apply torque to all motor components
    for _, component in ipairs(placed_components) do
        if component.is_motor then
            component.body:apply_torque(component.motor_speed * 10)
        end
    end
end

function update(dt)
    if game_state == "testing" then
        -- Check for vehicle progress (camera follow)
        update_camera()

        -- Check for goal reached
        check_goal()

        -- Simulate joint constraints (simplified - proper joint API would be better)
        simulate_joints()
    end

    -- Update data bindings for rendering
    update_bindings()
end

function update_camera()
    -- Follow the center of mass of the vehicle
    if #placed_components == 0 then return end

    local sum_x = 0
    local sum_y = 0
    for _, comp in ipairs(placed_components) do
        local info = comp.body:get_info()
        sum_x = sum_x + info.pos_x
        sum_y = sum_y + info.pos_y
    end

    local target_x = sum_x / #placed_components
    local target_y = sum_y / #placed_components

    -- Smooth camera movement
    camera_x = camera_x + (target_x - camera_x) * 0.1
    camera_y = camera_y + (target_y - camera_y) * 0.1
end

function check_goal()
    -- Check if any component reached the goal
    for _, comp in ipairs(placed_components) do
        local info = comp.body:get_info()
        if info.pos_x >= goal_x - 2 then
            game_state = "success"
            print("SUCCESS! You reached the goal!")
            return
        end
    end
end

function simulate_joints()
    -- Simplified joint simulation using distance constraints
    -- In a full implementation, we'd use Box2D's joint API (revolute, distance, etc.)
    for _, joint in ipairs(joints) do
        if not joint.broken then
            local info1 = joint.comp1.body:get_info()
            local info2 = joint.comp2.body:get_info()

            local dx = info2.pos_x - info1.pos_x
            local dy = info2.pos_y - info1.pos_y
            local distance = math.sqrt(dx * dx + dy * dy)

            -- Calculate force magnitude based on distance from rest length
            local rest_length = math.sqrt(
                (info1.pos_x - joint.anchor_x)^2 + (info1.pos_y - joint.anchor_y)^2 +
                (info2.pos_x - joint.anchor_x)^2 + (info2.pos_y - joint.anchor_y)^2
            )

            local force_magnitude = (distance - rest_length) * 100 -- Spring constant

            -- Check if force exceeds breaking threshold
            if math.abs(force_magnitude) > joint.max_force then
                joint.broken = true
                print("Joint broke from impact!")
            else
                -- Apply constraint forces (simplified)
                -- Note: This is a placeholder - real joints would be handled by Box2D
                if distance > 0.01 then
                    local force_x = (dx / distance) * force_magnitude * 0.5
                    local force_y = (dy / distance) * force_magnitude * 0.5

                    -- Apply opposite forces to maintain constraint
                    joint.comp1.body:apply_force_to_center(force_x, force_y)
                    joint.comp2.body:apply_force_to_center(-force_x, -force_y)
                end
            end
        end
    end
end

function update_bindings()
    -- Create view objects for rendering
    local component_views = {}
    for _, comp in ipairs(placed_components) do
        local view = comp.body:create_view()
        table.insert(component_views, {
            view = view,
            type = comp.type,
            render_type = comp.render_type,
            radius = comp.radius,
            half_width = comp.half_width,
            half_height = comp.half_height,
            is_motor = comp.is_motor or false
        })
    end

    local terrain_views = {}
    for _, terrain in ipairs(terrain_bodies) do
        if terrain.is_goal then
            table.insert(terrain_views, {
                type = "goal",
                x = terrain.x,
                y = terrain.y
            })
        else
            table.insert(terrain_views, {
                type = "segment",
                x1 = terrain.x1,
                y1 = terrain.y1,
                x2 = terrain.x2,
                y2 = terrain.y2
            })
        end
    end

    local joint_views = {}
    for _, joint in ipairs(joints) do
        if not joint.broken then
            table.insert(joint_views, {
                x = joint.anchor_x,
                y = joint.anchor_y,
                is_motor = joint.is_motor
            })
        end
    end

    -- Bind data for UI
    datamodel.bind_table("vehicle_builder_state", {{
        components = component_views,
        terrain = terrain_views,
        joints = joint_views,
        camera_x = camera_x,
        camera_y = camera_y,
        camera_zoom = camera_zoom,
        game_state = game_state,
        selected_component = selected_component_type,
        start_zone = start_zone,
        goal_x = goal_x
    }})

    -- Bind component types for toolbox
    local toolbox_items = {}
    for _, def in ipairs(component_types) do
        table.insert(toolbox_items, {
            id = def.id,
            name = def.name,
            description = def.description,
            selected = (def.id == selected_component_type)
        })
    end
    datamodel.bind_table("toolbox", toolbox_items)
end

function shutdown()
    print("Vehicle Builder shutting down...")

    -- Cleanup
    for _, component in ipairs(placed_components) do
        component.body:destroy()
    end

    for _, terrain in ipairs(terrain_bodies) do
        terrain.body:destroy()
    end

    if world then
        world:destroy()
    end
end
