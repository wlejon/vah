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

-- Joint demonstrations
local joint_demos = {}
local joints = {}

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

    -- Create joint demonstrations
    create_joint_demos()

    status = "Running - " .. #balls .. " balls, " .. #coord_demos .. " coord demos, " .. #joints .. " joints"

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

function create_joint_demos()
    -- Joint demonstrations to showcase different joint types and configurations

    -- 1. PENDULUM - Simple Revolute Joint (hinge)
    -- Static anchor with dynamic pendulum bob
    local anchor1_result = world:create_body(physics.STATIC, -20, 0, 0)
    if anchor1_result then
        anchor1_result:add_circle_fixture(0.2, 0, 0, 1.0, 0.3, 0)
        local pendulum_result = world:create_body(physics.DYNAMIC, -20, 5, 0)
        if pendulum_result then
            pendulum_result:add_box_fixture(0.5, 2.0, 2.0, 0.3, 0.2)
            -- Create revolute joint at anchor point (no motor, no limits)
            local joint_result = world:create_revolute_joint(
                anchor1_result, pendulum_result,
                -20, 0,  -- anchor at static body position
                false, 0, 0  -- no motor
            )
            if joint_result then
                table.insert(joints, joint_result)
                table.insert(joint_demos, {
                    type = "pendulum",
                    anchor = anchor1_result,
                    body = pendulum_result,
                    joint = joint_result,
                    label = "Pendulum"
                })
                print("Created pendulum at (-20, 0)")
            end
        end
    end

    -- 2. MOTORIZED REVOLUTE - Revolute Joint with Motor
    -- Spinning platform powered by motor
    local anchor2_result = world:create_body(physics.STATIC, -10, 0, 0)
    if anchor2_result then
        anchor2_result:add_circle_fixture(0.2, 0, 0, 1.0, 0.3, 0)
        local platform_result = world:create_body(physics.DYNAMIC, -10, 0, 0)
        if platform_result then
            platform_result:add_box_fixture(3.0, 0.5, 2.0, 0.3, 0.2)
            -- Create revolute joint with motor (2 rad/s, max torque 50)
            local joint_result = world:create_revolute_joint(
                anchor2_result, platform_result,
                -10, 0,  -- anchor at center
                true, 2.0, 50.0  -- enable motor, 2 rad/s, 50 Nm
            )
            if joint_result then
                table.insert(joints, joint_result)
                table.insert(joint_demos, {
                    type = "motor",
                    anchor = anchor2_result,
                    body = platform_result,
                    joint = joint_result,
                    label = "Motor"
                })
                print("Created motorized platform at (-10, 0)")
            end
        end
    end

    -- 3. ANGLE-LIMITED REVOLUTE - Gate/Door
    -- Swings only between specific angles
    local anchor3_result = world:create_body(physics.STATIC, 0, 0, 0)
    if anchor3_result then
        anchor3_result:add_circle_fixture(0.2, 0, 0, 1.0, 0.3, 0)
        local gate_result = world:create_body(physics.DYNAMIC, 1.5, 0, 0)
        if gate_result then
            gate_result:add_box_fixture(3.0, 0.5, 2.0, 0.3, 0.2)
            -- Create revolute joint with angle limits (-π/4 to π/4)
            local joint_result = world:create_revolute_joint(
                anchor3_result, gate_result,
                0, 0,  -- anchor at left edge
                false, 0, 0  -- no motor
            )
            if joint_result then
                -- Enable angle limits: -45° to +45° (in radians)
                joint_result:enable_limit(true)
                joint_result:set_limits(-math.pi/4, math.pi/4)
                table.insert(joints, joint_result)
                table.insert(joint_demos, {
                    type = "gate",
                    anchor = anchor3_result,
                    body = gate_result,
                    joint = joint_result,
                    label = "Gate (±45°)"
                })
                print("Created angle-limited gate at (0, 0)")
            end
        end
    end

    -- 4. SOFT SPRING - Distance Joint with low frequency
    -- Creates bouncy, soft connection
    local spring_anchor1 = world:create_body(physics.STATIC, 10, 0, 0)
    if spring_anchor1 then
        spring_anchor1:add_circle_fixture(0.2, 0, 0, 1.0, 0.3, 0)
        local spring_bob1 = world:create_body(physics.DYNAMIC, 10, 5, 0)
        if spring_bob1 then
            spring_bob1:add_circle_fixture(0.5, 0, 0, 2.0, 0.3, 0.5)
            -- Soft spring: low frequency (2 Hz), medium damping (0.5)
            local joint_result = world:create_distance_joint(
                spring_anchor1, spring_bob1,
                10, 0,  -- anchor point on static body
                10, 5,  -- anchor point on dynamic body
                2.0,    -- frequency (Hz) - lower = softer
                0.5     -- damping ratio
            )
            if joint_result then
                table.insert(joints, joint_result)
                table.insert(joint_demos, {
                    type = "soft_spring",
                    anchor = spring_anchor1,
                    body = spring_bob1,
                    joint = joint_result,
                    label = "Soft Spring"
                })
                print("Created soft spring at (10, 0)")
            end
        end
    end

    -- 5. STIFF SPRING - Distance Joint with high frequency
    -- Creates rigid, stiff connection
    local spring_anchor2 = world:create_body(physics.STATIC, 20, 0, 0)
    if spring_anchor2 then
        spring_anchor2:add_circle_fixture(0.2, 0, 0, 1.0, 0.3, 0)
        local spring_bob2 = world:create_body(physics.DYNAMIC, 20, 5, 0)
        if spring_bob2 then
            spring_bob2:add_circle_fixture(0.5, 0, 0, 2.0, 0.3, 0.5)
            -- Stiff spring: high frequency (10 Hz), high damping (0.9)
            local joint_result = world:create_distance_joint(
                spring_anchor2, spring_bob2,
                20, 0,  -- anchor point on static body
                20, 5,  -- anchor point on dynamic body
                10.0,   -- frequency (Hz) - higher = stiffer
                0.9     -- damping ratio
            )
            if joint_result then
                table.insert(joints, joint_result)
                table.insert(joint_demos, {
                    type = "stiff_spring",
                    anchor = spring_anchor2,
                    body = spring_bob2,
                    joint = joint_result,
                    label = "Stiff Spring"
                })
                print("Created stiff spring at (20, 0)")
            end
        end
    end

    -- 6. SPRING CHAIN - Multiple bodies connected with distance joints
    -- Demonstrates compound joint systems
    local chain_bodies = {}
    local chain_start_x = -5
    local chain_start_y = -20
    local chain_segment_length = 2.0

    -- Create anchor point
    local chain_anchor = world:create_body(physics.STATIC, chain_start_x, chain_start_y, 0)
    if chain_anchor then
        chain_anchor:add_circle_fixture(0.2, 0, 0, 1.0, 0.3, 0)
        table.insert(chain_bodies, chain_anchor)

        -- Create 4 chain segments
        for i = 1, 4 do
            local segment_y = chain_start_y + i * chain_segment_length
            local segment = world:create_body(physics.DYNAMIC, chain_start_x, segment_y, 0)
            if segment then
                segment:add_box_fixture(0.4, 0.8, 1.0, 0.3, 0.3)
                table.insert(chain_bodies, segment)

                -- Connect to previous segment with distance joint
                local prev_body = chain_bodies[i]
                local prev_y = i == 1 and chain_start_y or (chain_start_y + (i-1) * chain_segment_length)
                local joint_result = world:create_distance_joint(
                    prev_body, segment,
                    chain_start_x, prev_y,  -- anchor on previous segment
                    chain_start_x, segment_y,  -- anchor on current segment
                    5.0,  -- medium frequency
                    0.7   -- medium-high damping
                )
                if joint_result then
                    table.insert(joints, joint_result)
                end
            end
        end

        table.insert(joint_demos, {
            type = "chain",
            bodies = chain_bodies,
            label = "Chain"
        })
        print("Created spring chain at (" .. chain_start_x .. ", " .. chain_start_y .. ")")
    end

    print("Created " .. #joints .. " joints total")
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

    -- Extract joint demo data for rendering
    local joint_data = {}
    for i, joint_demo in ipairs(joint_demos) do
        if joint_demo.type == "chain" then
            -- Chain has multiple bodies
            local body_ids = {}
            for _, body in ipairs(joint_demo.bodies) do
                local view = body:create_view()
                table.insert(body_ids, view.id)
            end
            table.insert(joint_data, {
                type = joint_demo.type,
                body_ids = body_ids,
                label = joint_demo.label
            })
        else
            -- Single joint with anchor and body
            local anchor_view = joint_demo.anchor:create_view()
            local body_view = joint_demo.body:create_view()
            table.insert(joint_data, {
                type = joint_demo.type,
                anchor_id = anchor_view.id,
                body_id = body_view.id,
                label = joint_demo.label
            })
        end
    end

    -- Bind plain tables to data model - these can cross thread boundaries
    datamodel.bind_table("physics_bodies", {{bodies = body_data}})
    datamodel.bind_table("physics_state", {{bodies = body_data}})
    datamodel.bind_table("coord_demos", {{world_id = world_id, demos = demo_data}})
    datamodel.bind_table("joint_demos", {{world_id = world_id, joints = joint_data}})
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

    -- Destroy joints first (before their bodies)
    for _, joint in ipairs(joints) do
        joint:destroy()
    end
    joints = {}

    -- Destroy joint demo bodies
    for _, joint_demo in ipairs(joint_demos) do
        if joint_demo.type == "chain" then
            for _, body in ipairs(joint_demo.bodies) do
                body:destroy()
            end
        else
            if joint_demo.anchor then
                joint_demo.anchor:destroy()
            end
            if joint_demo.body then
                joint_demo.body:destroy()
            end
        end
    end
    joint_demos = {}

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

    -- Destroy existing joints and joint demos
    for _, joint in ipairs(joints) do
        joint:destroy()
    end
    joints = {}

    for _, joint_demo in ipairs(joint_demos) do
        if joint_demo.type == "chain" then
            for _, body in ipairs(joint_demo.bodies) do
                body:destroy()
            end
        else
            if joint_demo.anchor then
                joint_demo.anchor:destroy()
            end
            if joint_demo.body then
                joint_demo.body:destroy()
            end
        end
    end
    joint_demos = {}

    -- Create new balls
    for i = 1, 5 do
        create_ball(-10 + i * 5, -15)  -- Spawn at same height
    end

    -- Recreate coordinate demos
    create_coord_demos()

    -- Recreate joint demos
    create_joint_demos()

    status = "Reset - " .. #balls .. " balls, " .. #coord_demos .. " coord demos, " .. #joints .. " joints"
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
