#include "LuaThread.h"
#include "CommandQueue.h"
#include "ResponseQueue.h"
#include "Seqlock.h"
#include "InputState.h"
#include "Logger.h"
#include <chrono>

namespace {
    // Helper to convert sol::table to PayloadMap
    PayloadMap TableToPayloadMap(const sol::table& table) {
        PayloadMap result;
        for (const auto& [key, value] : table) {
            if (!key.is<std::string>()) continue;
            std::string key_str = key.as<std::string>();

            if (value.is<bool>()) {
                result[key_str] = value.as<bool>();
            } else if (value.is<int>()) {
                result[key_str] = value.as<int>();
            } else if (value.is<double>()) {
                result[key_str] = value.as<double>();
            } else if (value.is<std::string>()) {
                result[key_str] = value.as<std::string>();
            }
        }
        return result;
    }
}

LuaThread::LuaThread(int id, const std::string& script_path,
                     CommandQueue* command_queue,
                     Seqlock<InputState>* input_seqlock)
    : id_(id)
    , script_path_(script_path)
    , state_(State::Starting)
    , should_stop_(false)
    , is_paused_(false)
    , command_queue_(command_queue)
    , input_seqlock_(input_seqlock)
    , response_queue_(std::make_unique<ResponseQueue>())
    , next_request_id_(1)
    , parent_thread_id_(0)
    , parent_request_id_(0)
{
}

LuaThread::~LuaThread() {
    Stop();
    Join();
}

void LuaThread::Start() {
    thread_ = std::make_unique<std::thread>(&LuaThread::ThreadMain, this);
}

void LuaThread::Stop() {
    should_stop_ = true;
    state_ = State::Stopping;
}

void LuaThread::Pause() {
    is_paused_ = true;
    state_ = State::Paused;
}

void LuaThread::Resume() {
    is_paused_ = false;
    state_ = State::Running;
}

void LuaThread::SetParent(int parent_id, int parent_request_id) {
    parent_thread_id_ = parent_id;
    parent_request_id_ = parent_request_id;
}

void LuaThread::Join() {
    if (thread_ && thread_->joinable()) {
        thread_->join();
    }
}

sol::object LuaThread::CallSaveHook() {
    if (!lua_) return sol::nil;

    sol::optional<sol::function> save_fn = (*lua_)["on_save"];
    if (save_fn) {
        auto result = save_fn.value()();
        return result;
    }
    return sol::nil;
}

void LuaThread::CallLoadHook(const sol::object& data) {
    if (!lua_) return;

    sol::optional<sol::function> load_fn = (*lua_)["on_load"];
    if (load_fn) {
        load_fn.value()(data);
    }
}

void LuaThread::ProcessResponses() {
    if (!lua_) return;

    // Get all pending responses (lock-free read)
    auto responses = response_queue_->PopAll();

    for (auto& response : responses) {
        auto it = pending_requests_.find(response.request_id);
        if (it != pending_requests_.end()) {
            // Call the lua callback
            try {
                if (response.error.empty()) {
                    // Success: callback(data, nil)
                    it->second.callback(response.data, sol::nil);
                } else {
                    // Error: callback(nil, error)
                    it->second.callback(sol::nil, response.error);
                }
            } catch (const sol::error& e) {
                LOG_ERROR("Lua thread {} error in callback for request {}: {}",
                         id_, response.request_id, e.what());
            }

            // Remove from pending requests
            pending_requests_.erase(it);
        }
    }
}

void LuaThread::ProcessInputEvents() {
    if (!lua_ || !input_seqlock_) return;

    auto input_state = input_seqlock_->Read();

    // Process mouse button events
    if (on_mouse_button_) {
        for (const auto& event : input_state.mouse_button_events) {
            try {
                int button = static_cast<int>(event.button);
                on_mouse_button_(button, event.x, event.y, event.pressed);
            } catch (const sol::error& e) {
                LOG_ERROR("Lua thread {} error in on_mouse_button callback: {}", id_, e.what());
            }
        }
    }

    // Process mouse move events
    if (on_mouse_move_) {
        for (const auto& event : input_state.mouse_move_events) {
            try {
                on_mouse_move_(event.x, event.y, event.dx, event.dy);
            } catch (const sol::error& e) {
                LOG_ERROR("Lua thread {} error in on_mouse_move callback: {}", id_, e.what());
            }
        }
    }

    // Process key events
    if (on_key_) {
        for (const auto& event : input_state.key_events) {
            try {
                on_key_(event.key_name, event.pressed);
            } catch (const sol::error& e) {
                LOG_ERROR("Lua thread {} error in on_key callback: {}", id_, e.what());
            }
        }
    }
}

