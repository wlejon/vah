#include "LuaThread.h"
#include "Logger.h"
#include "FileSystem.h"
#include "LuaConversions.h"
#include "LuaQueries.h"
#include "JsonBindings.h"
#include "SqliteBindings.h"
#include "HttpBindings.h"
#include "FileWatcherBindings.h"
#include "FileIngestionBindings.h"
#include "ClipboardBindings.h"
#include "DataStore.h"
#include "WorkflowThread.h"
#include <httplib.h>
#include <chrono>

// Use conversion utilities from LuaConversions namespace
using LuaConversions::DynamicValueToLua;
using LuaConversions::ObjectToDynamicValue;
using LuaConversions::TableToDynamicTable;
using LuaConversions::TableToDynamicRow;
using LuaConversions::TableToPayloadMap;

LuaThread::LuaThread(int id, const std::string& script_path,
                     moodycamel::ConcurrentQueue<Command>* command_queue,
                     moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue,
                     DataStore* data_store)
    : id_(id)
    , script_path_(script_path)
    , state_(State::Starting)
    , should_stop_(false)
    , is_paused_(false)
    , command_queue_(command_queue)
    , ui_event_queue_(ui_event_queue)
    , data_store_(data_store)
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
    start_time_ = std::chrono::steady_clock::now();
    thread_ = std::make_unique<std::thread>(&LuaThread::ThreadMain, this);
}

void LuaThread::Stop() {
    should_stop_.store(true, std::memory_order_release);
    state_.store(State::Stopping, std::memory_order_release);

    // Stop any HTTP server running on this thread
    // Use mutex to safely access server pointer and prevent use-after-free
    {
        std::lock_guard<std::mutex> lock(http_server_mutex_);
        if (active_http_server_) {
            active_http_server_->stop();  // Thread-safe call to unblock listen()
        }
    }
}

void LuaThread::SetActiveHttpServer(httplib::Server* server) {
    std::lock_guard<std::mutex> lock(http_server_mutex_);
    active_http_server_ = server;
}

void LuaThread::ClearActiveHttpServer() {
    std::lock_guard<std::mutex> lock(http_server_mutex_);
    active_http_server_ = nullptr;
}

void LuaThread::Pause() {
    is_paused_.store(true, std::memory_order_release);
    state_.store(State::Paused, std::memory_order_release);
}

void LuaThread::Resume() {
    is_paused_.store(false, std::memory_order_release);
    state_.store(State::Running, std::memory_order_release);
}

void LuaThread::SetParent(int parent_id, int parent_request_id) {
    parent_thread_id_ = parent_id;
    parent_request_id_ = parent_request_id;
}

