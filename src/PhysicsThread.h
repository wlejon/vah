#pragma once

#include <thread>
#include <atomic>
#include <memory>
#include <unordered_map>
#include <vector>
#include <box2d/box2d.h>
#include <moodycamel/concurrentqueue.h>
#include "Commands.h"

/**
 * PhysicsBodyState - Snapshot of a single physics body for rendering
 */
struct PhysicsBodyState {
    int body_id;
    double pos_x;
    double pos_y;
    double angle;
    double vel_x;
    double vel_y;
    double mass;
    bool awake;
};

/**
 * PhysicsWorldState - Complete snapshot of physics world for rendering
 * Lock-free: Physics thread writes, render thread reads
 * Uses unordered_map for O(1) body lookup by body_id
 */
struct PhysicsWorldState {
    std::unordered_map<int, PhysicsBodyState> bodies;  // Changed from vector for O(1) lookup
    int world_id;
    double gravity_x;
    double gravity_y;
};

/**
 * PhysicsThread - Dedicated thread for Box2D physics simulation
 *
 * LOCK-FREE ARCHITECTURE:
 * - Each PhysicsThread owns a single b2World and all its bodies/fixtures
 * - Commands arrive via lock-free queue from Lua threads
 * - Results returned via promises (promise-in-command pattern)
 * - No mutexes, no shared state, no locks
 *
 * OWNERSHIP MODEL:
 * - PhysicsThread owns: b2World*, all b2Body*, all b2Fixture*
 * - Lua threads communicate via commands only
 * - Bodies/fixtures referenced by integer IDs
 *
 * SIMULATION:
 * - Fixed timestep (configurable, default 60Hz)
 * - Processes commands before each simulation step
 * - Can publish state via data binding for UI rendering
 */
class PhysicsThread {
public:
    enum class State {
        Starting,
        Running,
        Paused,
        Stopping,
        Stopped,
        Error
    };

    PhysicsThread(int world_id,
                  double gravity_x,
                  double gravity_y,
                  moodycamel::ConcurrentQueue<Command>* command_queue);
    ~PhysicsThread();

    // Start the physics thread (non-blocking)
    void Start();

    // Request thread to stop
    void Stop();

    // Pause/Resume simulation
    void Pause();
    void Resume();

    // Wait for thread to finish
    void Join();

    // Getters
    int GetWorldId() const { return world_id_; }
    State GetState() const { return state_.load(std::memory_order_acquire); }
    bool IsRunning() const { return state_.load(std::memory_order_acquire) == State::Running; }
    bool ShouldStop() const { return should_stop_.load(std::memory_order_acquire); }
    std::string GetError() const { return error_message_; }

    // Command queue for this physics world
    moodycamel::ConcurrentQueue<Command>* GetCommandQueue() { return &physics_command_queue_; }

    // Lock-free render state access (called from render thread)
    const PhysicsWorldState* GetRenderState() const {
        int read_idx = render_buffer_index_.load(std::memory_order_acquire);
        return &render_buffers_[read_idx];
    }

private:
    void ThreadMain();
    void ProcessCommands();
    void SimulationStep(float dt);
    void UpdateRenderState();

    // Command handlers
    void HandleCreateBody(Commands::CreatePhysicsBody& cmd);
    void HandleDestroyBody(Commands::DestroyPhysicsBody& cmd);
    void HandleAddBoxFixture(Commands::AddBoxFixture& cmd);
    void HandleAddCircleFixture(Commands::AddCircleFixture& cmd);
    void HandleAddPolygonFixture(Commands::AddPolygonFixture& cmd);
    void HandleSetBodyVelocity(Commands::SetBodyVelocity& cmd);
    void HandleSetBodyAngularVelocity(Commands::SetBodyAngularVelocity& cmd);
    void HandleSetBodyTransform(Commands::SetBodyTransform& cmd);
    void HandleApplyForce(Commands::ApplyForce& cmd);
    void HandleApplyForceToCenter(Commands::ApplyForceToCenter& cmd);
    void HandleApplyTorque(Commands::ApplyTorque& cmd);
    void HandleApplyLinearImpulse(Commands::ApplyLinearImpulse& cmd);
    void HandleApplyLinearImpulseToCenter(Commands::ApplyLinearImpulseToCenter& cmd);
    void HandleApplyAngularImpulse(Commands::ApplyAngularImpulse& cmd);
    void HandleQueryBodyInfo(Commands::QueryPhysicsBodyInfo& cmd);
    void HandleQueryWorldInfo(Commands::QueryPhysicsWorldInfo& cmd);
    void HandleSetGravity(Commands::SetPhysicsGravity& cmd);
    void HandleCreateRevoluteJoint(Commands::CreateRevoluteJoint& cmd);
    void HandleCreateDistanceJoint(Commands::CreateDistanceJoint& cmd);
    void HandleDestroyJoint(Commands::DestroyJoint& cmd);
    void HandleSetJointMotorSpeed(Commands::SetJointMotorSpeed& cmd);
    void HandleEnableJointLimit(Commands::EnableJointLimit& cmd);
    void HandleSetJointLimits(Commands::SetJointLimits& cmd);

    int world_id_;
    std::unique_ptr<b2WorldId> world_;
    std::atomic<State> state_;
    std::atomic<bool> should_stop_;
    std::atomic<bool> is_paused_;

    std::unique_ptr<std::thread> thread_;

    // Command queue for main thread to send commands to this physics world
    moodycamel::ConcurrentQueue<Command>* main_command_queue_;

    // Local command queue for physics-specific commands
    moodycamel::ConcurrentQueue<Command> physics_command_queue_;

    // Body/fixture/joint tracking (Box2D v3 uses IDs instead of pointers)
    int next_body_id_;
    int next_fixture_id_;
    int next_joint_id_;
    std::unordered_map<int, b2BodyId> bodies_;
    std::unordered_map<int, b2ShapeId> fixtures_;
    std::unordered_map<int, b2JointId> joints_;

    // Simulation settings
    float time_step_;
    int velocity_iterations_;
    int position_iterations_;

    std::string error_message_;

    // Lock-free double buffer for render state
    // Physics thread writes to write_buffer_index_, renderer reads from render_buffer_index_
    PhysicsWorldState render_buffers_[2];
    std::atomic<int> render_buffer_index_{0};  // Which buffer renderer should read (0 or 1)
    int write_buffer_index_{1};                 // Which buffer physics writes to (0 or 1)
};
