#pragma once

#include <variant>
#include <string>
#include <functional>
#include <future>
#include <memory>
#include <sol/sol.hpp>
#include "InputState.h"
#include "DataStore.h"

// Command types that lua threads can send to the main thread
namespace Commands {
    struct SpawnThread {
        std::string script_path;
        PayloadMap config;
        int parent_thread_id = 0;   // 0 = no parent
        int parent_request_id = 0;  // Request ID in parent to respond to
        int requesting_thread_id = 0;  // Thread that issued this command
    };

    struct TriggerUI {
        std::string event_name;
        PayloadMap payload;
    };

    struct CallMainThread {
        std::function<void()> callback;
    };

    struct StopThread {
        int thread_id;
    };

    struct SaveThread {
        int thread_id;
        std::string save_path;
    };

    struct Print {
        int thread_id;
        std::string message;
    };

    struct LoadUIDocument {
        int thread_id;  // Which thread loaded this document
        std::string document_path;
        bool show = true;
        std::string document_id;  // Optional ID to reference this document later
    };

    struct ShowUIDocument {
        std::string document_id;
    };

    struct HideUIDocument {
        std::string document_id;
    };

    struct ReloadUIDocument {
        std::string document_id;
    };

    struct SetElementText {
        std::string element_id;
        std::string text;
    };

    struct SetElementAttribute {
        std::string element_id;
        std::string attribute_name;
        std::string value;
    };

    struct SetElementStyle {
        std::string element_id;
        std::string property;
        std::string value;
    };

    struct AddElementClass {
        std::string element_id;
        std::string class_name;
    };

    struct RemoveElementClass {
        std::string element_id;
        std::string class_name;
    };

    struct SetTextEditorContent {
        std::string element_id;
        std::string content;
    };

    struct SetTextEditorTokens {
        std::string element_id;
        DynamicTable tokens;  // Array of token objects
    };

    struct SetTextEditorEditable {
        std::string element_id;
        bool editable;
    };

    struct SetTextEditorModified {
        std::string element_id;
        bool modified;
    };

    struct SetTextEditorConfig {
        std::string element_id;
        std::string config_key;
        DynamicValue value;
    };

    struct TextEditorCopy {
        std::string element_id;
    };

    struct TextEditorPaste {
        std::string element_id;
    };

    struct TextEditorCut {
        std::string element_id;
    };

    struct TextEditorSelectAll {
        std::string element_id;
    };

    struct TextEditorUndo {
        std::string element_id;
    };

    struct TextEditorRedo {
        std::string element_id;
    };

    // Synchronous data binding commands (promise-in-command pattern)
    // Promise is set by main thread when binding completes to wake blocked Lua thread
    struct BindDataTable {
        int requesting_thread_id;
        uint64_t request_id;
        std::string model_name;
        DynamicTable data;
        std::shared_ptr<std::promise<void>> promise;
    };

    struct BindDataObject {
        int requesting_thread_id;
        uint64_t request_id;
        std::string object_name;
        DynamicRow data;
        std::shared_ptr<std::promise<void>> promise;
    };

    struct TriggerTextEditorModified {
        std::string element_id;
        bool modified;
        std::string content;
    };

    struct FileChanged {
        std::string path;
        std::string event_type;  // "created", "modified", "deleted"
    };

    struct AddFileWatch {
        std::string path;
        bool recursive;
    };

    struct RemoveFileWatch {
        std::string path;
    };

    struct RegisterGlobalEvent {
        std::string event_name;
        int thread_id;
    };

    struct UnregisterGlobalEvent {
        std::string event_name;
    };

    struct TriggerGlobalEvent {
        std::string event_name;
        PayloadMap payload;
    };

    struct NotificationActionData {
        std::string id;
        std::string label;
    };

    struct AddNotification {
        int type;
        std::string title;
        std::string message;
        std::string thread_name;
        bool dismissible;
        bool expandable;
        std::string expanded_content;
        std::vector<NotificationActionData> actions;
        PayloadMap metadata;
        double ttl_seconds;
        int thread_id = -1;
    };

    struct ClearNotifications {
    };

    struct DismissNotification {
        std::string notification_id;
    };

    struct CloseApplication {
    };

    struct MarkSystemReady {
        std::string system_name;
    };

