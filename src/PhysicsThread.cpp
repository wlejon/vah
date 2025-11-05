#include "PhysicsThread.h"
#include "Logger.h"
#include <chrono>
#include <box2d/box2d.h>

PhysicsThread::PhysicsThread(int world_id,
                             double gravity_x,
                             double gravity_y,
                             moodycamel::ConcurrentQueue<Command>* command_queue)
    : world_id_(world_id)
    , state_(State::Starting)
    , should_stop_(false)
    , is_paused_(false)
    , main_command_queue_(command_queue)
    , next_body_id_(1)
    , next_fixture_id_(1)
    , next_joint_id_(1)
    , time_step_(1.0f / 60.0f)  // 60Hz default
    , velocity_iterations_(8)
    , position_iterations_(3)
{
    // Create Box2D world with gravity (v3.x API)
    b2WorldDef worldDef = b2DefaultWorldDef();
    worldDef.gravity = {static_cast<float>(gravity_x), static_cast<float>(gravity_y)};
    world_ = std::make_unique<b2WorldId>(b2CreateWorld(&worldDef));

    LOG_INFO("PhysicsThread {} created with gravity ({}, {})", world_id_, gravity_x, gravity_y);
}

PhysicsThread::~PhysicsThread() {
    Stop();
    Join();

    // Destroy Box2D world
    if (world_) {
        b2DestroyWorld(*world_);
    }
}

void PhysicsThread::Start() {
    thread_ = std::make_unique<std::thread>(&PhysicsThread::ThreadMain, this);
}

void PhysicsThread::Stop() {
    should_stop_.store(true, std::memory_order_release);
    state_.store(State::Stopping, std::memory_order_release);
}

void PhysicsThread::Pause() {
    is_paused_.store(true, std::memory_order_release);
    state_.store(State::Paused, std::memory_order_release);
}

void PhysicsThread::Resume() {
    is_paused_.store(false, std::memory_order_release);
    state_.store(State::Running, std::memory_order_release);
}

void PhysicsThread::Join() {
    if (thread_ && thread_->joinable()) {
        thread_->join();
    }
}

void PhysicsThread::ThreadMain() {
    try {
        state_.store(State::Running, std::memory_order_release);
        LOG_INFO("PhysicsThread {} running", world_id_);

        // Fixed timestep simulation
        auto frame_duration = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::duration<float>(time_step_)
        );
        auto next_frame_time = std::chrono::steady_clock::now();

        while (!should_stop_.load(std::memory_order_acquire)) {
            // Handle pause
            while (is_paused_.load(std::memory_order_acquire) && !should_stop_.load(std::memory_order_acquire)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }

            if (should_stop_.load(std::memory_order_acquire)) break;

            // Process all pending commands before simulation step
            ProcessCommands();

            // Step the physics simulation
            SimulationStep(time_step_);

            // Wait for next frame
            next_frame_time += frame_duration;
            std::this_thread::sleep_until(next_frame_time);
        }

        state_.store(State::Stopped, std::memory_order_release);
        LOG_INFO("PhysicsThread {} stopped normally", world_id_);

    } catch (const std::exception& e) {
        error_message_ = e.what();
        LOG_ERROR("PhysicsThread {} exception: {}", world_id_, error_message_);
        state_.store(State::Error, std::memory_order_release);
    }
}

