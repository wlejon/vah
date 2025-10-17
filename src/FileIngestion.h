#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>

namespace FileIngestion {

// Represents a single ingested file
struct IngestedFile {
    std::string path;               // Full path to the file
    std::string relative_path;      // Path relative to ingestion root
    std::string name;               // File name with extension
    std::string extension;          // File extension (lowercase, with dot)
    std::string mime_type;          // Detected MIME type
    uint64_t size;                  // File size in bytes
    double modified_time;           // Last modified time (seconds since epoch)
    bool is_binary;                 // True if file appears to be binary
};

// Represents an ingestion session
struct IngestionSession {
    std::string id;                                     // Unique session ID
    std::string root_path;                              // Root path of ingestion
    std::vector<IngestedFile> files;                    // All ingested files
    std::unordered_map<std::string, int> type_counts;   // Count by extension
    uint64_t total_size;                                // Total bytes ingested
    double created_time;                                // Session creation time
};

// Detect MIME type from file extension and content
std::string DetectMimeType(const std::string& path, const std::string& extension);

// Check if file appears to be binary (vs text)
bool IsBinaryFile(const std::string& path, size_t sample_size = 512);

// Ingest a single file
IngestedFile IngestFile(const std::string& path, const std::string& relative_path = "");

// Ingest a directory recursively
std::vector<IngestedFile> IngestDirectory(const std::string& path, size_t max_files = 10000);

// Create an ingestion session
IngestionSession CreateSession(const std::string& root_path);

} // namespace FileIngestion