double LuaThread::GetUptime() const {
    auto now = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time_);
    return duration.count() / 1000.0;  // Convert to seconds
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

    // Note: Query responses are now handled via promises in commands
    // This method still handles event-based responses if needed
    for (auto& response : responses) {
        // Handle any non-query responses here if needed in the future
        LOG_WARN("Lua thread {} received unexpected response for request {}", id_, response.request_id);
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
            state_.store(State::Error, std::memory_order_release);
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
                state_.store(State::Error, std::memory_order_release);
                return;
            }
        }

        state_.store(State::Running, std::memory_order_release);
        LOG_INFO("Lua thread {} running", id_);

        // 30hz update loop (33.33ms per frame)
        constexpr auto frame_duration = std::chrono::milliseconds(33);
        auto next_frame_time = std::chrono::steady_clock::now();

        sol::optional<sol::function> update_fn = (*lua_)["update"];

        while (!should_stop_.load(std::memory_order_acquire)) {
            // Handle pause
            while (is_paused_.load(std::memory_order_acquire) && !should_stop_.load(std::memory_order_acquire)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }

            if (should_stop_.load(std::memory_order_acquire)) break;

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
                    // Special handling for system_ready events
                    // Try to call optional {system}_ready() callback
                    if (ui_event.name == "system_ready") {
                        auto system_it = ui_event.payload.find("system");
                        if (system_it != ui_event.payload.end()) {
                            std::string system_name;
                            if (std::holds_alternative<std::string>(system_it->second)) {
                                system_name = std::get<std::string>(system_it->second);
                            }

                            if (!system_name.empty()) {
                                // Look for optional {system}_ready callback
                                std::string callback_name = system_name + "_ready";
                                sol::optional<sol::function> callback_fn = (*lua_)[callback_name];
                                if (callback_fn) {
                                    try {
                                        callback_fn.value()();
                                        LOG_INFO("Lua thread {} called {}()", id_, callback_name);
                                    } catch (const sol::error& e) {
                                        LOG_ERROR("Lua thread {} error in {}: {}", id_, callback_name, e.what());
                                    } catch (const std::exception& e) {
                                        LOG_ERROR("Lua thread {} C++ exception in {}: {}", id_, callback_name, e.what());
                                    } catch (...) {
                                        LOG_ERROR("Lua thread {} unknown exception in {}", id_, callback_name);
                                    }
                                }
                            }
                        }
                    }

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
                        } catch (const std::exception& e) {
                            LOG_ERROR("Lua thread {} C++ exception in event handler for '{}': {}",
                                     id_, ui_event.name, e.what());
                        } catch (...) {
                            LOG_ERROR("Lua thread {} unknown exception in event handler for '{}'",
                                     id_, ui_event.name);
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
                    state_.store(State::Error, std::memory_order_release);
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

        state_.store(State::Stopped, std::memory_order_release);
        LOG_INFO("Lua thread {} finished normally", id_);

    } catch (const std::exception& e) {
        error_message_ = e.what();
        LOG_ERROR("Lua thread {} exception: {}", id_, error_message_);
        state_.store(State::Error, std::memory_order_release);
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

    // Note: Notification system is now managed by Lua (scripts/notifications.lua)
    // Threads can use: local notif = require('notifications'); notif.add({...})

    // Bind event registration system
    auto event_table = lua_->create_table();

    event_table["register"] = [this](const std::string& event_name, sol::function handler) {
        event_handlers_[event_name] = handler;
    };

    event_table["register_global"] = [this](const std::string& event_name, sol::function handler) {
        // Register handler locally
        event_handlers_[event_name] = handler;

        // Send command to main thread to register this thread for global event
        Commands::RegisterGlobalEvent cmd;
        cmd.event_name = event_name;
        cmd.thread_id = id_;
        command_queue_->enqueue(std::move(cmd));
    };

    event_table["unregister_global"] = [this](const std::string& event_name) {
        // Remove handler locally
        event_handlers_.erase(event_name);

        // Send command to main thread to unregister global event
        Commands::UnregisterGlobalEvent cmd;
        cmd.event_name = event_name;
        command_queue_->enqueue(std::move(cmd));
    };

    event_table["trigger_global"] = [this](const std::string& event_name, sol::optional<sol::table> payload_table) {
        // Build payload from Lua table
        PayloadMap payload;
        if (payload_table) {
            payload = TableToPayloadMap(payload_table.value());
        }

        // Send command to main thread to trigger global event
        Commands::TriggerGlobalEvent cmd;
        cmd.event_name = event_name;
        cmd.payload = std::move(payload);
        command_queue_->enqueue(std::move(cmd));
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

    command_table["close_application"] = [this]() {
        Commands::CloseApplication cmd;
        command_queue_->enqueue(std::move(cmd));
    };

    (*lua_)["command"] = command_table;

    // Bind system operations
    auto system_table = lua_->create_table();

    system_table["mark_ready"] = [this](const std::string& system_name) {
        Commands::MarkSystemReady cmd;
        cmd.system_name = system_name;
        command_queue_->enqueue(std::move(cmd));
    };

    (*lua_)["system"] = system_table;

    // Bind UI operations
    auto ui_table = lua_->create_table();

    ui_table["load_document"] = [this](const std::string& path, sol::optional<bool> show, sol::optional<std::string> doc_id) {
        Commands::LoadUIDocument cmd;
        cmd.thread_id = id_;
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

    ui_table["texteditor_copy"] = [this](const std::string& element_id) {
        Commands::TextEditorCopy cmd;
        cmd.element_id = element_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["texteditor_paste"] = [this](const std::string& element_id) {
        Commands::TextEditorPaste cmd;
        cmd.element_id = element_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["texteditor_cut"] = [this](const std::string& element_id) {
        Commands::TextEditorCut cmd;
        cmd.element_id = element_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["texteditor_select_all"] = [this](const std::string& element_id) {
        Commands::TextEditorSelectAll cmd;
        cmd.element_id = element_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["texteditor_undo"] = [this](const std::string& element_id) {
        Commands::TextEditorUndo cmd;
        cmd.element_id = element_id;
        command_queue_->enqueue(std::move(cmd));
    };

    ui_table["texteditor_redo"] = [this](const std::string& element_id) {
        Commands::TextEditorRedo cmd;
        cmd.element_id = element_id;
        command_queue_->enqueue(std::move(cmd));
    };

    // Document query operations (synchronous - blocks until response arrives)
    ui_table["list_documents"] = [this]() {
        return LuaQueries::QueryDocumentList(this);
    };

    ui_table["get_document_info"] = [this](const std::string& document_id) {
        return LuaQueries::QueryDocumentInfo(this, document_id);
    };

    (*lua_)["ui"] = ui_table;

    // Bind clipboard operations
    ClipboardBindings::SetupBindings(*lua_);

    // Bind data model operations (synchronous via promise-in-command pattern)
    auto datamodel_table = lua_->create_table();

    datamodel_table["bind_table"] = [this](const std::string& model_name, sol::table data) {
        // If thread is shutting down, skip binding to avoid deadlock
        // (Main thread may be blocked in Join() waiting for us to exit)
        if (should_stop_.load(std::memory_order_acquire)) {
            LOG_DEBUG("Skipping bind_table('{}') - thread {} is shutting down", model_name, id_);
            return;
        }

        // Convert Lua table to DynamicTable (array of objects)
        DynamicTable dynamic_data = TableToDynamicTable(data);

        // Create promise/future pair for synchronous blocking
        auto promise = std::make_shared<std::promise<void>>();
        auto future = promise->get_future();

        // Send command to main thread with promise
        Commands::BindDataTable cmd;
        cmd.requesting_thread_id = id_;
        cmd.request_id = next_request_id_++;
        cmd.model_name = model_name;
        cmd.data = std::move(dynamic_data);
        cmd.promise = promise;
        command_queue_->enqueue(std::move(cmd));

        // Block until main thread processes the binding
        future.get();
    };

    datamodel_table["bind_object"] = [this](const std::string& object_name, sol::table data) {
        // If thread is shutting down, skip binding to avoid deadlock
        // (Main thread may be blocked in Join() waiting for us to exit)
        if (should_stop_.load(std::memory_order_acquire)) {
            LOG_DEBUG("Skipping bind_object('{}') - thread {} is shutting down", object_name, id_);
            return;
        }

        // Convert Lua table to DynamicRow (single object)
        DynamicRow dynamic_data = TableToDynamicRow(data);

        // Create promise/future pair for synchronous blocking
        auto promise = std::make_shared<std::promise<void>>();
        auto future = promise->get_future();

        // Send command to main thread with promise
        Commands::BindDataObject cmd;
        cmd.requesting_thread_id = id_;
        cmd.request_id = next_request_id_++;
        cmd.object_name = object_name;
        cmd.data = std::move(dynamic_data);
        cmd.promise = promise;
        command_queue_->enqueue(std::move(cmd));

        // Block until main thread processes the binding
        future.get();
    };

    (*lua_)["datamodel"] = datamodel_table;

    // Bind thread query operations (synchronous - blocks until response arrives)
    auto thread_table = lua_->create_table();

    thread_table["list"] = [this]() {
        return LuaQueries::QueryThreadList(this);
    };

    thread_table["get_info"] = [this](int thread_id) {
        return LuaQueries::QueryThreadInfo(this, thread_id);
    };

    (*lua_)["thread"] = thread_table;

    // Register workflow thread creation (moved to WorkflowThread.cpp for clarity)
    RegisterWorkflowThreadBindings(*lua_);

    // Bind thread info (backward compatibility)
    (*lua_)["thread_id"] = id_;
    (*lua_)["thread_name"] = script_path_;

    // Bind sleep function
    (*lua_)["sleep"] = [](double seconds) {
        std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(seconds * 1000)));
    };

    // Note: process_responses is no longer needed - queries are now synchronous and block automatically

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

