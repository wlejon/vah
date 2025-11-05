-- Physics Demo - Bouncing Balls with Box2D
-- Demonstrates the Box2D physics integration using lock-free architecture

-- Physics world and bodies
local world = nil
local world_id = nil  -- Store world ID for render context
local ground = nil
local balls = {}

-- Coordinate system demonstration shapes
local coord_demos = {}
local demo_time = 0  -- Track time for cyclical animations

-- Status for UI display
local status = "Initializing..."

function update_status()
    datamodel.bind_table("demo_status", {{text = status}})
end

function startup()
    print("Physics Demo starting...")

    -- Create physics world with gravity pointing down (Y-down coordinate system)
    local world_result, error_msg = physics.create_world(0, 10)
    if not world_result then
        print("Failed to create physics world: " .. error_msg)
        status = "Error: " .. error_msg
        return
    end

    world = world_result
    world_id = world.id
    print("Created physics world with gravity (0, 10) - Y-down coordinates, world_id=" .. world_id)

    -- Create ground (static body) - below origin in Y-down
    local ground_result, ground_error = world:create_body(physics.STATIC, 0, 10, 0)
    if not ground_result then
        print("Failed to create ground: " .. ground_error)
        status = "Error: " .. ground_error
        return
    end

    ground = ground_result

    -- Add box fixture to ground (50 units wide, 1 unit tall)
    local fixture_id, fixture_error = ground:add_box_fixture(50, 1, 0, 0.3, 0)
    if fixture_id < 0 then
        print("Failed to add ground fixture: " .. fixture_error)
    else
        print("Created ground at y=10 with box fixture (Y-down)")
    end

    -- Create some bouncing balls (above ground in Y-down = negative Y)
    for i = 1, 5 do
        create_ball(-10 + i * 5, -15)  -- Spawn at same height
    end

    -- Create coordinate system demonstration shapes
    create_coord_demos()

    status = "Running - " .. #balls .. " balls, " .. #coord_demos .. " coord demos"

    -- Initialize status display
    update_status()

    -- Bind initial body data BEFORE loading UI
    update()

    -- Load UI - update(dt) will be called automatically by the engine
    ui.load_document("ui/apps/physics_demo/physics_demo.rml", true, "physics_demo")
end

