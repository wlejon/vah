#include "PhysicsBindings.h"
#include "PhysicsThread.h"
#include "Logger.h"
#include "Commands.h"
#include "LuaThread.h"
#include "LuaConversions.h"
#include <unordered_map>
#include <memory>

namespace PhysicsBindings {

// Global physics thread storage
// NOTE: In a production system, this would be managed by ThreadManager
static std::unordered_map<int, std::unique_ptr<PhysicsThread>> g_physics_threads;
static int g_next_world_id = 1;
static std::mutex g_physics_threads_mutex;  // ONLY for managing thread lifecycle, not for physics data

// Forward declarations
class World;
class Body;
class Joint;
class PhysicsBodyView;

// PhysicsBodyView - Lightweight view for rendering (can cross lua_State boundaries)
// Caches PhysicsThread pointer for lock-free, O(1) access to body state
class PhysicsBodyView {
public:
    PhysicsBodyView(int world_id, int body_id, PhysicsThread* physics_thread)
        : world_id_(world_id)
        , body_id_(body_id)
        , physics_thread_(physics_thread)
    {
    }

    int GetBodyId() const { return body_id_; }
    int GetWorldId() const { return world_id_; }

    // Live property getters - read from render state (lock-free, O(1) map lookup)
    const PhysicsBodyState* GetRenderState() const {
        if (!physics_thread_) {
            return nullptr;
        }

        const PhysicsWorldState* world_state = physics_thread_->GetRenderState();
        if (!world_state) {
            return nullptr;
        }

        // O(1) map lookup by body_id (no iteration, no mutex)
        auto it = world_state->bodies.find(body_id_);
        if (it != world_state->bodies.end()) {
            return &it->second;
        }
        return nullptr;
    }

    double GetPosX() const {
        auto state = GetRenderState();
        return state ? state->pos_x : 0.0;
    }

    double GetPosY() const {
        auto state = GetRenderState();
        return state ? state->pos_y : 0.0;
    }

    double GetAngle() const {
        auto state = GetRenderState();
        return state ? state->angle : 0.0;
    }

    double GetVelX() const {
        auto state = GetRenderState();
        return state ? state->vel_x : 0.0;
    }

    double GetVelY() const {
        auto state = GetRenderState();
        return state ? state->vel_y : 0.0;
    }

    double GetMass() const {
        auto state = GetRenderState();
        return state ? state->mass : 0.0;
    }

    bool GetAwake() const {
        auto state = GetRenderState();
        return state ? state->awake : false;
    }

private:
    int world_id_;
    int body_id_;
    PhysicsThread* physics_thread_;  // Cached pointer for lock-free access
};

// Body handle - stores body_id, world_id, and references to queues
// Properties read directly from physics thread's render state (lock-free double buffer)
class Body {
public:
    Body(int body_id, int world_id, PhysicsThread* physics_thread, LuaThread* lua_thread)
        : body_id_(body_id)
        , world_id_(world_id)
        , physics_thread_(physics_thread)
        , lua_thread_(lua_thread)
    {
    }

    int GetBodyId() const { return body_id_; }
    int GetWorldId() const { return world_id_; }
    PhysicsThread* GetPhysicsThread() const { return physics_thread_; }
    LuaThread* GetLuaThread() const { return lua_thread_; }

    // Create a lightweight view for rendering (can cross lua_State boundaries)
    PhysicsBodyView CreateView() const {
        return PhysicsBodyView(world_id_, body_id_, physics_thread_);
    }

private:
    int body_id_;
    int world_id_;
    PhysicsThread* physics_thread_;
    LuaThread* lua_thread_;
};

// World handle - stores world_id and physics thread pointer
class World {
public:
    World(int world_id, PhysicsThread* physics_thread, LuaThread* lua_thread)
        : world_id_(world_id)
        , physics_thread_(physics_thread)
        , lua_thread_(lua_thread)
    {
    }

