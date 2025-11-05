#pragma once

#include <sol/sol.hpp>

/**
 * PhysicsBindings - Lua bindings for Box2D physics
 *
 * LOCK-FREE ARCHITECTURE:
 * - All operations send commands to PhysicsThread via lock-free queue
 * - Query operations block using promise-in-command pattern
 * - Action operations are fire-and-forget (non-blocking)
 * - Worlds/bodies/fixtures referenced by integer IDs
 *
 * API DESIGN:
 * - physics.create_world(gravity_x, gravity_y) -> World handle
 * - world:create_body(type, x, y, angle) -> Body handle
 * - body:add_box_fixture(hw, hh, density, friction, restitution) -> fixture_id
 * - body:add_circle_fixture(radius, ...) -> fixture_id
 * - body:set_velocity(vx, vy) - fire and forget
 * - body:get_info() -> table (blocking query)
 *
 * USAGE EXAMPLE:
 * ```lua
 * local world = physics.create_world(0, -10)  -- gravity pointing down
 * local ground = world:create_body("static", 0, -10, 0)
 * ground:add_box_fixture(50, 1, 0, 0.3, 0)
 *
 * local ball = world:create_body("dynamic", 0, 5, 0)
 * ball:add_circle_fixture(0.5, 0, 0, 1.0, 0.3, 0.8)
 *
 * -- In update loop:
 * ball:apply_force_to_center(10, 0)
 * local info = ball:get_info()
 * print(info.pos_x, info.pos_y)
 * ```
 */
namespace PhysicsBindings {
    void SetupBindings(sol::state& lua);
    void SetupRenderBindings(lua_State* L);  // For RmlUI context (60Hz view creation)
}