function create_ball(x, y)
    -- Create dynamic body
    local body_result, body_error = world:create_body(physics.DYNAMIC, x, y, 0)
    if not body_result then
        print("Failed to create ball: " .. body_error)
        return
    end

    local ball = body_result

    -- Add circle fixture (radius 0.5, density 1.0, friction 0.3, restitution 0.8 for bounciness)
    local fixture_id, fixture_error = ball:add_circle_fixture(0.5, 0, 0, 1.0, 0.3, 0.8)
    if fixture_id < 0 then
        print("Failed to add ball fixture: " .. fixture_error)
        return
    end

    table.insert(balls, {
        body = ball,
        id = #balls + 1
    })

    print(string.format("Created ball %d at (%.1f, %.1f)", #balls, x, y))
end

function create_coord_demos()
    -- Create spinning wheels (kinematic bodies with constant angular velocity)
    -- Note: In Y-down, positive rotation = clockwise (natural wheel forward roll)

    -- Wheel 1: Clockwise spinner at left
    local wheel1_result, wheel1_error = world:create_body(physics.KINEMATIC, -15, -5, 0)
    if wheel1_result then
        wheel1_result:add_circle_fixture(1.0, 0, 0, 1.0, 0.3, 0)
        wheel1_result:set_angular_velocity(2.0)  -- Clockwise in Y-down
        table.insert(coord_demos, {
            body = wheel1_result,
            type = "wheel_cw",
            label = "CW"
        })
        print("Created clockwise wheel at (-15, -5) Y-down")
    end

    -- Wheel 2: Counter-clockwise spinner at right
    local wheel2_result, wheel2_error = world:create_body(physics.KINEMATIC, 15, -5, 0)
    if wheel2_result then
        wheel2_result:add_circle_fixture(1.0, 0, 0, 1.0, 0.3, 0)
        wheel2_result:set_angular_velocity(-2.0)  -- Counter-clockwise in Y-down
        table.insert(coord_demos, {
            body = wheel2_result,
            type = "wheel_ccw",
            label = "CCW"
        })
        print("Created counter-clockwise wheel at (15, -5) Y-down")
    end

    -- Horizontal movers (left-right oscillation)
    local h_mover1_result, h_error1 = world:create_body(physics.KINEMATIC, -10, -15, 0)
    if h_mover1_result then
        h_mover1_result:add_box_fixture(0.75, 0.75, 1.0, 0.3, 0)
        table.insert(coord_demos, {
            body = h_mover1_result,
            type = "h_mover",
            label = "H",
            center_x = -10,
            amplitude = 5,
            frequency = 0.5
        })
        print("Created horizontal mover at (-10, -15) Y-down")
    end

    -- Vertical mover (up-down oscillation)
    local v_mover1_result, v_error1 = world:create_body(physics.KINEMATIC, 0, -10, 0)
    if v_mover1_result then
        v_mover1_result:add_box_fixture(0.75, 0.75, 1.0, 0.3, 0)
        table.insert(coord_demos, {
            body = v_mover1_result,
            type = "v_mover",
            label = "V",
            center_y = -10,
            amplitude = 5,
            frequency = 0.4
        })
        print("Created vertical mover at (0, -10) Y-down")
    end

    -- Diagonal mover (showing both X and Y)
    local d_mover1_result, d_error1 = world:create_body(physics.KINEMATIC, 10, -15, 0)
    if d_mover1_result then
        d_mover1_result:add_box_fixture(0.75, 0.75, 1.0, 0.3, 0)
        table.insert(coord_demos, {
            body = d_mover1_result,
            type = "d_mover",
            label = "D",
            center_x = 10,
            center_y = -15,
            amplitude = 3,
            frequency = 0.6
        })
        print("Created diagonal mover at (10, -15) Y-down")
    end
end

function update(dt)
    -- Update time for cyclical animations
    demo_time = demo_time + (dt or 0.033)  -- Default to ~30Hz if dt is nil

    -- Update coordinate demo movers with cyclical motion
    -- Only update velocity - physics thread interpolates position smoothly at 60Hz
    for i, demo_data in ipairs(coord_demos) do
        if demo_data.type == "h_mover" then
            -- Horizontal oscillation: x(t) = center_x + amplitude * sin(2π * frequency * t)
            -- Velocity: vx(t) = amplitude * 2π * frequency * cos(2π * frequency * t)
            local omega = 2 * math.pi * demo_data.frequency
            local velocity_x = demo_data.amplitude * omega * math.cos(omega * demo_time)
            demo_data.body:set_velocity(velocity_x, 0)
        elseif demo_data.type == "v_mover" then
            -- Vertical oscillation: y(t) = center_y + amplitude * sin(2π * frequency * t)
            -- Velocity: vy(t) = amplitude * 2π * frequency * cos(2π * frequency * t)
            local omega = 2 * math.pi * demo_data.frequency
            local velocity_y = demo_data.amplitude * omega * math.cos(omega * demo_time)
            demo_data.body:set_velocity(0, velocity_y)
        elseif demo_data.type == "d_mover" then
            -- Circular motion: x(t) = center_x + amplitude * cos(2π * frequency * t)
            --                   y(t) = center_y + amplitude * sin(2π * frequency * t)
            -- Velocity: vx(t) = -amplitude * 2π * frequency * sin(2π * frequency * t)
            --           vy(t) =  amplitude * 2π * frequency * cos(2π * frequency * t)
            local omega = 2 * math.pi * demo_data.frequency
            local velocity_x = -demo_data.amplitude * omega * math.sin(omega * demo_time)
            local velocity_y = demo_data.amplitude * omega * math.cos(omega * demo_time)
            demo_data.body:set_velocity(velocity_x, velocity_y)
        end
    end

    -- Extract physics properties into plain tables for data model
    -- (DynamicValue can't hold userdata, so we need to convert to primitives)
    local body_data = {}
    for i, ball_data in ipairs(balls) do
        -- Create view to access current physics state
        local view = ball_data.body:create_view()

        -- Extract all properties into a plain table
        table.insert(body_data, {
            id = view.id,
            pos_x = view.pos_x,
            pos_y = view.pos_y,
            angle = view.angle,
            vel_x = view.vel_x,
            vel_y = view.vel_y,
            mass = view.mass,
            awake = view.awake
        })
    end

    -- Extract coordinate demo metadata (IDs only - render will create views at 60Hz)
    local demo_data = {}
    for i, demo in ipairs(coord_demos) do
        local view = demo.body:create_view()
        table.insert(demo_data, {
            body_id = view.id,
            type = demo.type,
            label = demo.label
        })
    end

    -- Bind plain tables to data model - these can cross thread boundaries
    datamodel.bind_table("physics_bodies", {{bodies = body_data}})
    datamodel.bind_table("physics_state", {{bodies = body_data}})
    datamodel.bind_table("coord_demos", {{world_id = world_id, demos = demo_data}})
end

function shutdown()
    print("Physics Demo shutting down...")

    -- Destroy balls
    for _, ball_data in ipairs(balls) do
        ball_data.body:destroy()
    end
    balls = {}

    -- Destroy coordinate demos
    for _, demo_data in ipairs(coord_demos) do
        demo_data.body:destroy()
    end
    coord_demos = {}

    -- Destroy ground
    if ground then
        ground:destroy()
        ground = nil
    end

    -- Destroy world
    if world then
        world:destroy()
        world = nil
    end

    print("Physics Demo shutdown complete")
end

-- UI event handlers
function on_reset()
    print("Resetting simulation...")

    -- Destroy existing balls
    for _, ball_data in ipairs(balls) do
        ball_data.body:destroy()
    end
    balls = {}

    -- Destroy existing coord demos
    for _, demo_data in ipairs(coord_demos) do
        demo_data.body:destroy()
    end
    coord_demos = {}
    demo_time = 0

    -- Create new balls
    for i = 1, 5 do
        create_ball(-10 + i * 5, -15)  -- Spawn at same height
    end

    -- Recreate coordinate demos
    create_coord_demos()

    status = "Reset - " .. #balls .. " balls, " .. #coord_demos .. " coord demos"
    update_status()
end

function on_add_ball()
    -- Add a ball at a random position (Y-down: negative Y is above ground)
    local x = math.random(-15, 15)
    local y = -math.random(5, 20)  -- Negative Y for above ground
    create_ball(x, y)

    status = "Running - " .. #balls .. " balls"
    update_status()
end

function on_impulse_all()
    -- Apply upward impulse to all balls (Y-down: negative impulse = upward)
    for _, ball_data in ipairs(balls) do
        ball_data.body:apply_linear_impulse_to_center(0, -50)
    end

    print("Applied upward impulse to all balls")
end

function on_toggle_gravity()
    if not world then return end

    -- Get current world info
    local info = world:get_info()
    if not info or (info.error and info.error ~= "") then
        print("Failed to get world info: " .. (info and info.error or "unknown error"))
        return
    end

    -- Toggle gravity (Y-down: positive = down, negative = up)
    local new_gravity_y = info.gravity_y > 0 and -10 or 10
    world:set_gravity(0, new_gravity_y)

    local direction = new_gravity_y > 0 and "down" or "up"
    status = string.format("Gravity: %.1f (%s)", new_gravity_y, direction)
    update_status()

    print(string.format("Set gravity to (0, %.1f) - %s", new_gravity_y, direction))
end

-- Register event handlers for UI interactions
event.register("reset_physics", function(payload)
    on_reset()
end)

event.register("add_ball", function(payload)
    on_add_ball()
end)

event.register("impulse_all", function(payload)
    on_impulse_all()
end)

event.register("toggle_gravity", function(payload)
    on_toggle_gravity()
end)