    int GetWorldId() const { return world_id_; }
    PhysicsThread* GetPhysicsThread() const { return physics_thread_; }
    LuaThread* GetLuaThread() const { return lua_thread_; }

private:
    int world_id_;
    PhysicsThread* physics_thread_;
    LuaThread* lua_thread_;
};

// Joint handle - stores joint_id, world_id, and references to queues
class Joint {
public:
    Joint(int joint_id, int world_id, PhysicsThread* physics_thread, LuaThread* lua_thread)
        : joint_id_(joint_id)
        , world_id_(world_id)
        , physics_thread_(physics_thread)
        , lua_thread_(lua_thread)
    {
    }

    int GetJointId() const { return joint_id_; }
    int GetWorldId() const { return world_id_; }
    PhysicsThread* GetPhysicsThread() const { return physics_thread_; }
    LuaThread* GetLuaThread() const { return lua_thread_; }

private:
    int joint_id_;
    int world_id_;
    PhysicsThread* physics_thread_;
    LuaThread* lua_thread_;
};

// Create a physics world (blocking - waits for thread to start)
std::tuple<sol::object, std::string> CreateWorld(sol::this_state s, double gravity_x, double gravity_y) {
    sol::state_view lua(s);

    // Get LuaThread pointer from registry
    void* ptr = lua.registry()["__luathread_ptr"];
    LuaThread* lua_thread = static_cast<LuaThread*>(ptr);

    if (!lua_thread) {
        return {sol::nil, "No thread context available"};
    }

    try {
        // Allocate world ID
        int world_id;
        {
            std::lock_guard<std::mutex> lock(g_physics_threads_mutex);
            world_id = g_next_world_id++;
        }

        // Create physics thread
        auto physics_thread = std::make_unique<PhysicsThread>(
            world_id,
            gravity_x,
            gravity_y,
            nullptr  // Will route commands through physics thread's own queue
        );

        PhysicsThread* physics_thread_ptr = physics_thread.get();

        // Start the thread
        physics_thread->Start();

        // Store the thread
        {
            std::lock_guard<std::mutex> lock(g_physics_threads_mutex);
            g_physics_threads[world_id] = std::move(physics_thread);
        }

        // Create World handle
        auto world = std::make_shared<World>(world_id, physics_thread_ptr, lua_thread);

        LOG_INFO("Created physics world {} with gravity ({}, {})", world_id, gravity_x, gravity_y);

        return {sol::make_object(lua, world), ""};

    } catch (const std::exception& e) {
        return {sol::nil, std::string("Error creating physics world: ") + e.what()};
    }
}

// Destroy a physics world
void DestroyWorld(std::shared_ptr<World> world) {
    if (!world) return;

    int world_id = world->GetWorldId();

    std::lock_guard<std::mutex> lock(g_physics_threads_mutex);
    auto it = g_physics_threads.find(world_id);
    if (it != g_physics_threads.end()) {
        it->second->Stop();
        it->second->Join();
        g_physics_threads.erase(it);
        LOG_INFO("Destroyed physics world {}", world_id);
    }
}

// Create a body in the world (blocking - uses promise)
std::tuple<sol::object, std::string> CreateBody(sol::this_state s, std::shared_ptr<World> world,
                                                 const std::string& body_type,
                                                 double x, double y, double angle) {
    sol::state_view lua(s);

    if (!world) {
        return {sol::nil, "Invalid world"};
    }

    try {
        // Convert body type string to enum
        int type_enum = 2; // default to dynamic
        if (body_type == "static") type_enum = 0;
        else if (body_type == "kinematic") type_enum = 1;
        else if (body_type == "dynamic") type_enum = 2;

        // Create promise for blocking call
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        // Create command
        Commands::CreatePhysicsBody cmd;
        cmd.requesting_thread_id = world->GetLuaThread()->GetId();
        cmd.request_id = world->GetLuaThread()->AllocateRequestId();
        cmd.world_id = world->GetWorldId();
        cmd.body_type = type_enum;
        cmd.position_x = x;
        cmd.position_y = y;
        cmd.angle = angle;
        cmd.promise = promise;

        // Enqueue to physics thread
        world->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        // Block until physics thread responds
        PayloadMap response = future.get();

        // Extract body_id and error
        int64_t body_id_int = std::get<int64_t>(response.at("body_id"));
        std::string error = std::get<std::string>(response.at("error"));

        if (body_id_int < 0) {
            return {sol::nil, error};
        }

        // Create Body handle
        auto body = std::make_shared<Body>(
            static_cast<int>(body_id_int),
            world->GetWorldId(),
            world->GetPhysicsThread(),
            world->GetLuaThread()
        );

        return {sol::make_object(lua, body), ""};

    } catch (const std::exception& e) {
        return {sol::nil, std::string("Error creating body: ") + e.what()};
    }
}

// Destroy a body
void DestroyBody(std::shared_ptr<Body> body) {
    if (!body) return;

    Commands::DestroyPhysicsBody cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Add box fixture to body (blocking - returns fixture_id)
std::tuple<int, std::string> AddBoxFixture(std::shared_ptr<Body> body,
                                            double half_width, double half_height,
                                            sol::optional<double> density,
                                            sol::optional<double> friction,
                                            sol::optional<double> restitution,
                                            sol::optional<bool> is_sensor) {
    if (!body) {
        return {-1, "Invalid body"};
    }

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::AddBoxFixture cmd;
        cmd.requesting_thread_id = body->GetLuaThread()->GetId();
        cmd.request_id = body->GetLuaThread()->AllocateRequestId();
        cmd.world_id = body->GetWorldId();
        cmd.body_id = body->GetBodyId();
        cmd.half_width = half_width;
        cmd.half_height = half_height;
        cmd.density = density.value_or(1.0);
        cmd.friction = friction.value_or(0.3);
        cmd.restitution = restitution.value_or(0.0);
        cmd.is_sensor = is_sensor.value_or(false);
        cmd.promise = promise;

        body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        int64_t fixture_id = std::get<int64_t>(response.at("fixture_id"));
        std::string error = std::get<std::string>(response.at("error"));

        return {static_cast<int>(fixture_id), error};

    } catch (const std::exception& e) {
        return {-1, std::string("Error adding box fixture: ") + e.what()};
    }
}

// Add circle fixture to body (blocking - returns fixture_id)
std::tuple<int, std::string> AddCircleFixture(std::shared_ptr<Body> body,
                                               double radius,
                                               sol::optional<double> offset_x,
                                               sol::optional<double> offset_y,
                                               sol::optional<double> density,
                                               sol::optional<double> friction,
                                               sol::optional<double> restitution,
                                               sol::optional<bool> is_sensor) {
    if (!body) {
        return {-1, "Invalid body"};
    }

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::AddCircleFixture cmd;
        cmd.requesting_thread_id = body->GetLuaThread()->GetId();
        cmd.request_id = body->GetLuaThread()->AllocateRequestId();
        cmd.world_id = body->GetWorldId();
        cmd.body_id = body->GetBodyId();
        cmd.radius = radius;
        cmd.offset_x = offset_x.value_or(0.0);
        cmd.offset_y = offset_y.value_or(0.0);
        cmd.density = density.value_or(1.0);
        cmd.friction = friction.value_or(0.3);
        cmd.restitution = restitution.value_or(0.0);
        cmd.is_sensor = is_sensor.value_or(false);
        cmd.promise = promise;

        body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        int64_t fixture_id = std::get<int64_t>(response.at("fixture_id"));
        std::string error = std::get<std::string>(response.at("error"));

        return {static_cast<int>(fixture_id), error};

    } catch (const std::exception& e) {
        return {-1, std::string("Error adding circle fixture: ") + e.what()};
    }
}

