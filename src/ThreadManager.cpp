#include "ThreadManager.h"
#include "Logger.h"
#include <fstream>
#include <sstream>

namespace {
    // Escape a string for Lua (handle quotes and special characters)
    std::string EscapeLuaString(const std::string& str) {
        std::string result;
        for (char c : str) {
            if (c == '"' || c == '\\') {
                result += '\\';
            }
            result += c;
        }
        return result;
    }

    // Convert sol::object to Lua code
    void SerializeLuaValue(std::ostream& out, const sol::object& obj, int indent_level = 0) {
        std::string indent(indent_level * 2, ' ');

        if (!obj.valid() || obj.is<sol::nil_t>()) {
            out << "nil";
            return;
        }

        sol::type obj_type = obj.get_type();

        switch (obj_type) {
            case sol::type::boolean:
                out << (obj.as<bool>() ? "true" : "false");
                break;

            case sol::type::number:
                // Try int first for cleaner output
                if (obj.is<int>()) {
                    out << obj.as<int>();
                } else {
                    out << obj.as<double>();
                }
                break;

            case sol::type::string:
                out << '"' << EscapeLuaString(obj.as<std::string>()) << '"';
                break;

            case sol::type::table: {
                sol::table tbl = obj.as<sol::table>();

                // Check if it's an array (consecutive integer keys starting from 1)
                bool is_array = true;
                size_t expected_index = 1;
                size_t count = 0;

                for (const auto& [key, value] : tbl) {
                    count++;
                    if (!key.is<int>() || key.as<int>() != static_cast<int>(expected_index)) {
                        is_array = false;
                        break;
                    }
                    expected_index++;
                }

                out << "{";

                if (count > 0) {
                    out << "\n";

                    if (is_array) {
                        // Array-style
                        for (const auto& [key, value] : tbl) {
                            out << indent << "  ";
                            SerializeLuaValue(out, value, indent_level + 1);
                            out << ",\n";
                        }
                    } else {
                        // Object/map style
                        for (const auto& [key, value] : tbl) {
                            out << indent << "  ";

                            // Write key
                            if (key.is<std::string>()) {
                                std::string key_str = key.as<std::string>();
                                // Check if key is a valid Lua identifier
                                bool is_identifier = !key_str.empty() &&
                                    (std::isalpha(key_str[0]) || key_str[0] == '_');
                                for (size_t i = 1; i < key_str.size() && is_identifier; ++i) {
                                    is_identifier = std::isalnum(key_str[i]) || key_str[i] == '_';
                                }

                                if (is_identifier) {
                                    out << key_str << " = ";
                                } else {
                                    out << "[\"" << EscapeLuaString(key_str) << "\"] = ";
                                }
                            } else if (key.is<int>()) {
                                out << "[" << key.as<int>() << "] = ";
                            } else {
                                continue; // Skip unsupported key types
                            }

                            // Write value
                            SerializeLuaValue(out, value, indent_level + 1);
                            out << ",\n";
                        }
                    }

                    out << indent;
                }

                out << "}";
                break;
            }

            default:
                // Unsupported types (functions, userdata, etc.) -> nil
                out << "nil";
                break;
        }
    }
}

ThreadManager::ThreadManager(moodycamel::ConcurrentQueue<Command>* command_queue,
                             moodycamel::ConcurrentQueue<UIEvent>* ui_event_queue,
                             DataStore* data_store,
                             NotificationFeed* notification_feed)
    : command_queue_(command_queue)
    , ui_event_queue_(ui_event_queue)
    , data_store_(data_store)
    , notification_feed_(notification_feed)
{
}

ThreadManager::~ThreadManager() {
    StopAll();
}

LuaThread* ThreadManager::GetThread(int thread_id) const {
    if (thread_id < 0 || thread_id >= static_cast<int>(threads_.size())) {
        return nullptr;
    }
    return threads_[thread_id].get();
}

int ThreadManager::SpawnThread(const std::string& script_path) {
    int thread_id = static_cast<int>(threads_.size());

    auto thread = std::make_unique<LuaThread>(thread_id, script_path, command_queue_, ui_event_queue_, data_store_, notification_feed_);
    thread->Start();

    threads_.push_back(std::move(thread));

    LOG_INFO("ThreadManager: Spawned thread {} for script '{}'", thread_id, script_path);
    return thread_id;
}

