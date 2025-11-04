-- Physics Demo - Bouncing Balls with Box2D
-- Demonstrates the Box2D physics integration using lock-free architecture

-- Physics world and bodies
local world = nil
local ground = nil
local balls = {}

-- Status for UI display
local status = "Initializing..."

function update_status()
    datamodel.bind_table("demo_status", {{text = status}})
end

function startup()
    print("Physics Demo starting...")

    -- Create physics world with gravity pointing down
    local world_result, error_msg = physics.create_world(0, -10)
    if not world_result then
        print("Failed to create physics world: " .. error_msg)
        status = "Error: " .. error_msg
        return
    end

    world = world_result
    print("Created physics world with gravity (0, -10)")

    -- Create ground (static body)
    local ground_result, ground_error = world:create_body(physics.STATIC, 0, -10, 0)
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
        print("Created ground at y=-10 with box fixture")
    end

    -- Create some bouncing balls
    for i = 1, 5 do
        create_ball(-10 + i * 5, 10 + i * 2)
    end

    status = "Running - " .. #balls .. " balls"

    -- Initialize status display
    update_status()

    -- Bind body views BEFORE loading UI so render has data immediately
    update()

    -- Load UI - physics thread will push render state directly at 60Hz
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

function update(dt)
    -- Create lightweight views for rendering (can cross lua_State boundaries)
    local body_views = {}
    for i, ball_data in ipairs(balls) do
        -- Create view - lightweight userdata with just IDs
        table.insert(body_views, ball_data.body:create_view())
    end

    -- Bind views to data model - render function will read live properties at 60fps
    datamodel.bind_table("physics_bodies", {{bodies = body_views}})

    -- Also bind for UI list
    datamodel.bind_table("physics_state", {{bodies = body_views}})
end

function shutdown()
    print("Physics Demo shutting down...")

    -- Destroy balls
    for _, ball_data in ipairs(balls) do
        ball_data.body:destroy()
    end
    balls = {}

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

    -- Create new balls
    for i = 1, 5 do
        create_ball(-10 + i * 5, 10 + i * 2)
    end

    status = "Reset - " .. #balls .. " balls"
    update_status()
end

function on_add_ball()
    -- Add a ball at a random position
    local x = math.random(-15, 15)
    local y = math.random(5, 20)
    create_ball(x, y)

    status = "Running - " .. #balls .. " balls"
    update_status()
end

function on_impulse_all()
    -- Apply upward impulse to all balls
    for _, ball_data in ipairs(balls) do
        ball_data.body:apply_linear_impulse_to_center(0, 50)
    end

    print("Applied impulse to all balls")
end

function on_toggle_gravity()
    if not world then return end

    -- Get current world info
    local info = world:get_info()
    if not info or (info.error and info.error ~= "") then
        print("Failed to get world info: " .. (info and info.error or "unknown error"))
        return
    end

    -- Toggle gravity
    local new_gravity_y = info.gravity_y < 0 and 10 or -10
    world:set_gravity(0, new_gravity_y)

    status = string.format("Gravity: %.1f", new_gravity_y)
    update_status()

    print(string.format("Set gravity to (0, %.1f)", new_gravity_y))
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