// Add polygon fixture to body (blocking - returns fixture_id)
std::tuple<int, std::string> AddPolygonFixture(std::shared_ptr<Body> body,
                                                sol::table vertices,
                                                sol::optional<double> density,
                                                sol::optional<double> friction,
                                                sol::optional<double> restitution,
                                                sol::optional<bool> is_sensor) {
    if (!body) {
        return {-1, "Invalid body"};
    }

    try {
        // Convert Lua table to flat vertex array
        std::vector<double> vertex_data;
        for (size_t i = 1; i <= vertices.size(); i++) {
            sol::object value = vertices[i];
            if (value.is<double>()) {
                vertex_data.push_back(value.as<double>());
            } else if (value.is<int>()) {
                vertex_data.push_back(static_cast<double>(value.as<int>()));
            }
        }

        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::AddPolygonFixture cmd;
        cmd.requesting_thread_id = body->GetLuaThread()->GetId();
        cmd.request_id = body->GetLuaThread()->AllocateRequestId();
        cmd.world_id = body->GetWorldId();
        cmd.body_id = body->GetBodyId();
        cmd.vertices = std::move(vertex_data);
        cmd.density = density.value_or(1.0);
        cmd.friction = friction.value_or(0.3);
        cmd.restitution = restitution.value_or(0.0);
        cmd.is_sensor = is_sensor.value_or(false);
        cmd.promise = promise;

        body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        int64_t fixture_id = std::get<int64_t>(response.at("fixture_id"));
        std::string error = std::get<std::string>(response.at("error"));

        return {static_cast<int>(fixture_id), error};

    } catch (const std::exception& e) {
        return {-1, std::string("Error adding polygon fixture: ") + e.what()};
    }
}