void PhysicsThread::ProcessCommands() {
    // Dequeue all commands from physics-specific queue
    Command cmd;
    while (physics_command_queue_.try_dequeue(cmd)) {
        std::visit([this](auto&& command) {
            using T = std::decay_t<decltype(command)>;

            if constexpr (std::is_same_v<T, Commands::CreatePhysicsBody>) {
                HandleCreateBody(command);
            }
            else if constexpr (std::is_same_v<T, Commands::DestroyPhysicsBody>) {
                HandleDestroyBody(command);
            }
            else if constexpr (std::is_same_v<T, Commands::AddBoxFixture>) {
                HandleAddBoxFixture(command);
            }
            else if constexpr (std::is_same_v<T, Commands::AddCircleFixture>) {
                HandleAddCircleFixture(command);
            }
            else if constexpr (std::is_same_v<T, Commands::AddPolygonFixture>) {
                HandleAddPolygonFixture(command);
            }
            else if constexpr (std::is_same_v<T, Commands::SetBodyVelocity>) {
                HandleSetBodyVelocity(command);
            }
            else if constexpr (std::is_same_v<T, Commands::SetBodyAngularVelocity>) {
                HandleSetBodyAngularVelocity(command);
            }
            else if constexpr (std::is_same_v<T, Commands::SetBodyTransform>) {
                HandleSetBodyTransform(command);
            }
            else if constexpr (std::is_same_v<T, Commands::ApplyForce>) {
                HandleApplyForce(command);
            }
            else if constexpr (std::is_same_v<T, Commands::ApplyForceToCenter>) {
                HandleApplyForceToCenter(command);
            }
            else if constexpr (std::is_same_v<T, Commands::ApplyTorque>) {
                HandleApplyTorque(command);
            }
            else if constexpr (std::is_same_v<T, Commands::ApplyLinearImpulse>) {
                HandleApplyLinearImpulse(command);
            }
            else if constexpr (std::is_same_v<T, Commands::ApplyLinearImpulseToCenter>) {
                HandleApplyLinearImpulseToCenter(command);
            }
            else if constexpr (std::is_same_v<T, Commands::ApplyAngularImpulse>) {
                HandleApplyAngularImpulse(command);
            }
            else if constexpr (std::is_same_v<T, Commands::QueryPhysicsBodyInfo>) {
                HandleQueryBodyInfo(command);
            }
            else if constexpr (std::is_same_v<T, Commands::QueryPhysicsWorldInfo>) {
                HandleQueryWorldInfo(command);
            }
            else if constexpr (std::is_same_v<T, Commands::SetPhysicsGravity>) {
                HandleSetGravity(command);
            }
            else if constexpr (std::is_same_v<T, Commands::CreateRevoluteJoint>) {
                HandleCreateRevoluteJoint(command);
            }
            else if constexpr (std::is_same_v<T, Commands::CreateDistanceJoint>) {
                HandleCreateDistanceJoint(command);
            }
            else if constexpr (std::is_same_v<T, Commands::DestroyJoint>) {
                HandleDestroyJoint(command);
            }
            else if constexpr (std::is_same_v<T, Commands::SetJointMotorSpeed>) {
                HandleSetJointMotorSpeed(command);
            }
        }, cmd);
    }
}

void PhysicsThread::SimulationStep(float dt) {
    if (world_) {
        b2World_Step(*world_, dt, velocity_iterations_);

        // Update render state (lock-free double buffer)
        UpdateRenderState();
    }
}

void PhysicsThread::UpdateRenderState() {
    // Write to write buffer
    PhysicsWorldState& write_buf = render_buffers_[write_buffer_index_];
    write_buf.bodies.clear();  // Clear map
    write_buf.world_id = world_id_;

    // Get gravity
    if (world_) {
        b2Vec2 gravity = b2World_GetGravity(*world_);
        write_buf.gravity_x = static_cast<double>(gravity.x);
        write_buf.gravity_y = static_cast<double>(gravity.y);
    }

    // Collect all body states - now using map for O(1) lookup
    for (const auto& [body_id, b2_body_id] : bodies_) {
        if (B2_IS_NON_NULL(b2_body_id)) {
            PhysicsBodyState state;
            state.body_id = body_id;

            b2Vec2 pos = b2Body_GetPosition(b2_body_id);
            b2Rot rot = b2Body_GetRotation(b2_body_id);
            b2Vec2 vel = b2Body_GetLinearVelocity(b2_body_id);
            float mass = b2Body_GetMass(b2_body_id);
            bool awake = b2Body_IsAwake(b2_body_id);

            state.pos_x = static_cast<double>(pos.x);
            state.pos_y = static_cast<double>(pos.y);
            state.angle = static_cast<double>(b2Rot_GetAngle(rot));
            state.vel_x = static_cast<double>(vel.x);
            state.vel_y = static_cast<double>(vel.y);
            state.mass = static_cast<double>(mass);
            state.awake = awake;

            write_buf.bodies[body_id] = state;  // Insert/update in map by body_id
        }
    }

    // Atomic swap: make write buffer the new read buffer
    // This is lock-free and thread-safe
    int old_read_idx = render_buffer_index_.exchange(write_buffer_index_, std::memory_order_release);
    write_buffer_index_ = old_read_idx;
}