void LuaThread::ThreadMain() {
    try {
        // Create lua state for this thread
        lua_ = std::make_unique<sol::state>();
        lua_->open_libraries(sol::lib::base, sol::lib::package, sol::lib::math,
                            sol::lib::string, sol::lib::table, sol::lib::os);

        // Setup bindings
        SetupLuaBindings();

        // Load and run the script
        auto result = lua_->safe_script_file(script_path_);
        if (!result.valid()) {
            sol::error err = result;
            error_message_ = err.what();
            LOG_ERROR("Lua thread {} error loading script '{}': {}", id_, script_path_, error_message_);
            state_ = State::Error;
            return;
        }

        // Call startup() if it exists
        sol::optional<sol::function> startup_fn = (*lua_)["startup"];
        if (startup_fn) {
            auto startup_result = startup_fn.value()();
            if (!startup_result.valid()) {
                sol::error err = startup_result;
                error_message_ = err.what();
                LOG_ERROR("Lua thread {} error in startup(): {}", id_, error_message_);
                state_ = State::Error;
                return;
            }
        }

        state_ = State::Running;
        LOG_INFO("Lua thread {} running", id_);

        // 30hz update loop (33.33ms per frame)
        constexpr auto frame_duration = std::chrono::milliseconds(33);
        auto next_frame_time = std::chrono::steady_clock::now();

        sol::optional<sol::function> update_fn = (*lua_)["update"];

        while (!should_stop_) {
            // Handle pause
            while (is_paused_ && !should_stop_) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }

            if (should_stop_) break;

            // Process responses and fire callbacks
            ProcessResponses();

            // Process SDL input events
            ProcessInputEvents();

            // Dispatch UI events to registered event handlers
            if (input_seqlock_) {
                auto input_state = input_seqlock_->Read();
                for (const auto& ui_event : input_state.ui_events) {
                    auto it = event_handlers_.find(ui_event.name);
                    if (it != event_handlers_.end()) {
                        // Convert payload to lua table
                        auto payload_table = lua_->create_table();
                        for (const auto& [key, value] : ui_event.payload) {
                            std::visit([&](auto&& val) {
                                using T = std::decay_t<decltype(val)>;
                                if constexpr (std::is_same_v<T, std::monostate>) {
                                    payload_table[key] = sol::nil;
                                } else {
                                    payload_table[key] = val;
                                }
                            }, value);
                        }

                        // Call registered handler
                        try {
                            it->second(payload_table);
                        } catch (const sol::error& e) {
                            LOG_ERROR("Lua thread {} error in event handler for '{}': {}",
                                     id_, ui_event.name, e.what());
                        }
                    }
                }
            }

            // Call update(dt) if it exists
            if (update_fn) {
                double dt = 0.033;  // Fixed timestep for now
                auto update_result = update_fn.value()(dt);
                if (!update_result.valid()) {
                    sol::error err = update_result;
                    error_message_ = err.what();
                    LOG_ERROR("Lua thread {} error in update(): {}", id_, error_message_);
                    state_ = State::Error;
                    return;
                }
            }

            // Wait for next frame (30hz)
            next_frame_time += frame_duration;
            std::this_thread::sleep_until(next_frame_time);
        }

        // Call shutdown() if it exists
        sol::optional<sol::function> shutdown_fn = (*lua_)["shutdown"];
        if (shutdown_fn) {
            auto shutdown_result = shutdown_fn.value()();
            if (!shutdown_result.valid()) {
                sol::error err = shutdown_result;
                LOG_WARN("Lua thread {} error in shutdown(): {}", id_, err.what());
            }
        }

        state_ = State::Stopped;
        LOG_INFO("Lua thread {} finished normally", id_);

    } catch (const std::exception& e) {
        error_message_ = e.what();
        LOG_ERROR("Lua thread {} exception: {}", id_, error_message_);
        state_ = State::Error;
    }
}