int ThreadManager::SpawnThread(const std::string& script_path, int parent_thread_id, int parent_request_id) {
    int thread_id = static_cast<int>(threads_.size());

    auto thread = std::make_unique<LuaThread>(thread_id, script_path, command_queue_, ui_event_queue_, data_store_, notification_feed_);

    if (parent_thread_id != 0) {
        thread->SetParent(parent_thread_id, parent_request_id);
    }

    thread->Start();

    threads_.push_back(std::move(thread));

    LOG_INFO("ThreadManager: Spawned thread {} for script '{}' (parent: {})", thread_id, script_path, parent_thread_id);
    return thread_id;
}

void ThreadManager::StopThread(int thread_id) {
    LuaThread* thread = GetThread(thread_id);

    if (thread != nullptr) {
        thread->Stop();
        thread->Join();
        threads_[thread_id].reset();  // Set to nullptr
        LOG_INFO("ThreadManager: Stopped thread {}", thread_id);
    }
}

void ThreadManager::StopAll() {
    size_t thread_count = 0;

    // First pass: stop all threads
    for (auto& thread : threads_) {
        if (thread != nullptr) {
            thread->Stop();
            ++thread_count;
        }
    }

    LOG_INFO("ThreadManager: Stopping all {} threads", thread_count);

    // Second pass: join and delete all threads
    for (auto& thread : threads_) {
        if (thread != nullptr) {
            thread->Join();
            thread.reset();
        }
    }
}

void ThreadManager::PauseThread(int thread_id) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        thread->Pause();
        LOG_INFO("ThreadManager: Paused thread {}", thread_id);
    }
}

void ThreadManager::ResumeThread(int thread_id) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        thread->Resume();
        LOG_INFO("ThreadManager: Resumed thread {}", thread_id);
    }
}

void ThreadManager::PauseAll() {
    LOG_INFO("ThreadManager: Pausing all threads");

    for (auto& thread : threads_) {
        if (thread != nullptr) {
            thread->Pause();
        }
    }
}

void ThreadManager::ResumeAll() {
    LOG_INFO("ThreadManager: Resuming all threads");

    for (auto& thread : threads_) {
        if (thread != nullptr) {
            thread->Resume();
        }
    }
}

void ThreadManager::SaveThread(int thread_id, const std::string& save_path) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        // Pause thread before saving
        bool was_running = thread->IsRunning();
        if (was_running) {
            thread->Pause();
        }

        try {
            // Call lua save hook
            sol::object save_data = thread->CallSaveHook();

            // Write to file as Lua code
            std::ofstream file(save_path);
            if (!file.is_open()) {
                LOG_ERROR("ThreadManager: Failed to open file '{}' for writing", save_path);
            } else {
                file << "-- Thread " << thread_id << " save data\n";
                file << "return ";
                SerializeLuaValue(file, save_data);
                file << "\n";
                file.close();
                LOG_INFO("ThreadManager: Saved thread {} to '{}'", thread_id, save_path);
            }
        } catch (const std::exception& e) {
            LOG_ERROR("ThreadManager: Error saving thread {}: {}", thread_id, e.what());
        }

        // Resume if it was running
        if (was_running) {
            thread->Resume();
        }
    }
}

void ThreadManager::LoadThread(int thread_id, const std::string& load_path) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        try {
            // Load into thread (will execute Lua file and call load hook)
            thread->LoadFromLuaFile(load_path);

            LOG_INFO("ThreadManager: Loaded thread {} from '{}'", thread_id, load_path);
        } catch (const std::exception& e) {
            LOG_ERROR("ThreadManager: Error loading thread {}: {}", thread_id, e.what());
        }
    }
}

bool ThreadManager::HasThread(int thread_id) const {
    return GetThread(thread_id) != nullptr;
}

LuaThread::State ThreadManager::GetThreadState(int thread_id) const {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        return thread->GetState();
    }
    return LuaThread::State::Stopped;
}

std::string ThreadManager::GetThreadError(int thread_id) const {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        return thread->GetError();
    }
    return "";
}

size_t ThreadManager::GetThreadCount() const {
    size_t count = 0;
    for (const auto& thread : threads_) {
        if (thread != nullptr) {
            ++count;
        }
    }
    return count;
}

std::vector<int> ThreadManager::GetAllThreadIds() const {
    std::vector<int> ids;
    for (size_t i = 0; i < threads_.size(); ++i) {
        if (threads_[i] != nullptr) {
            ids.push_back(static_cast<int>(i));
        }
    }
    return ids;
}

moodycamel::ConcurrentQueue<Response>* ThreadManager::GetThreadResponseQueue(int thread_id) {
    LuaThread* thread = GetThread(thread_id);
    if (thread != nullptr) {
        return thread->GetResponseQueue();
    }
    return nullptr;
}
