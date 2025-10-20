#include "LuaThread.h"
#include "Logger.h"
#include "FileSystem.h"
#include "JsonBindings.h"
#include "SqliteBindings.h"
#include "HttpBindings.h"
#include "FileWatcherBindings.h"
#include "FileIngestionBindings.h"
#include "NotificationBindings.h"
#include "DataStore.h"
#include <httplib.h>
#include <chrono>

namespace {
    // Forward declaration for recursion
    sol::object DynamicValueToLua(sol::state& lua, const DynamicValue& value);

    // Helper to recursively convert DynamicValue to Lua object
    sol::object DynamicValueToLua(sol::state& lua, const DynamicValue& value) {
        return std::visit([&](auto&& val) -> sol::object {
            using T = std::decay_t<decltype(val)>;

            if constexpr (std::is_same_v<T, std::monostate>) {
                return sol::make_object(lua, sol::nil);
            }
            else if constexpr (std::is_same_v<T, bool>) {
                return sol::make_object(lua, val);
            }
            else if constexpr (std::is_same_v<T, int64_t>) {
                return sol::make_object(lua, val);
            }
            else if constexpr (std::is_same_v<T, double>) {
                return sol::make_object(lua, val);
            }
            else if constexpr (std::is_same_v<T, std::string>) {
                return sol::make_object(lua, val);
            }
            else if constexpr (std::is_same_v<T, std::shared_ptr<DynamicMap>>) {
                // Nested object - recursively convert to Lua table
                if (!val) {
                    return sol::make_object(lua, sol::nil);
                }
                auto nested_table = lua.create_table();
                for (const auto& [key, nested_value] : val->fields) {
                    nested_table[key] = DynamicValueToLua(lua, nested_value);
                }
                return nested_table;
            }
            else {
                return sol::make_object(lua, sol::nil);
            }
        }, value);
    }

    // Helper to convert sol::object to DynamicValue
    DynamicValue ObjectToDynamicValue(const sol::object& obj) {
        if (obj.is<bool>()) {
            return obj.as<bool>();
        } else if (obj.is<int>()) {
            return static_cast<int64_t>(obj.as<int>());
        } else if (obj.is<int64_t>()) {
            return obj.as<int64_t>();
        } else if (obj.is<double>()) {
            return obj.as<double>();
        } else if (obj.is<std::string>()) {
            return obj.as<std::string>();
        } else if (obj.is<sol::table>()) {
            // Nested table - convert to DynamicMap
            // Support both string keys and numeric array indices (converted to strings)
            auto nested_map = std::make_shared<DynamicMap>();
            sol::table nested_table = obj.as<sol::table>();
            for (const auto& [key, value] : nested_table) {
                std::string key_str;
                if (key.is<std::string>()) {
                    key_str = key.as<std::string>();
                } else if (key.is<int>()) {
                    // Convert numeric index to string for arrays
                    key_str = std::to_string(key.as<int>());
                } else {
                    // Skip other key types
                    continue;
                }
                nested_map->fields[key_str] = ObjectToDynamicValue(value);
            }
            return nested_map;
        } else {
            return std::monostate{};
        }
    }

    // Helper to convert Lua table (array of tables) to DynamicTable
    DynamicTable TableToDynamicTable(const sol::table& table) {
        DynamicTable result;

        // Debug: Check table type
        size_t count = 0;

        // Iterate through all pairs to see what we have
        for (const auto& [key, value] : table) {
            if (key.is<int>() || key.is<size_t>()) {
                count++;
                int index = key.as<int>();

                if (value.is<sol::table>()) {
                    sol::table row_table = value.as<sol::table>();
                    DynamicRow row;

                    // Convert each field in the row
                    for (const auto& [row_key, row_value] : row_table) {
                        if (row_key.is<std::string>()) {
                            std::string key_str = row_key.as<std::string>();
                            row[key_str] = ObjectToDynamicValue(row_value);
                        }
                    }

                    result.push_back(std::move(row));
                }
            }
        }

        return result;
    }

    // Helper to convert Lua table to PayloadMap (for configs, params, etc.)
    PayloadMap TableToPayloadMap(const sol::table& table) {
        PayloadMap result;
        for (const auto& [key, value] : table) {
            if (key.is<std::string>()) {
                std::string key_str = key.as<std::string>();
                result[key_str] = ObjectToDynamicValue(value);
            }
        }
        return result;
    }
}