void LuaThread::SetupLuaBindings() {
    // Bind event registration system
    auto event_table = lua_->create_table();

    event_table["register"] = [this](const std::string& event_name, sol::function handler) {
        event_handlers_[event_name] = handler;
        LOG_DEBUG("Lua thread {} registered handler for event '{}'", id_, event_name);
    };

    (*lua_)["event"] = event_table;

    // Bind command queue interface
    auto command_table = lua_->create_table();

    command_table["spawn_thread"] = [this](const std::string& path, sol::optional<sol::table> config) {
        Commands::SpawnThread cmd;
        cmd.script_path = path;
        if (config) {
            cmd.config = TableToPayloadMap(config.value());
        }
        cmd.parent_thread_id = id_;
        cmd.requesting_thread_id = id_;
        command_queue_->Push(std::move(cmd));
    };

    command_table["stop_thread"] = [this](int thread_id) {
        Commands::StopThread cmd;
        cmd.thread_id = thread_id;
        command_queue_->Push(std::move(cmd));
    };

    (*lua_)["command"] = command_table;

    // Bind UI operations
    auto ui_table = lua_->create_table();

    ui_table["load_document"] = [this](const std::string& path, sol::optional<bool> show) {
        Commands::LoadUIDocument cmd;
        cmd.document_path = path;
        cmd.show = show.value_or(true);
        command_queue_->Push(std::move(cmd));
        LOG_DEBUG("Lua thread {} queued LoadUIDocument: {}", id_, path);
    };

    ui_table["set_element_text"] = [this](const std::string& element_id, const std::string& text) {
        Commands::SetElementText cmd;
        cmd.element_id = element_id;
        cmd.text = text;
        command_queue_->Push(std::move(cmd));
    };

    (*lua_)["ui"] = ui_table;

    // Bind input state interface
    auto input_table = lua_->create_table();

    input_table["get_state"] = [this]() -> sol::table {
        if (!input_seqlock_) {
            return lua_->create_table();
        }

        auto state = input_seqlock_->Read();
        auto table = lua_->create_table();

        // Mouse
        auto mouse = table["mouse"] = lua_->create_table();
        mouse["x"] = state.mouse_x;
        mouse["y"] = state.mouse_y;
        mouse["left"] = state.mouse_left;
        mouse["right"] = state.mouse_right;
        mouse["middle"] = state.mouse_middle;

        // Keyboard (simplified - add more as needed)
        auto keyboard = table["keyboard"] = lua_->create_table();
        for (const auto& [key, pressed] : state.keyboard) {
            keyboard[key] = pressed;
        }

        // Frame number
        table["frame"] = state.frame_number;

        // UI Events
        auto events = table["ui_events"] = lua_->create_table();
        for (size_t i = 0; i < state.ui_events.size(); ++i) {
            auto event = events[i + 1] = lua_->create_table();
            event["name"] = state.ui_events[i].name;

            // Convert PayloadMap to lua table
            auto payload_table = lua_->create_table();
            for (const auto& [key, value] : state.ui_events[i].payload) {
                std::visit([&](auto&& val) {
                    using T = std::decay_t<decltype(val)>;
                    if constexpr (std::is_same_v<T, std::monostate>) {
                        payload_table[key] = sol::nil;
                    } else {
                        payload_table[key] = val;
                    }
                }, value);
            }
            event["payload"] = payload_table;
        }

        return table;
    };

    // Input event callbacks
    input_table["on_mouse_button"] = [this](sol::function callback) {
        on_mouse_button_ = callback;
    };

    input_table["on_mouse_move"] = [this](sol::function callback) {
        on_mouse_move_ = callback;
    };

    input_table["on_key"] = [this](sol::function callback) {
        on_key_ = callback;
    };

    (*lua_)["input"] = input_table;

    // Bind thread info
    (*lua_)["thread_id"] = id_;
    (*lua_)["thread_name"] = script_path_;

    // Override print to send to main thread via command queue
    (*lua_)["print"] = [this](sol::variadic_args va) {
        std::string message;
        for (auto v : va) {
            if (!message.empty()) message += "\t";

            if (v.is<std::string>()) {
                message += v.as<std::string>();
            } else if (v.is<int>()) {
                message += std::to_string(v.as<int>());
            } else if (v.is<double>()) {
                message += std::to_string(v.as<double>());
            } else if (v.is<bool>()) {
                message += v.as<bool>() ? "true" : "false";
            } else if (v.is<sol::nil_t>()) {
                message += "nil";
            } else {
                message += "<" + std::string(sol::type_name(lua_->lua_state(), v.get_type())) + ">";
            }
        }

        Commands::Print cmd;
        cmd.thread_id = id_;
        cmd.message = message;
        command_queue_->Push(std::move(cmd));
    };
}