void PhysicsThread::HandleCreateBody(Commands::CreatePhysicsBody& cmd) {
    try {
        if (cmd.world_id != world_id_) {
            PayloadMap response;
            response["body_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("World ID mismatch");
            cmd.promise->set_value(std::move(response));
            return;
        }

        // Box2D v3 API: Create body definition
        b2BodyDef bodyDef = b2DefaultBodyDef();

        // Set body type
        switch (cmd.body_type) {
            case 0: bodyDef.type = b2_staticBody; break;
            case 1: bodyDef.type = b2_kinematicBody; break;
            case 2: bodyDef.type = b2_dynamicBody; break;
            default: bodyDef.type = b2_dynamicBody; break;
        }

        bodyDef.position = {static_cast<float>(cmd.position_x), static_cast<float>(cmd.position_y)};
        bodyDef.rotation = b2MakeRot(static_cast<float>(cmd.angle));

        // Create body using Box2D v3 API
        b2BodyId bodyId = b2CreateBody(*world_, &bodyDef);

        if (!B2_IS_NON_NULL(bodyId)) {
            PayloadMap response;
            response["body_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Failed to create body");
            cmd.promise->set_value(std::move(response));
            return;
        }

        int body_id = next_body_id_++;
        bodies_[body_id] = bodyId;

        PayloadMap response;
        response["body_id"] = static_cast<int64_t>(body_id);
        response["error"] = std::string("");
        cmd.promise->set_value(std::move(response));

        LOG_DEBUG("PhysicsThread {}: Created body {} at ({}, {})", world_id_, body_id, cmd.position_x, cmd.position_y);

    } catch (const std::exception& e) {
        PayloadMap response;
        response["body_id"] = static_cast<int64_t>(-1);
        response["error"] = std::string(e.what());
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleDestroyBody(Commands::DestroyPhysicsBody& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end()) {
        if (B2_IS_NON_NULL(it->second)) {
            b2DestroyBody(it->second);
        }
        bodies_.erase(it);
        LOG_DEBUG("PhysicsThread {}: Destroyed body {}", world_id_, cmd.body_id);
    }
}

void PhysicsThread::HandleAddBoxFixture(Commands::AddBoxFixture& cmd) {
    try {
        if (cmd.world_id != world_id_) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("World ID mismatch");
            cmd.promise->set_value(std::move(response));
            return;
        }

        auto body_it = bodies_.find(cmd.body_id);
        if (body_it == bodies_.end()) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Body not found");
            cmd.promise->set_value(std::move(response));
            return;
        }

        // Box2D v3: Create polygon shape as box
        b2Polygon box = b2MakeBox(static_cast<float>(cmd.half_width), static_cast<float>(cmd.half_height));

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = static_cast<float>(cmd.density);
        shapeDef.material.friction = static_cast<float>(cmd.friction);
        shapeDef.material.restitution = static_cast<float>(cmd.restitution);
        shapeDef.isSensor = cmd.is_sensor;

        b2ShapeId shapeId = b2CreatePolygonShape(body_it->second, &shapeDef, &box);

        if (!B2_IS_NON_NULL(shapeId)) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Failed to create shape");
            cmd.promise->set_value(std::move(response));
            return;
        }

        int fixture_id = next_fixture_id_++;
        fixtures_[fixture_id] = shapeId;

        PayloadMap response;
        response["fixture_id"] = static_cast<int64_t>(fixture_id);
        response["error"] = std::string("");
        cmd.promise->set_value(std::move(response));

    } catch (const std::exception& e) {
        PayloadMap response;
        response["fixture_id"] = static_cast<int64_t>(-1);
        response["error"] = std::string(e.what());
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleAddCircleFixture(Commands::AddCircleFixture& cmd) {
    try {
        if (cmd.world_id != world_id_) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("World ID mismatch");
            cmd.promise->set_value(std::move(response));
            return;
        }

        auto body_it = bodies_.find(cmd.body_id);
        if (body_it == bodies_.end()) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Body not found");
            cmd.promise->set_value(std::move(response));
            return;
        }

        // Box2D v3: Create circle shape
        b2Circle circle;
        circle.center = {static_cast<float>(cmd.offset_x), static_cast<float>(cmd.offset_y)};
        circle.radius = static_cast<float>(cmd.radius);

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = static_cast<float>(cmd.density);
        shapeDef.material.friction = static_cast<float>(cmd.friction);
        shapeDef.material.restitution = static_cast<float>(cmd.restitution);
        shapeDef.isSensor = cmd.is_sensor;

        b2ShapeId shapeId = b2CreateCircleShape(body_it->second, &shapeDef, &circle);

        if (!B2_IS_NON_NULL(shapeId)) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Failed to create shape");
            cmd.promise->set_value(std::move(response));
            return;
        }

        int fixture_id = next_fixture_id_++;
        fixtures_[fixture_id] = shapeId;

        PayloadMap response;
        response["fixture_id"] = static_cast<int64_t>(fixture_id);
        response["error"] = std::string("");
        cmd.promise->set_value(std::move(response));

    } catch (const std::exception& e) {
        PayloadMap response;
        response["fixture_id"] = static_cast<int64_t>(-1);
        response["error"] = std::string(e.what());
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleAddPolygonFixture(Commands::AddPolygonFixture& cmd) {
    try {
        if (cmd.world_id != world_id_) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("World ID mismatch");
            cmd.promise->set_value(std::move(response));
            return;
        }

        auto body_it = bodies_.find(cmd.body_id);
        if (body_it == bodies_.end()) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Body not found");
            cmd.promise->set_value(std::move(response));
            return;
        }

        // Convert flat array to b2Vec2 array
        if (cmd.vertices.size() % 2 != 0 || cmd.vertices.size() < 6 || cmd.vertices.size() > 16) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Invalid vertex count (must be 3-8 vertices, even number of coordinates)");
            cmd.promise->set_value(std::move(response));
            return;
        }

        b2Vec2 vertices[8];
        int vertex_count = static_cast<int>(cmd.vertices.size() / 2);
        for (int i = 0; i < vertex_count; i++) {
            vertices[i] = {static_cast<float>(cmd.vertices[i * 2]), static_cast<float>(cmd.vertices[i * 2 + 1])};
        }

        // Create hull from vertices
        b2Hull hull = b2ComputeHull(vertices, vertex_count);
        b2Polygon polygon = b2MakePolygon(&hull, 0.0f);

        b2ShapeDef shapeDef = b2DefaultShapeDef();
        shapeDef.density = static_cast<float>(cmd.density);
        shapeDef.material.friction = static_cast<float>(cmd.friction);
        shapeDef.material.restitution = static_cast<float>(cmd.restitution);
        shapeDef.isSensor = cmd.is_sensor;

        b2ShapeId shapeId = b2CreatePolygonShape(body_it->second, &shapeDef, &polygon);

        if (!B2_IS_NON_NULL(shapeId)) {
            PayloadMap response;
            response["fixture_id"] = static_cast<int64_t>(-1);
            response["error"] = std::string("Failed to create shape");
            cmd.promise->set_value(std::move(response));
            return;
        }

        int fixture_id = next_fixture_id_++;
        fixtures_[fixture_id] = shapeId;

        PayloadMap response;
        response["fixture_id"] = static_cast<int64_t>(fixture_id);
        response["error"] = std::string("");
        cmd.promise->set_value(std::move(response));

    } catch (const std::exception& e) {
        PayloadMap response;
        response["fixture_id"] = static_cast<int64_t>(-1);
        response["error"] = std::string(e.what());
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleSetBodyVelocity(Commands::SetBodyVelocity& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Vec2 velocity = {static_cast<float>(cmd.velocity_x), static_cast<float>(cmd.velocity_y)};
        b2Body_SetLinearVelocity(it->second, velocity);
    }
}