// Set body velocity (fire and forget)
void SetBodyVelocity(std::shared_ptr<Body> body, double vx, double vy) {
    if (!body) return;

    Commands::SetBodyVelocity cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.velocity_x = vx;
    cmd.velocity_y = vy;

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Set body angular velocity (fire and forget)
void SetBodyAngularVelocity(std::shared_ptr<Body> body, double angular_velocity) {
    if (!body) return;

    Commands::SetBodyAngularVelocity cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.angular_velocity = angular_velocity;

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Set body transform (fire and forget)
void SetBodyTransform(std::shared_ptr<Body> body, double x, double y, double angle) {
    if (!body) return;

    Commands::SetBodyTransform cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.position_x = x;
    cmd.position_y = y;
    cmd.angle = angle;

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Apply force (fire and forget)
void ApplyForce(std::shared_ptr<Body> body, double fx, double fy, double px, double py, sol::optional<bool> wake) {
    if (!body) return;

    Commands::ApplyForce cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.force_x = fx;
    cmd.force_y = fy;
    cmd.point_x = px;
    cmd.point_y = py;
    cmd.wake = wake.value_or(true);

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Apply force to center (fire and forget)
void ApplyForceToCenter(std::shared_ptr<Body> body, double fx, double fy, sol::optional<bool> wake) {
    if (!body) return;

    Commands::ApplyForceToCenter cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.force_x = fx;
    cmd.force_y = fy;
    cmd.wake = wake.value_or(true);

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Apply torque (fire and forget)
void ApplyTorque(std::shared_ptr<Body> body, double torque, sol::optional<bool> wake) {
    if (!body) return;

    Commands::ApplyTorque cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.torque = torque;
    cmd.wake = wake.value_or(true);

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Apply linear impulse (fire and forget)
void ApplyLinearImpulse(std::shared_ptr<Body> body, double ix, double iy, double px, double py, sol::optional<bool> wake) {
    if (!body) return;

    Commands::ApplyLinearImpulse cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.impulse_x = ix;
    cmd.impulse_y = iy;
    cmd.point_x = px;
    cmd.point_y = py;
    cmd.wake = wake.value_or(true);

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Apply linear impulse to center (fire and forget)
void ApplyLinearImpulseToCenter(std::shared_ptr<Body> body, double ix, double iy, sol::optional<bool> wake) {
    if (!body) return;

    Commands::ApplyLinearImpulseToCenter cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.impulse_x = ix;
    cmd.impulse_y = iy;
    cmd.wake = wake.value_or(true);

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Apply angular impulse (fire and forget)
void ApplyAngularImpulse(std::shared_ptr<Body> body, double impulse, sol::optional<bool> wake) {
    if (!body) return;

    Commands::ApplyAngularImpulse cmd;
    cmd.world_id = body->GetWorldId();
    cmd.body_id = body->GetBodyId();
    cmd.impulse = impulse;
    cmd.wake = wake.value_or(true);

    body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Query body info (blocking)
sol::table GetBodyInfo(sol::this_state s, std::shared_ptr<Body> body) {
    sol::state_view lua(s);

    if (!body) {
        return lua.create_table();
    }

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QueryPhysicsBodyInfo cmd;
        cmd.requesting_thread_id = body->GetLuaThread()->GetId();
        cmd.request_id = body->GetLuaThread()->AllocateRequestId();
        cmd.world_id = body->GetWorldId();
        cmd.body_id = body->GetBodyId();
        cmd.promise = promise;

        body->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        return LuaConversions::PayloadMapToTable(lua, response);

    } catch (const std::exception& e) {
        LOG_ERROR("Error querying body info: {}", e.what());
        return lua.create_table();
    }
}

// Query world info (blocking)
sol::table GetWorldInfo(sol::this_state s, std::shared_ptr<World> world) {
    sol::state_view lua(s);

    if (!world) {
        return lua.create_table();
    }

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::QueryPhysicsWorldInfo cmd;
        cmd.requesting_thread_id = world->GetLuaThread()->GetId();
        cmd.request_id = world->GetLuaThread()->AllocateRequestId();
        cmd.world_id = world->GetWorldId();
        cmd.promise = promise;

        world->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        return LuaConversions::PayloadMapToTable(lua, response);

    } catch (const std::exception& e) {
        LOG_ERROR("Error querying world info: {}", e.what());
        return lua.create_table();
    }
}

// Set world gravity (fire and forget)
void SetGravity(std::shared_ptr<World> world, double gx, double gy) {
    if (!world) return;

    Commands::SetPhysicsGravity cmd;
    cmd.world_id = world->GetWorldId();
    cmd.gravity_x = gx;
    cmd.gravity_y = gy;

    world->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Create revolute joint (blocking - returns joint handle)
std::tuple<sol::object, std::string> CreateRevoluteJoint(sol::this_state s,
                                                           std::shared_ptr<World> world,
                                                           std::shared_ptr<Body> body_a,
                                                           std::shared_ptr<Body> body_b,
                                                           double anchor_x,
                                                           double anchor_y,
                                                           sol::optional<bool> enable_motor,
                                                           sol::optional<double> motor_speed,
                                                           sol::optional<double> max_motor_torque) {
    sol::state_view lua(s);

    if (!world || !body_a || !body_b) {
        return {sol::nil, "Invalid world or bodies"};
    }

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::CreateRevoluteJoint cmd;
        cmd.requesting_thread_id = world->GetLuaThread()->GetId();
        cmd.request_id = world->GetLuaThread()->AllocateRequestId();
        cmd.world_id = world->GetWorldId();
        cmd.body_a_id = body_a->GetBodyId();
        cmd.body_b_id = body_b->GetBodyId();
        cmd.anchor_x = anchor_x;
        cmd.anchor_y = anchor_y;
        cmd.enable_motor = enable_motor.value_or(false);
        cmd.motor_speed = motor_speed.value_or(0.0);
        cmd.max_motor_torque = max_motor_torque.value_or(0.0);
        cmd.enable_limit = false;
        cmd.lower_angle = 0.0;
        cmd.upper_angle = 0.0;
        cmd.promise = promise;

        world->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        int64_t joint_id_int = std::get<int64_t>(response.at("joint_id"));
        std::string error = std::get<std::string>(response.at("error"));

        if (joint_id_int < 0) {
            return {sol::nil, error};
        }

        auto joint = std::make_shared<Joint>(
            static_cast<int>(joint_id_int),
            world->GetWorldId(),
            world->GetPhysicsThread(),
            world->GetLuaThread()
        );

        return {sol::make_object(lua, joint), ""};

    } catch (const std::exception& e) {
        return {sol::nil, std::string("Error creating revolute joint: ") + e.what()};
    }
}

// Create distance joint (blocking - returns joint handle)
std::tuple<sol::object, std::string> CreateDistanceJoint(sol::this_state s,
                                                           std::shared_ptr<World> world,
                                                           std::shared_ptr<Body> body_a,
                                                           std::shared_ptr<Body> body_b,
                                                           double anchor_a_x,
                                                           double anchor_a_y,
                                                           double anchor_b_x,
                                                           double anchor_b_y,
                                                           sol::optional<double> frequency,
                                                           sol::optional<double> damping) {
    sol::state_view lua(s);

    if (!world || !body_a || !body_b) {
        return {sol::nil, "Invalid world or bodies"};
    }

    try {
        auto promise = std::make_shared<std::promise<PayloadMap>>();
        auto future = promise->get_future();

        Commands::CreateDistanceJoint cmd;
        cmd.requesting_thread_id = world->GetLuaThread()->GetId();
        cmd.request_id = world->GetLuaThread()->AllocateRequestId();
        cmd.world_id = world->GetWorldId();
        cmd.body_a_id = body_a->GetBodyId();
        cmd.body_b_id = body_b->GetBodyId();
        cmd.anchor_a_x = anchor_a_x;
        cmd.anchor_a_y = anchor_a_y;
        cmd.anchor_b_x = anchor_b_x;
        cmd.anchor_b_y = anchor_b_y;
        cmd.frequency = frequency.value_or(0.0);  // 0 = rigid
        cmd.damping_ratio = damping.value_or(0.0);
        cmd.promise = promise;

        world->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));

        PayloadMap response = future.get();

        int64_t joint_id_int = std::get<int64_t>(response.at("joint_id"));
        std::string error = std::get<std::string>(response.at("error"));

        if (joint_id_int < 0) {
            return {sol::nil, error};
        }

        auto joint = std::make_shared<Joint>(
            static_cast<int>(joint_id_int),
            world->GetWorldId(),
            world->GetPhysicsThread(),
            world->GetLuaThread()
        );

        return {sol::make_object(lua, joint), ""};

    } catch (const std::exception& e) {
        return {sol::nil, std::string("Error creating distance joint: ") + e.what()};
    }
}

// Destroy a joint
void DestroyJoint(std::shared_ptr<Joint> joint) {
    if (!joint) return;

    Commands::DestroyJoint cmd;
    cmd.world_id = joint->GetWorldId();
    cmd.joint_id = joint->GetJointId();

    joint->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// Set joint motor speed (fire and forget)
void SetJointMotorSpeed(std::shared_ptr<Joint> joint, double motor_speed) {
    if (!joint) return;

    Commands::SetJointMotorSpeed cmd;
    cmd.world_id = joint->GetWorldId();
    cmd.joint_id = joint->GetJointId();
    cmd.motor_speed = motor_speed;

    joint->GetPhysicsThread()->GetCommandQueue()->enqueue(std::move(cmd));
}

// No longer needed - Body objects now have live property bindings

void SetupBindings(sol::state& lua) {
    // Register PhysicsBodyView - lightweight view for rendering (can cross lua_State)
    lua.new_usertype<PhysicsBodyView>("PhysicsBodyView",
        sol::no_constructor,
        // Live property getters - read from render state (lock-free)
        "pos_x", sol::property(&PhysicsBodyView::GetPosX),
        "pos_y", sol::property(&PhysicsBodyView::GetPosY),
        "angle", sol::property(&PhysicsBodyView::GetAngle),
        "vel_x", sol::property(&PhysicsBodyView::GetVelX),
        "vel_y", sol::property(&PhysicsBodyView::GetVelY),
        "mass", sol::property(&PhysicsBodyView::GetMass),
        "awake", sol::property(&PhysicsBodyView::GetAwake),
        "id", sol::property(&PhysicsBodyView::GetBodyId)
    );

    // Register Body usertype
    lua.new_usertype<Body>("PhysicsBody",
        sol::no_constructor,
        "add_box_fixture", &AddBoxFixture,
        "add_circle_fixture", &AddCircleFixture,
        "add_polygon_fixture", &AddPolygonFixture,
        "set_velocity", &SetBodyVelocity,
        "set_angular_velocity", &SetBodyAngularVelocity,
        "set_transform", &SetBodyTransform,
        "apply_force", &ApplyForce,
        "apply_force_to_center", &ApplyForceToCenter,
        "apply_torque", &ApplyTorque,
        "apply_linear_impulse", &ApplyLinearImpulse,
        "apply_linear_impulse_to_center", &ApplyLinearImpulseToCenter,
        "apply_angular_impulse", &ApplyAngularImpulse,
        "get_info", &GetBodyInfo,
        "destroy", &DestroyBody,
        "create_view", &Body::CreateView  // Create view for rendering
    );

    // Register Joint usertype
    lua.new_usertype<Joint>("PhysicsJoint",
        sol::no_constructor,
        "set_motor_speed", &SetJointMotorSpeed,
        "destroy", &DestroyJoint
    );

    // Register World usertype
    lua.new_usertype<World>("PhysicsWorld",
        sol::no_constructor,
        "create_body", &CreateBody,
        "create_revolute_joint", &CreateRevoluteJoint,
        "create_distance_joint", &CreateDistanceJoint,
        "get_info", &GetWorldInfo,
        "set_gravity", &SetGravity,
        "destroy", &DestroyWorld,
        "id", sol::property(&World::GetWorldId)
    );

    // Register physics table with functions
    auto physics_table = lua.create_table();

    physics_table["create_world"] = &CreateWorld;

    // Body type constants
    physics_table["STATIC"] = "static";
    physics_table["KINEMATIC"] = "kinematic";
    physics_table["DYNAMIC"] = "dynamic";

    lua["physics"] = physics_table;

    LOG_INFO("Physics bindings registered (Box2D with lock-free threads)");
}

// Create a PhysicsBodyView from world_id and body_id (for render context)
std::tuple<sol::object, std::string> CreateBodyView(sol::this_state s, int world_id, int body_id) {
    sol::state_view lua(s);

    // Look up physics thread from global registry
    PhysicsThread* physics_thread = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_physics_threads_mutex);
        auto it = g_physics_threads.find(world_id);
        if (it != g_physics_threads.end()) {
            physics_thread = it->second.get();
        }
    }

    if (!physics_thread) {
        return {sol::nil, "World not found"};
    }

    // Create view (reads from render buffer at 60Hz)
    auto view = std::make_shared<PhysicsBodyView>(world_id, body_id, physics_thread);
    return {sol::make_object(lua, view), ""};
}

void SetupRenderBindings(lua_State* L) {
    sol::state_view lua(L);

    // Register PhysicsBodyView usertype (read-only properties)
    lua.new_usertype<PhysicsBodyView>("PhysicsBodyView",
        sol::no_constructor,
        // Live property getters - read from render state (lock-free)
        "pos_x", sol::property(&PhysicsBodyView::GetPosX),
        "pos_y", sol::property(&PhysicsBodyView::GetPosY),
        "angle", sol::property(&PhysicsBodyView::GetAngle),
        "vel_x", sol::property(&PhysicsBodyView::GetVelX),
        "vel_y", sol::property(&PhysicsBodyView::GetVelY),
        "mass", sol::property(&PhysicsBodyView::GetMass),
        "awake", sol::property(&PhysicsBodyView::GetAwake),
        "id", sol::property(&PhysicsBodyView::GetBodyId)
    );

    // Register minimal physics table for render context
    auto physics_table = lua.create_table();
    physics_table["create_body_view"] = &CreateBodyView;
    lua["physics"] = physics_table;

    LOG_INFO("Physics render bindings registered (60Hz view creation)");
}

} // namespace PhysicsBindings
