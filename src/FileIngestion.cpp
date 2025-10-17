#include "FileIngestion.h"
#include "Logger.h"
#include <filesystem>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <chrono>
#include <iomanip>

namespace fs = std::filesystem;

namespace FileIngestion {

// Comprehensive MIME type detection based on extension
std::string DetectMimeType(const std::string& path, const std::string& extension) {
    std::string lower_ext = extension;
    std::transform(lower_ext.begin(), lower_ext.end(), lower_ext.begin(), ::tolower);

    // Text formats
    if (lower_ext == ".txt") return "text/plain";
    if (lower_ext == ".md" || lower_ext == ".markdown") return "text/markdown";
    if (lower_ext == ".html" || lower_ext == ".htm") return "text/html";
    if (lower_ext == ".css") return "text/css";
    if (lower_ext == ".xml") return "text/xml";
    if (lower_ext == ".csv") return "text/csv";
    if (lower_ext == ".tsv") return "text/tab-separated-values";

    // Code/Script
    if (lower_ext == ".js") return "application/javascript";
    if (lower_ext == ".json") return "application/json";
    if (lower_ext == ".lua") return "text/x-lua";
    if (lower_ext == ".py") return "text/x-python";
    if (lower_ext == ".cpp" || lower_ext == ".cc" || lower_ext == ".cxx") return "text/x-c++";
    if (lower_ext == ".c") return "text/x-c";
    if (lower_ext == ".h" || lower_ext == ".hpp") return "text/x-c++";
    if (lower_ext == ".java") return "text/x-java";
    if (lower_ext == ".rs") return "text/x-rust";
    if (lower_ext == ".go") return "text/x-go";
    if (lower_ext == ".rb") return "text/x-ruby";
    if (lower_ext == ".php") return "text/x-php";
    if (lower_ext == ".sh" || lower_ext == ".bash") return "text/x-shellscript";
    if (lower_ext == ".sql") return "text/x-sql";
    if (lower_ext == ".yaml" || lower_ext == ".yml") return "text/yaml";
    if (lower_ext == ".toml") return "text/x-toml";

    // Documents
    if (lower_ext == ".pdf") return "application/pdf";
    if (lower_ext == ".doc") return "application/msword";
    if (lower_ext == ".docx") return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    if (lower_ext == ".xls") return "application/vnd.ms-excel";
    if (lower_ext == ".xlsx") return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    if (lower_ext == ".ppt") return "application/vnd.ms-powerpoint";
    if (lower_ext == ".pptx") return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    if (lower_ext == ".odt") return "application/vnd.oasis.opendocument.text";
    if (lower_ext == ".ods") return "application/vnd.oasis.opendocument.spreadsheet";
    if (lower_ext == ".odp") return "application/vnd.oasis.opendocument.presentation";
    if (lower_ext == ".rtf") return "application/rtf";

    // Images
    if (lower_ext == ".jpg" || lower_ext == ".jpeg") return "image/jpeg";
    if (lower_ext == ".png") return "image/png";
    if (lower_ext == ".gif") return "image/gif";
    if (lower_ext == ".bmp") return "image/bmp";
    if (lower_ext == ".svg") return "image/svg+xml";
    if (lower_ext == ".webp") return "image/webp";
    if (lower_ext == ".ico") return "image/x-icon";
    if (lower_ext == ".tif" || lower_ext == ".tiff") return "image/tiff";
    if (lower_ext == ".heic") return "image/heic";
    if (lower_ext == ".raw") return "image/x-raw";

    // Audio
    if (lower_ext == ".mp3") return "audio/mpeg";
    if (lower_ext == ".wav") return "audio/wav";
    if (lower_ext == ".ogg") return "audio/ogg";
    if (lower_ext == ".flac") return "audio/flac";
    if (lower_ext == ".aac") return "audio/aac";
    if (lower_ext == ".m4a") return "audio/mp4";
    if (lower_ext == ".wma") return "audio/x-ms-wma";

    // Video
    if (lower_ext == ".mp4") return "video/mp4";
    if (lower_ext == ".avi") return "video/x-msvideo";
    if (lower_ext == ".mkv") return "video/x-matroska";
    if (lower_ext == ".mov") return "video/quicktime";
    if (lower_ext == ".wmv") return "video/x-ms-wmv";
    if (lower_ext == ".flv") return "video/x-flv";
    if (lower_ext == ".webm") return "video/webm";

    // Archives
    if (lower_ext == ".zip") return "application/zip";
    if (lower_ext == ".tar") return "application/x-tar";
    if (lower_ext == ".gz") return "application/gzip";
    if (lower_ext == ".bz2") return "application/x-bzip2";
    if (lower_ext == ".7z") return "application/x-7z-compressed";
    if (lower_ext == ".rar") return "application/x-rar-compressed";

    // Databases
    if (lower_ext == ".db" || lower_ext == ".sqlite" || lower_ext == ".sqlite3") return "application/x-sqlite3";

    // Default
    return "application/octet-stream";
}

// Check if file is binary by examining first N bytes
bool IsBinaryFile(const std::string& path, size_t sample_size) {
    try {
        std::ifstream file(path, std::ios::binary);
        if (!file.is_open()) {
            return false; // Can't read, assume text
        }

        std::vector<char> buffer(sample_size);
        file.read(buffer.data(), sample_size);
        size_t bytes_read = file.gcount();

        if (bytes_read == 0) {
            return false; // Empty file, treat as text
        }

        // Check for null bytes (strong indicator of binary)
        for (size_t i = 0; i < bytes_read; i++) {
            if (buffer[i] == '\0') {
                return true;
            }
        }

        // Check percentage of non-printable characters
        size_t non_printable = 0;
        for (size_t i = 0; i < bytes_read; i++) {
            unsigned char c = static_cast<unsigned char>(buffer[i]);
            // Allow common whitespace and printable ASCII
            if (c < 32 && c != '\t' && c != '\n' && c != '\r') {
                non_printable++;
            } else if (c >= 127 && c < 160) {
                non_printable++;
            }
        }

        // If more than 30% non-printable, consider binary
        double ratio = static_cast<double>(non_printable) / bytes_read;
        return ratio > 0.3;

    } catch (const std::exception& e) {
        LOG_WARN("Error checking if file is binary '{}': {}", path, e.what());
        return false;
    }
}

IngestedFile IngestFile(const std::string& path, const std::string& relative_path) {
    IngestedFile file;

    try {
        file.path = path;
        file.relative_path = relative_path.empty() ? fs::path(path).filename().string() : relative_path;
        file.name = fs::path(path).filename().string();
        file.extension = fs::path(path).extension().string();

        // Normalize extension to lowercase
        std::transform(file.extension.begin(), file.extension.end(),
                      file.extension.begin(), ::tolower);

        file.size = fs::file_size(path);

        // Get modified time
        auto ftime = fs::last_write_time(path);
        auto sctp = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
            ftime - fs::file_time_type::clock::now() + std::chrono::system_clock::now()
        );
        file.modified_time = sctp.time_since_epoch().count() / 1000000000.0;

        // Detect MIME type
        file.mime_type = DetectMimeType(path, file.extension);

        // Check if binary
        file.is_binary = IsBinaryFile(path);

    } catch (const std::exception& e) {
        LOG_ERROR("Error ingesting file '{}': {}", path, e.what());
        file.size = 0;
        file.modified_time = 0;
        file.mime_type = "application/octet-stream";
        file.is_binary = false;
    }