void PhysicsThread::HandleSetBodyAngularVelocity(Commands::SetBodyAngularVelocity& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Body_SetAngularVelocity(it->second, static_cast<float>(cmd.angular_velocity));
    }
}

void PhysicsThread::HandleSetBodyTransform(Commands::SetBodyTransform& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Vec2 position = {static_cast<float>(cmd.position_x), static_cast<float>(cmd.position_y)};
        b2Rot rotation = b2MakeRot(static_cast<float>(cmd.angle));
        b2Body_SetTransform(it->second, position, rotation);
    }
}

void PhysicsThread::HandleApplyForce(Commands::ApplyForce& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Vec2 force = {static_cast<float>(cmd.force_x), static_cast<float>(cmd.force_y)};
        b2Vec2 point = {static_cast<float>(cmd.point_x), static_cast<float>(cmd.point_y)};
        b2Body_ApplyForce(it->second, force, point, cmd.wake);
    }
}

void PhysicsThread::HandleApplyForceToCenter(Commands::ApplyForceToCenter& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Vec2 force = {static_cast<float>(cmd.force_x), static_cast<float>(cmd.force_y)};
        b2Body_ApplyForceToCenter(it->second, force, cmd.wake);
    }
}

void PhysicsThread::HandleApplyTorque(Commands::ApplyTorque& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Body_ApplyTorque(it->second, static_cast<float>(cmd.torque), cmd.wake);
    }
}

