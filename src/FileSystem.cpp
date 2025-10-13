#include "FileSystem.h"
#include "Logger.h"
#include <filesystem>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

namespace FileSystemBindings {

// Read entire file as string
std::tuple<sol::object, std::string> ReadFile(sol::this_state s, const std::string& path) {
    sol::state_view lua(s);

    try {
        std::ifstream file(path, std::ios::binary);
        if (!file.is_open()) {
            return {sol::nil, "Failed to open file: " + path};
        }

        std::stringstream buffer;
        buffer << file.rdbuf();
        return {sol::make_object(lua, buffer.str()), ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error reading file: ") + e.what()};
    }
}

// Write content to file
std::tuple<bool, std::string> WriteFile(const std::string& path, const std::string& content) {
    try {
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        if (!file.is_open()) {
            return {false, "Failed to open file for writing: " + path};
        }

        file << content;
        file.close();
        return {true, ""};
    }
    catch (const std::exception& e) {
        return {false, std::string("Error writing file: ") + e.what()};
    }
}

// List directory contents
std::tuple<sol::object, std::string> ListDir(sol::this_state s, const std::string& path) {
    sol::state_view lua(s);

    try {
        if (!fs::exists(path)) {
            return {sol::nil, "Path does not exist: " + path};
        }

        if (!fs::is_directory(path)) {
            return {sol::nil, "Path is not a directory: " + path};
        }

        auto result = lua.create_table();
        int index = 1;

        for (const auto& entry : fs::directory_iterator(path)) {
            auto item = lua.create_table();
            item["name"] = entry.path().filename().string();
            item["is_dir"] = entry.is_directory();

            if (entry.is_regular_file()) {
                try {
                    item["size"] = static_cast<double>(entry.file_size());
                } catch (...) {
                    item["size"] = 0.0;
                }
            } else {
                item["size"] = 0.0;
            }

            result[index++] = item;
        }

        return {result, ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error listing directory: ") + e.what()};
    }
}

// Get file/directory info
std::tuple<sol::object, std::string> Stat(sol::this_state s, const std::string& path) {
    sol::state_view lua(s);

    try {
        if (!fs::exists(path)) {
            return {sol::nil, "Path does not exist: " + path};
        }

        auto result = lua.create_table();
        result["exists"] = true;
        result["is_dir"] = fs::is_directory(path);
        result["is_file"] = fs::is_regular_file(path);

        if (fs::is_regular_file(path)) {
            try {
                result["size"] = static_cast<double>(fs::file_size(path));
            } catch (...) {
                result["size"] = 0.0;
            }
        } else {
            result["size"] = 0.0;
        }

        // Get last write time (as seconds since epoch)
        try {
            auto ftime = fs::last_write_time(path);
            auto sctp = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
                ftime - fs::file_time_type::clock::now() + std::chrono::system_clock::now()
            );
            auto time_since_epoch = sctp.time_since_epoch().count() / 1000000000.0;
            result["modified_time"] = time_since_epoch;
        } catch (...) {
            result["modified_time"] = 0.0;
        }

        return {result, ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error getting file info: ") + e.what()};
    }
}

// Check if path exists
bool Exists(const std::string& path) {
    try {
        return fs::exists(path);
    }
    catch (...) {
        return false;
    }
}

// Create directory (including parents)
std::tuple<bool, std::string> CreateDir(const std::string& path) {
    try {
        if (fs::exists(path)) {
            return {true, ""};
        }

        fs::create_directories(path);
        return {true, ""};
    }
    catch (const std::exception& e) {
        return {false, std::string("Error creating directory: ") + e.what()};
    }
}

// Get absolute path
std::tuple<sol::object, std::string> AbsolutePath(sol::this_state s, const std::string& path) {
    sol::state_view lua(s);

    try {
        auto abs = fs::absolute(path);
        return {sol::make_object(lua, abs.string()), ""};
    }
    catch (const std::exception& e) {
        return {sol::nil, std::string("Error getting absolute path: ") + e.what()};
    }
}

// Get current working directory
std::string GetCwd() {
    try {
        return fs::current_path().string();
    }
    catch (...) {
        return "";
    }
}

// Delete file or directory
std::tuple<bool, std::string> Delete(const std::string& path) {
    try {
        if (!fs::exists(path)) {
            return {false, "Path does not exist: " + path};
        }

        fs::remove(path);
        return {true, ""};
    }
    catch (const std::exception& e) {
        return {false, std::string("Error deleting path: ") + e.what()};
    }
}

// Recursively walk directory tree
std::tuple<bool, std::string> Walk(const std::string& path, sol::function callback) {
    try {
        if (!fs::exists(path)) {
            return {false, "Path does not exist: " + path};
        }

        if (!fs::is_directory(path)) {
            return {false, "Path is not a directory: " + path};
        }

        for (const auto& entry : fs::recursive_directory_iterator(path)) {
            try {
                std::string entry_path = entry.path().string();
                bool is_dir = entry.is_directory();
                size_t size = 0;

                if (entry.is_regular_file()) {
                    try {
                        size = entry.file_size();
                    } catch (...) {
                        size = 0;
                    }
                }

                // Call Lua callback with (path, is_dir, size)
                auto result = callback(entry_path, is_dir, static_cast<double>(size));

                // If callback returns false, stop walking
                if (result.valid() && result.get_type() == sol::type::boolean) {
                    if (!result.get<bool>()) {
                        break;
                    }
                }
            }
            catch (const std::exception&) {
                // Skip entries that cause errors (permissions, etc)
                continue;
            }
        }

        return {true, ""};
    }
    catch (const std::exception& e) {
        return {false, std::string("Error walking directory: ") + e.what()};
    }
}

// Join path components
std::string Join(sol::variadic_args args) {
    fs::path result;
    for (auto arg : args) {
        if (arg.is<std::string>()) {
            result /= arg.as<std::string>();
        }
    }
    return result.string();
}

// Get directory name (parent path)
std::string DirName(const std::string& path) {
    try {
        return fs::path(path).parent_path().string();
    }
    catch (...) {
        return "";
    }
}

// Get base name (filename with extension)
std::string BaseName(const std::string& path) {
    try {
        return fs::path(path).filename().string();
    }
    catch (...) {
        return "";
    }
}

// Get file extension
std::string Extension(const std::string& path) {
    try {
        return fs::path(path).extension().string();
    }
    catch (...) {
        return "";
    }
}

// Get stem (filename without extension)
std::string Stem(const std::string& path) {
    try {
        return fs::path(path).stem().string();
    }
    catch (...) {
        return "";
    }
}

void SetupBindings(sol::state& lua) {
    auto fs_table = lua.create_table();

    fs_table["read_file"] = ReadFile;
    fs_table["write_file"] = WriteFile;
    fs_table["list_dir"] = ListDir;
    fs_table["stat"] = Stat;
    fs_table["exists"] = Exists;
    fs_table["create_dir"] = CreateDir;
    fs_table["delete"] = Delete;
    fs_table["absolute_path"] = AbsolutePath;
    fs_table["get_cwd"] = GetCwd;
    fs_table["walk"] = Walk;
    fs_table["join"] = Join;
    fs_table["dirname"] = DirName;
    fs_table["basename"] = BaseName;
    fs_table["extension"] = Extension;
    fs_table["stem"] = Stem;

    // Convenience aliases
    fs_table["read"] = ReadFile;
    fs_table["write"] = WriteFile;
    fs_table["mkdir"] = CreateDir;
    fs_table["size"] = [](sol::this_state s, const std::string& path) -> std::tuple<sol::object, std::string> {
        auto [stat_result, err] = Stat(s, path);
        sol::state_view lua(s);
        if (!stat_result.valid() || err != "") {
            return {sol::make_object(lua, sol::nil), err};
        }
        sol::table stat_table = stat_result.as<sol::table>();
        return {stat_table["size"], ""};
    };

    lua["fs"] = fs_table;

    LOG_INFO("FileSystem bindings initialized");
}

} // namespace FileSystemBindings