    return file;
}

std::vector<IngestedFile> IngestDirectory(const std::string& path, size_t max_files) {
    std::vector<IngestedFile> files;

    try {
        if (!fs::exists(path)) {
            LOG_ERROR("Path does not exist: {}", path);
            return files;
        }

        if (!fs::is_directory(path)) {
            LOG_ERROR("Path is not a directory: {}", path);
            return files;
        }

        fs::path root(path);

        for (const auto& entry : fs::recursive_directory_iterator(path)) {
            try {
                if (entry.is_regular_file()) {
                    // Check file limit
                    if (files.size() >= max_files) {
                        LOG_WARN("Reached max file limit ({}) during ingestion of '{}'", max_files, path);
                        break;
                    }

                    // Calculate relative path
                    fs::path entry_path = entry.path();
                    fs::path rel_path = fs::relative(entry_path, root);

                    IngestedFile file = IngestFile(entry_path.string(), rel_path.string());
                    files.push_back(file);
                }
            } catch (const std::exception& e) {
                LOG_WARN("Error processing entry in directory '{}': {}", path, e.what());
                continue;
            }
        }

    } catch (const std::exception& e) {
        LOG_ERROR("Error ingesting directory '{}': {}", path, e.what());
    }

    return files;
}

IngestionSession CreateSession(const std::string& root_path) {
    IngestionSession session;

    try {
        // Generate session ID from timestamp
        auto now = std::chrono::system_clock::now();
        auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()
        ).count();

        std::ostringstream oss;
        oss << "session_" << timestamp;
        session.id = oss.str();

        session.root_path = root_path;
        session.created_time = timestamp / 1000.0;
        session.total_size = 0;

        // Determine if it's a file or directory
        if (fs::is_directory(root_path)) {
            LOG_INFO("Ingesting directory: {}", root_path);
            session.files = IngestDirectory(root_path);
        } else if (fs::is_regular_file(root_path)) {
            LOG_INFO("Ingesting single file: {}", root_path);
            session.files.push_back(IngestFile(root_path));
        } else {
            LOG_ERROR("Path is neither file nor directory: {}", root_path);
            return session;
        }

        // Calculate statistics
        for (const auto& file : session.files) {
            session.total_size += file.size;
            session.type_counts[file.extension]++;
        }

        LOG_INFO("Ingestion session '{}' created: {} files, {} bytes",
                session.id, session.files.size(), session.total_size);

    } catch (const std::exception& e) {
        LOG_ERROR("Error creating ingestion session for '{}': {}", root_path, e.what());
    }

    return session;
}

} // namespace FileIngestion