void PhysicsThread::HandleApplyLinearImpulse(Commands::ApplyLinearImpulse& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Vec2 impulse = {static_cast<float>(cmd.impulse_x), static_cast<float>(cmd.impulse_y)};
        b2Vec2 point = {static_cast<float>(cmd.point_x), static_cast<float>(cmd.point_y)};
        b2Body_ApplyLinearImpulse(it->second, impulse, point, cmd.wake);
    }
}

void PhysicsThread::HandleApplyLinearImpulseToCenter(Commands::ApplyLinearImpulseToCenter& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Vec2 impulse = {static_cast<float>(cmd.impulse_x), static_cast<float>(cmd.impulse_y)};
        b2Body_ApplyLinearImpulseToCenter(it->second, impulse, cmd.wake);
    }
}

void PhysicsThread::HandleApplyAngularImpulse(Commands::ApplyAngularImpulse& cmd) {
    if (cmd.world_id != world_id_) return;

    auto it = bodies_.find(cmd.body_id);
    if (it != bodies_.end() && B2_IS_NON_NULL(it->second)) {
        b2Body_ApplyAngularImpulse(it->second, static_cast<float>(cmd.impulse), cmd.wake);
    }
}

void PhysicsThread::HandleQueryBodyInfo(Commands::QueryPhysicsBodyInfo& cmd) {
    try {
        if (cmd.world_id != world_id_) {
            PayloadMap response;
            response["error"] = std::string("World ID mismatch");
            cmd.promise->set_value(std::move(response));
            return;
        }

        auto it = bodies_.find(cmd.body_id);
        if (it == bodies_.end() || !B2_IS_NON_NULL(it->second)) {
            PayloadMap response;
            response["error"] = std::string("Body not found");
            cmd.promise->set_value(std::move(response));
            return;
        }

        b2BodyId bodyId = it->second;
        b2Vec2 pos = b2Body_GetPosition(bodyId);
        b2Rot rot = b2Body_GetRotation(bodyId);
        b2Vec2 vel = b2Body_GetLinearVelocity(bodyId);
        float angular_vel = b2Body_GetAngularVelocity(bodyId);
        float mass = b2Body_GetMass(bodyId);
        bool awake = b2Body_IsAwake(bodyId);
        bool enabled = b2Body_IsEnabled(bodyId);

        PayloadMap response;
        response["pos_x"] = static_cast<double>(pos.x);
        response["pos_y"] = static_cast<double>(pos.y);
        response["angle"] = static_cast<double>(b2Rot_GetAngle(rot));
        response["vel_x"] = static_cast<double>(vel.x);
        response["vel_y"] = static_cast<double>(vel.y);
        response["angular_vel"] = static_cast<double>(angular_vel);
        response["mass"] = static_cast<double>(mass);
        response["awake"] = awake;
        response["enabled"] = enabled;
        response["error"] = std::string("");

        cmd.promise->set_value(std::move(response));

    } catch (const std::exception& e) {
        PayloadMap response;
        response["error"] = std::string(e.what());
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleQueryWorldInfo(Commands::QueryPhysicsWorldInfo& cmd) {
    try {
        if (cmd.world_id != world_id_) {
            PayloadMap response;
            response["error"] = std::string("World ID mismatch");
            cmd.promise->set_value(std::move(response));
            return;
        }

        if (!world_) {
            PayloadMap response;
            response["error"] = std::string("World not valid");
            cmd.promise->set_value(std::move(response));
            return;
        }

        b2Vec2 gravity = b2World_GetGravity(*world_);
        int body_count = static_cast<int>(bodies_.size());

        PayloadMap response;
        response["body_count"] = static_cast<int64_t>(body_count);
        response["gravity_x"] = static_cast<double>(gravity.x);
        response["gravity_y"] = static_cast<double>(gravity.y);
        response["error"] = std::string("");

        cmd.promise->set_value(std::move(response));

    } catch (const std::exception& e) {
        PayloadMap response;
        response["error"] = std::string(e.what());
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleSetGravity(Commands::SetPhysicsGravity& cmd) {
    if (cmd.world_id != world_id_) return;

    if (world_) {
        b2Vec2 gravity = {static_cast<float>(cmd.gravity_x), static_cast<float>(cmd.gravity_y)};
        b2World_SetGravity(*world_, gravity);
        LOG_DEBUG("PhysicsThread {}: Set gravity to ({}, {})", world_id_, cmd.gravity_x, cmd.gravity_y);
    }
}

void PhysicsThread::HandleCreateRevoluteJoint(Commands::CreateRevoluteJoint& cmd) {
    PayloadMap response;
    int joint_id = -1;
    std::string error = "";

    try {
        // Find bodies
        auto body_a_it = bodies_.find(cmd.body_a_id);
        auto body_b_it = bodies_.find(cmd.body_b_id);

        if (body_a_it == bodies_.end()) {
            error = "Body A not found: " + std::to_string(cmd.body_a_id);
        } else if (body_b_it == bodies_.end()) {
            error = "Body B not found: " + std::to_string(cmd.body_b_id);
        } else {
            // Create revolute joint definition
            b2RevoluteJointDef jointDef = b2DefaultRevoluteJointDef();
            jointDef.bodyIdA = body_a_it->second;
            jointDef.bodyIdB = body_b_it->second;
            jointDef.localAnchorA = b2Body_GetLocalPoint(body_a_it->second, {static_cast<float>(cmd.anchor_x), static_cast<float>(cmd.anchor_y)});
            jointDef.localAnchorB = b2Body_GetLocalPoint(body_b_it->second, {static_cast<float>(cmd.anchor_x), static_cast<float>(cmd.anchor_y)});
            jointDef.enableMotor = cmd.enable_motor;
            jointDef.motorSpeed = static_cast<float>(cmd.motor_speed);
            jointDef.maxMotorTorque = static_cast<float>(cmd.max_motor_torque);
            jointDef.enableLimit = cmd.enable_limit;
            jointDef.lowerAngle = static_cast<float>(cmd.lower_angle);
            jointDef.upperAngle = static_cast<float>(cmd.upper_angle);

            // Create joint
            b2JointId joint = b2CreateRevoluteJoint(*world_, &jointDef);

            // Store joint
            joint_id = next_joint_id_++;
            joints_[joint_id] = joint;

            LOG_DEBUG("PhysicsThread {}: Created revolute joint {} between bodies {} and {}",
                     world_id_, joint_id, cmd.body_a_id, cmd.body_b_id);
        }
    } catch (const std::exception& e) {
        error = std::string("Exception creating revolute joint: ") + e.what();
        LOG_ERROR("PhysicsThread {}: {}", world_id_, error);
    }

    response["joint_id"] = static_cast<int64_t>(joint_id);
    response["error"] = error;

    if (cmd.promise) {
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleCreateDistanceJoint(Commands::CreateDistanceJoint& cmd) {
    PayloadMap response;
    int joint_id = -1;
    std::string error = "";

    try {
        // Find bodies
        auto body_a_it = bodies_.find(cmd.body_a_id);
        auto body_b_it = bodies_.find(cmd.body_b_id);

        if (body_a_it == bodies_.end()) {
            error = "Body A not found: " + std::to_string(cmd.body_a_id);
        } else if (body_b_it == bodies_.end()) {
            error = "Body B not found: " + std::to_string(cmd.body_b_id);
        } else {
            // Create distance joint definition
            b2DistanceJointDef jointDef = b2DefaultDistanceJointDef();
            jointDef.bodyIdA = body_a_it->second;
            jointDef.bodyIdB = body_b_it->second;
            jointDef.localAnchorA = b2Body_GetLocalPoint(body_a_it->second, {static_cast<float>(cmd.anchor_a_x), static_cast<float>(cmd.anchor_a_y)});
            jointDef.localAnchorB = b2Body_GetLocalPoint(body_b_it->second, {static_cast<float>(cmd.anchor_b_x), static_cast<float>(cmd.anchor_b_y)});

            // Calculate rest length from anchor positions
            b2Vec2 pos_a = b2Body_GetWorldPoint(body_a_it->second, jointDef.localAnchorA);
            b2Vec2 pos_b = b2Body_GetWorldPoint(body_b_it->second, jointDef.localAnchorB);
            b2Vec2 delta = {pos_b.x - pos_a.x, pos_b.y - pos_a.y};
            jointDef.length = std::sqrt(delta.x * delta.x + delta.y * delta.y);

            jointDef.hertz = static_cast<float>(cmd.frequency);
            jointDef.dampingRatio = static_cast<float>(cmd.damping_ratio);

            // Create joint
            b2JointId joint = b2CreateDistanceJoint(*world_, &jointDef);

            // Store joint
            joint_id = next_joint_id_++;
            joints_[joint_id] = joint;

            LOG_DEBUG("PhysicsThread {}: Created distance joint {} between bodies {} and {} with length {}",
                     world_id_, joint_id, cmd.body_a_id, cmd.body_b_id, jointDef.length);
        }
    } catch (const std::exception& e) {
        error = std::string("Exception creating distance joint: ") + e.what();
        LOG_ERROR("PhysicsThread {}: {}", world_id_, error);
    }

    response["joint_id"] = static_cast<int64_t>(joint_id);
    response["error"] = error;

    if (cmd.promise) {
        cmd.promise->set_value(std::move(response));
    }
}

void PhysicsThread::HandleDestroyJoint(Commands::DestroyJoint& cmd) {
    auto it = joints_.find(cmd.joint_id);
    if (it != joints_.end()) {
        b2DestroyJoint(it->second);
        joints_.erase(it);
        LOG_DEBUG("PhysicsThread {}: Destroyed joint {}", world_id_, cmd.joint_id);
    }
}

void PhysicsThread::HandleSetJointMotorSpeed(Commands::SetJointMotorSpeed& cmd) {
    auto it = joints_.find(cmd.joint_id);
    if (it != joints_.end()) {
        // Set motor speed for revolute joint
        b2RevoluteJoint_SetMotorSpeed(it->second, static_cast<float>(cmd.motor_speed));
        LOG_DEBUG("PhysicsThread {}: Set joint {} motor speed to {}", world_id_, cmd.joint_id, cmd.motor_speed);
    }
}
