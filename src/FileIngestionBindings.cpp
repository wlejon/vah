#include "FileIngestionBindings.h"
#include "FileIngestion.h"
#include "Logger.h"
#include <filesystem>

namespace FileIngestionBindings {

void SetupBindings(sol::state& lua) {
    // Create ingestion namespace
    auto ingest_table = lua.create_table();

    // Bind IngestedFile as usertype
    lua.new_usertype<FileIngestion::IngestedFile>("IngestedFile",
        "path", &FileIngestion::IngestedFile::path,
        "relative_path", &FileIngestion::IngestedFile::relative_path,
        "name", &FileIngestion::IngestedFile::name,
        "extension", &FileIngestion::IngestedFile::extension,
        "mime_type", &FileIngestion::IngestedFile::mime_type,
        "size", &FileIngestion::IngestedFile::size,
        "modified_time", &FileIngestion::IngestedFile::modified_time,
        "is_binary", &FileIngestion::IngestedFile::is_binary
    );

    // Bind IngestionSession as usertype
    // Note: type_counts (unordered_map) is not directly bound due to sol2 limitations
    // Use get_type_summary() or session_to_table() to access type counts from Lua
    lua.new_usertype<FileIngestion::IngestionSession>("IngestionSession",
        "id", &FileIngestion::IngestionSession::id,
        "root_path", &FileIngestion::IngestionSession::root_path,
        "files", &FileIngestion::IngestionSession::files,
        "total_size", &FileIngestion::IngestionSession::total_size,
        "created_time", &FileIngestion::IngestionSession::created_time
    );

    // Ingest a single file
    ingest_table["file"] = [](const std::string& path) -> FileIngestion::IngestedFile {
        return FileIngestion::IngestFile(path);
    };

    // Ingest a directory
    ingest_table["directory"] = [](const std::string& path, sol::optional<int> max_files) -> std::vector<FileIngestion::IngestedFile> {
        size_t limit = max_files.value_or(10000);
        return FileIngestion::IngestDirectory(path, limit);
    };

    // Create an ingestion session (auto-detects file vs directory)
    ingest_table["create_session"] = [](const std::string& path) -> FileIngestion::IngestionSession {
        return FileIngestion::CreateSession(path);
    };

    // Convert ingestion session to Lua table (for data binding)
    ingest_table["session_to_table"] = [](sol::this_state s, const FileIngestion::IngestionSession& session) -> sol::table {
        sol::state_view lua(s);
        auto result = lua.create_table();

        result["id"] = session.id;
        result["root_path"] = session.root_path;
        result["total_size"] = static_cast<double>(session.total_size);
        result["created_time"] = session.created_time;
        result["file_count"] = session.files.size();

        // Convert files to array of tables
        auto files_array = lua.create_table();
        for (size_t i = 0; i < session.files.size(); i++) {
            const auto& file = session.files[i];
            auto file_table = lua.create_table();

            file_table["path"] = file.path;
            file_table["relative_path"] = file.relative_path;
            file_table["name"] = file.name;
            file_table["extension"] = file.extension;
            file_table["mime_type"] = file.mime_type;
            file_table["size"] = static_cast<double>(file.size);
            file_table["modified_time"] = file.modified_time;
            file_table["is_binary"] = file.is_binary;

            files_array[i + 1] = file_table; // Lua 1-based indexing
        }
        result["files"] = files_array;

        // Convert type counts
        auto type_counts_table = lua.create_table();
        for (const auto& [ext, count] : session.type_counts) {
            type_counts_table[ext] = count;
        }
        result["type_counts"] = type_counts_table;

        return result;
    };

    // Helper: Detect MIME type
    ingest_table["detect_mime_type"] = [](const std::string& path) -> std::string {
        std::filesystem::path p(path);
        return FileIngestion::DetectMimeType(path, p.extension().string());
    };

    // Helper: Check if file is binary
    ingest_table["is_binary"] = [](const std::string& path) -> bool {
        return FileIngestion::IsBinaryFile(path);
    };

    // Helper: Get file type summary from session
    ingest_table["get_type_summary"] = [](sol::this_state s, const FileIngestion::IngestionSession& session) -> sol::table {
        sol::state_view lua(s);
        auto summary = lua.create_table();

        // Create sorted list by count
        std::vector<std::pair<std::string, int>> sorted_types;
        for (const auto& [ext, count] : session.type_counts) {
            sorted_types.push_back({ext, count});
        }
        std::sort(sorted_types.begin(), sorted_types.end(),
                 [](const auto& a, const auto& b) { return a.second > b.second; });

        int index = 1;
        for (const auto& [ext, count] : sorted_types) {
            auto entry = lua.create_table();
            entry["extension"] = ext.empty() ? "(no extension)" : ext;
            entry["count"] = count;
            summary[index++] = entry;
        }

        return summary;
    };

    lua["ingest"] = ingest_table;

    LOG_INFO("FileIngestion bindings initialized");
}

} // namespace FileIngestionBindings