    // Query commands (request/response pattern)
    // Promise is set by main thread to wake blocked Lua thread
    struct QueryThreadList {
        int requesting_thread_id;
        uint64_t request_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;
    };

    struct QueryThreadInfo {
        int requesting_thread_id;
        uint64_t request_id;
        int thread_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;
    };

    struct QueryDocumentList {
        int requesting_thread_id;
        uint64_t request_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;
    };

    struct QueryDocumentInfo {
        int requesting_thread_id;
        uint64_t request_id;
        std::string document_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;
    };

    // Audio commands
    struct LoadSound {
        int requesting_thread_id;
        uint64_t request_id;
        std::string file_path;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {sound_id=int, error=string}
    };

    struct UnloadSound {
        int sound_id;
    };

    struct PlaySound {
        int sound_id;
        float volume;      // 0.0 to 1.0
        float pan;         // -1.0 to 1.0
        bool loop;
        bool restart;      // Rewind to beginning before playing
    };

    struct StopSound {
        int sound_id;
    };

    struct PauseSound {
        int sound_id;
    };

    struct SetSoundVolume {
        int sound_id;
        float volume;
    };

    struct SetSoundPan {
        int sound_id;
        float pan;
    };

    struct SetSoundLooping {
        int sound_id;
        bool loop;
    };

    struct SetSoundPosition {
        int sound_id;
        float seconds;
    };

    struct RewindSound {
        int sound_id;
    };

    struct QuerySoundInfo {
        int requesting_thread_id;
        uint64_t request_id;
        int sound_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {is_playing, position, volume, pan, looping, length}
    };

    struct SetMasterVolume {
        float volume;
    };

    struct QueryMasterVolume {
        int requesting_thread_id;
        uint64_t request_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {volume=float}
    };

    // Physics commands - for Box2D integration
    struct CreatePhysicsWorld {
        int requesting_thread_id;
        uint64_t request_id;
        double gravity_x;
        double gravity_y;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {world_id=int, error=string}
    };

    struct DestroyPhysicsWorld {
        int world_id;
    };

    struct StepPhysicsWorld {
        int world_id;
        float time_step;
        int velocity_iterations;
        int position_iterations;
    };

    struct CreatePhysicsBody {
        int requesting_thread_id;
        uint64_t request_id;
        int world_id;
        int body_type;  // 0=static, 1=kinematic, 2=dynamic
        double position_x;
        double position_y;
        double angle;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {body_id=int, error=string}
    };

    struct DestroyPhysicsBody {
        int world_id;
        int body_id;
    };

    struct AddBoxFixture {
        int requesting_thread_id;
        uint64_t request_id;
        int world_id;
        int body_id;
        double half_width;
        double half_height;
        double density;
        double friction;
        double restitution;
        bool is_sensor;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {fixture_id=int, error=string}
    };

    struct AddCircleFixture {
        int requesting_thread_id;
        uint64_t request_id;
        int world_id;
        int body_id;
        double radius;
        double offset_x;
        double offset_y;
        double density;
        double friction;
        double restitution;
        bool is_sensor;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {fixture_id=int, error=string}
    };

    struct AddPolygonFixture {
        int requesting_thread_id;
        uint64_t request_id;
        int world_id;
        int body_id;
        std::vector<double> vertices;  // Flat array: [x1, y1, x2, y2, ...]
        double density;
        double friction;
        double restitution;
        bool is_sensor;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {fixture_id=int, error=string}
    };

    struct SetBodyVelocity {
        int world_id;
        int body_id;
        double velocity_x;
        double velocity_y;
    };

    struct SetBodyAngularVelocity {
        int world_id;
        int body_id;
        double angular_velocity;
    };

    struct SetBodyTransform {
        int world_id;
        int body_id;
        double position_x;
        double position_y;
        double angle;
    };

    struct ApplyForce {
        int world_id;
        int body_id;
        double force_x;
        double force_y;
        double point_x;
        double point_y;
        bool wake;
    };

    struct ApplyForceToCenter {
        int world_id;
        int body_id;
        double force_x;
        double force_y;
        bool wake;
    };

    struct ApplyTorque {
        int world_id;
        int body_id;
        double torque;
        bool wake;
    };

    struct ApplyLinearImpulse {
        int world_id;
        int body_id;
        double impulse_x;
        double impulse_y;
        double point_x;
        double point_y;
        bool wake;
    };

