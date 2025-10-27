#include "FileWatcherBindings.h"
#include "Logger.h"
#include <efsw/efsw.hpp>
#include <memory>
#include <unordered_map>

namespace FileWatcherBindings {

// Listener that calls Lua callback directly (no cross-thread communication)
class LuaFileWatchListener : public efsw::FileWatchListener {
public:
    LuaFileWatchListener(sol::function callback)
        : callback_(callback)
    {}

    void handleFileAction(efsw::WatchID watch_id,
                         const std::string& dir,
                         const std::string& filename,
                         efsw::Action action,
                         std::string old_filename) override {

        if (!callback_.valid()) {
            return;
        }

        std::string event_type;
        switch (action) {
            case efsw::Actions::Add:
                event_type = "created";
                break;
            case efsw::Actions::Delete:
                event_type = "deleted";
                break;
            case efsw::Actions::Modified:
                event_type = "modified";
                break;
            case efsw::Actions::Moved:
                event_type = "moved";
                break;
            default:
                return;
        }

        std::string full_path = dir + filename;

        // Call Lua callback directly (we're in the same thread)
        try {
            if (action == efsw::Actions::Moved) {
                callback_(full_path, event_type, old_filename);
            } else {
                callback_(full_path, event_type);
            }
        } catch (const sol::error& e) {
            LOG_ERROR("File watch callback error: {}", e.what());
        }
    }

private:
    sol::function callback_;
};

// Per-thread watcher state (owned by the Lua thread)
class FileWatcherWrapper {
public:
    FileWatcherWrapper() {
        watcher_ = std::make_unique<efsw::FileWatcher>();
    }

    ~FileWatcherWrapper() {
        listeners_.clear();
        watcher_.reset();
    }

    int AddWatch(const std::string& path, bool recursive, sol::function callback) {
        auto listener = std::make_unique<LuaFileWatchListener>(callback);
        efsw::WatchID watch_id = watcher_->addWatch(path, listener.get(), recursive);

        if (watch_id < 0) {
            return -1;
        }

        // Store listener to keep it alive
        listeners_[watch_id] = std::move(listener);

        // Start watching if not already started
        watcher_->watch();

        return static_cast<int>(watch_id);
    }

    bool RemoveWatch(int watch_id) {
        watcher_->removeWatch(static_cast<efsw::WatchID>(watch_id));
        listeners_.erase(watch_id);
        return true;
    }

private:
    std::unique_ptr<efsw::FileWatcher> watcher_;
    std::unordered_map<efsw::WatchID, std::unique_ptr<LuaFileWatchListener>> listeners_;
};

void SetupBindings(sol::state& lua) {
    // Register the FileWatcherWrapper type
    lua.new_usertype<FileWatcherWrapper>("FileWatcher",
        sol::constructors<FileWatcherWrapper()>(),

        "add", [](FileWatcherWrapper& self, const std::string& path,
                  sol::optional<bool> recursive,
                  sol::function callback) -> std::tuple<sol::object, std::string> {
            sol::state_view lua_view(callback.lua_state());

            bool is_recursive = recursive.value_or(false);
            int watch_id = self.AddWatch(path, is_recursive, callback);

            if (watch_id < 0) {
                return {sol::nil, "Failed to add watch for path: " + path};
            }

            LOG_DEBUG("Added file watch: {} (recursive: {}, watch_id: {})",
                     path, is_recursive, watch_id);

            return {sol::make_object(lua_view, watch_id), ""};
        },

        "remove", [](FileWatcherWrapper& self, int watch_id) -> std::tuple<bool, std::string> {
            bool success = self.RemoveWatch(watch_id);
            if (success) {
                LOG_DEBUG("Removed file watch: {}", watch_id);
                return {true, ""};
            }
            return {false, "Failed to remove watch"};
        }
    );
}

} // namespace FileWatcherBindings