LuaThread::LuaThread(int id, const std::string& script_path,
                     moodycamel::ConcurrentQueue<Command>* command_queue,
                     moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue,
                     DataStore* data_store,
                     NotificationFeed* notification_feed)
    : id_(id)
    , script_path_(script_path)
    , state_(State::Starting)
    , should_stop_(false)
    , is_paused_(false)
    , command_queue_(command_queue)
    , ui_event_queue_(ui_event_queue)
    , data_store_(data_store)
    , notification_feed_(notification_feed)
    , response_queue_(std::make_unique<moodycamel::ConcurrentQueue<Response>>())
    , next_request_id_(1)
    , parent_thread_id_(0)
    , parent_request_id_(0)
    , active_http_server_(nullptr)
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

    // Stop any HTTP server running on this thread (lock-free)
    httplib::Server* server = active_http_server_.load(std::memory_order_acquire);
    if (server) {
        server->stop();  // Thread-safe call to unblock listen()
    }
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

void LuaThread::LoadFromLuaFile(const std::string& file_path) {
    if (!lua_) {
        LOG_ERROR("LuaThread {}: Cannot load from file, lua state not initialized", id_);
        return;
    }

    try {
        // Execute the Lua file to get the data
        auto result = lua_->safe_script_file(file_path);

        if (!result.valid()) {
            sol::error err = result;
            LOG_ERROR("LuaThread {}: Error loading save file '{}': {}", id_, file_path, err.what());
            return;
        }

        // The file should return a table
        sol::object data = result;

        // Call the load hook with the data
        CallLoadHook(data);
    } catch (const std::exception& e) {
        LOG_ERROR("LuaThread {}: Error loading from file '{}': {}", id_, file_path, e.what());
    }
}