    struct ApplyLinearImpulseToCenter {
        int world_id;
        int body_id;
        double impulse_x;
        double impulse_y;
        bool wake;
    };

    struct ApplyAngularImpulse {
        int world_id;
        int body_id;
        double impulse;
        bool wake;
    };

    struct QueryPhysicsBodyInfo {
        int requesting_thread_id;
        uint64_t request_id;
        int world_id;
        int body_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {pos_x, pos_y, angle, vel_x, vel_y, angular_vel, mass, ...}
    };

    struct QueryPhysicsWorldInfo {
        int requesting_thread_id;
        uint64_t request_id;
        int world_id;
        std::shared_ptr<std::promise<PayloadMap>> promise;  // Returns {body_count, gravity_x, gravity_y, ...}
    };

    struct SetPhysicsGravity {
        int world_id;
        double gravity_x;
        double gravity_y;
    };

}

// Variant holding all possible command types
using Command = std::variant<
    Commands::SpawnThread,
    Commands::TriggerUI,
    Commands::CallMainThread,
    Commands::StopThread,
    Commands::SaveThread,
    Commands::Print,
    Commands::LoadUIDocument,
    Commands::ShowUIDocument,
    Commands::HideUIDocument,
    Commands::ReloadUIDocument,
    Commands::SetElementText,
    Commands::SetElementAttribute,
    Commands::SetElementStyle,
    Commands::AddElementClass,
    Commands::RemoveElementClass,
    Commands::SetTextEditorContent,
    Commands::SetTextEditorTokens,
    Commands::SetTextEditorEditable,
    Commands::SetTextEditorModified,
    Commands::SetTextEditorConfig,
    Commands::TextEditorCopy,
    Commands::TextEditorPaste,
    Commands::TextEditorCut,
    Commands::TextEditorSelectAll,
    Commands::TextEditorUndo,
    Commands::TextEditorRedo,
    Commands::BindDataTable,
    Commands::BindDataObject,
    Commands::TriggerTextEditorModified,
    Commands::FileChanged,
    Commands::AddFileWatch,
    Commands::RemoveFileWatch,
    Commands::RegisterGlobalEvent,
    Commands::UnregisterGlobalEvent,
    Commands::TriggerGlobalEvent,
    Commands::AddNotification,
    Commands::ClearNotifications,
    Commands::DismissNotification,
    Commands::CloseApplication,
    Commands::MarkSystemReady,
    Commands::QueryThreadList,
    Commands::QueryThreadInfo,
    Commands::QueryDocumentList,
    Commands::QueryDocumentInfo,
    Commands::LoadSound,
    Commands::UnloadSound,
    Commands::PlaySound,
    Commands::StopSound,
    Commands::PauseSound,
    Commands::SetSoundVolume,
    Commands::SetSoundPan,
    Commands::SetSoundLooping,
    Commands::SetSoundPosition,
    Commands::RewindSound,
    Commands::QuerySoundInfo,
    Commands::SetMasterVolume,
    Commands::QueryMasterVolume,
    Commands::CreatePhysicsWorld,
    Commands::DestroyPhysicsWorld,
    Commands::StepPhysicsWorld,
    Commands::CreatePhysicsBody,
    Commands::DestroyPhysicsBody,
    Commands::AddBoxFixture,
    Commands::AddCircleFixture,
    Commands::AddPolygonFixture,
    Commands::SetBodyVelocity,
    Commands::SetBodyAngularVelocity,
    Commands::SetBodyTransform,
    Commands::ApplyForce,
    Commands::ApplyForceToCenter,
    Commands::ApplyTorque,
    Commands::ApplyLinearImpulse,
    Commands::ApplyLinearImpulseToCenter,
    Commands::ApplyAngularImpulse,
    Commands::QueryPhysicsBodyInfo,
    Commands::QueryPhysicsWorldInfo,
    Commands::SetPhysicsGravity
>;

// Response sent from main thread to lua thread
// THREADING: PayloadMap is thread-safe and can cross thread boundaries
// The receiving Lua thread converts PayloadMap to a Lua table
struct Response {
    uint64_t request_id;
    PayloadMap data;         // Thread-safe data that can cross lua_State boundaries
    std::string error;       // Empty if success

    Response(uint64_t id, PayloadMap&& d, const std::string& e = "")
        : request_id(id), data(std::move(d)), error(e) {}
};