void LuaThread::ProcessResponses() {
    if (!lua_) return;

    // Get all pending responses (lock-free read)
    std::vector<Response> responses;
    Response response{0, PayloadMap{}, ""};
    while (response_queue_->try_dequeue(response)) {
        responses.push_back(std::move(response));
    }

    for (auto& response : responses) {
        auto it = pending_requests_.find(response.request_id);
        if (it != pending_requests_.end()) {
            // Call the lua callback
            try {
                if (response.error.empty()) {
                    // Convert PayloadMap to Lua table (handles nested objects)
                    auto data_table = lua_->create_table();
                    for (const auto& [key, value] : response.data) {
                        data_table[key] = DynamicValueToLua(*lua_, value);
                    }
                    // Success: callback(data, nil)
                    it->second.callback(data_table, sol::nil);
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

void LuaThread::ThreadMain() {
    try {
        // Create lua state for this thread
        lua_ = std::make_unique<sol::state>();
        lua_->open_libraries(sol::lib::base, sol::lib::package, sol::lib::math,
                            sol::lib::string, sol::lib::table, sol::lib::os);

        // Add scripts directory to Lua package.path for require()
        std::string current_path = (*lua_)["package"]["path"];
        (*lua_)["package"]["path"] = current_path + ";./scripts/?.lua";

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

            ProcessResponses();

            // Dispatch UI events to registered event handlers
            // Only consume from queue if this thread has handlers registered
            // (prevents threads without handlers from stealing events)
            if (ui_event_queue_ && !event_handlers_.empty()) {
                std::vector<UIEvent> ui_events;
                UIEvent ui_event;
                while (ui_event_queue_->try_dequeue(ui_event)) {
                    ui_events.push_back(std::move(ui_event));
                }

                for (const auto& ui_event : ui_events) {
                    auto it = event_handlers_.find(ui_event.name);
                    if (it != event_handlers_.end()) {
                        // Convert payload to lua table (handles nested objects)
                        auto payload_table = lua_->create_table();
                        for (const auto& [key, value] : ui_event.payload) {
                            payload_table[key] = DynamicValueToLua(*lua_, value);
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
    // Setup file system bindings
    FileSystemBindings::SetupBindings(*lua_);

    // Setup JSON bindings
    JsonBindings::SetupBindings(*lua_);

    // Setup SQLite bindings
    SqliteBindings::SetupBindings(*lua_);

    // Setup HTTP bindings (pass this pointer for lock-free server registration)
    HttpBindings::SetupBindings(*lua_, this);

    // Setup file watcher bindings (each thread owns its watcher)
    FileWatcherBindings::SetupBindings(*lua_);

    // Setup file ingestion bindings
    FileIngestionBindings::SetupBindings(*lua_);

    // Setup notification bindings
    NotificationBindings::SetupBindings(*lua_, notification_feed_);

    // Bind event registration system
    auto event_table = lua_->create_table();

    event_table["register"] = [this](const std::string& event_name, sol::function handler) {
        event_handlers_[event_name] = handler;
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
        command_queue_->enqueue(std::move(cmd));
    };

    command_table["stop_thread"] = [this](int thread_id) {
        Commands::StopThread cmd;
        cmd.thread_id = thread_id;
        command_queue_->enqueue(std::move(cmd));
    };

    (*lua_)["command"] = command_table;

    // Bind UI operations
    auto ui_table = lua_->create_table();

    ui_table["load_document"] = [this](const std::string& path, sol::optional<bool> show, sol::optional<std::string> doc_id) {
        Commands::LoadUIDocument cmd;
        cmd.document_path = path;
        cmd.show = show.value_or(true);
        cmd.document_id = doc_id.value_or("");
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["show_document"] = [this](const std::string& doc_id) {
        Commands::ShowUIDocument cmd;
        cmd.document_id = doc_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["hide_document"] = [this](const std::string& doc_id) {
        Commands::HideUIDocument cmd;
        cmd.document_id = doc_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_element_text"] = [this](const std::string& element_id, const std::string& text) {
        Commands::SetElementText cmd;
        cmd.element_id = element_id;
        cmd.text = text;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_element_attribute"] = [this](const std::string& element_id, const std::string& attribute_name, const std::string& value) {
        Commands::SetElementAttribute cmd;
        cmd.element_id = element_id;
        cmd.attribute_name = attribute_name;
        cmd.value = value;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_element_style"] = [this](const std::string& element_id, const std::string& property, const std::string& value) {
        Commands::SetElementStyle cmd;
        cmd.element_id = element_id;
        cmd.property = property;
        cmd.value = value;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["add_element_class"] = [this](const std::string& element_id, const std::string& class_name) {
        Commands::AddElementClass cmd;
        cmd.element_id = element_id;
        cmd.class_name = class_name;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["remove_element_class"] = [this](const std::string& element_id, const std::string& class_name) {
        Commands::RemoveElementClass cmd;
        cmd.element_id = element_id;
        cmd.class_name = class_name;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_texteditor_content"] = [this](const std::string& element_id, const std::string& content) {
        Commands::SetTextEditorContent cmd;
        cmd.element_id = element_id;
        cmd.content = content;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_texteditor_tokens"] = [this](const std::string& element_id, sol::table tokens) {
        Commands::SetTextEditorTokens cmd;
        cmd.element_id = element_id;
        cmd.tokens = TableToDynamicTable(tokens);
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_texteditor_editable"] = [this](const std::string& element_id, bool editable) {
        Commands::SetTextEditorEditable cmd;
        cmd.element_id = element_id;
        cmd.editable = editable;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_texteditor_modified"] = [this](const std::string& element_id, bool modified) {
        Commands::SetTextEditorModified cmd;
        cmd.element_id = element_id;
        cmd.modified = modified;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["set_texteditor_config"] = [this](const std::string& element_id, const std::string& config_key, sol::object value) {
        Commands::SetTextEditorConfig cmd;
        cmd.element_id = element_id;
        cmd.config_key = config_key;
        cmd.value = ObjectToDynamicValue(value);
        command_queue_->enqueue(std::move(cmd));
    };

    (*lua_)["ui"] = ui_table;

    // Bind data model operations
    auto data_table = lua_->create_table();

    data_table["bind"] = [this](const std::string& model_name, sol::table data) {
        // Convert Lua table to DynamicTable
        DynamicTable dynamic_data = TableToDynamicTable(data);

        // Send command to main thread to update DataStore and dirty the model
        Commands::UpdateDataModel cmd;
        cmd.model_name = model_name;
        cmd.data = std::move(dynamic_data);
        command_queue_->enqueue(std::move(cmd));
    };

    (*lua_)["data"] = data_table;

    // Bind thread info
    (*lua_)["thread_id"] = id_;
    (*lua_)["thread_name"] = script_path_;

    // Bind sleep function
    (*lua_)["sleep"] = [](double seconds) {
        std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(seconds * 1000)));
    };

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
        command_queue_->enqueue(std::move(cmd));
    };
}

