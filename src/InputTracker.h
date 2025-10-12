#pragma once

#include <sqlite3.h>
#include <string>
#include <unordered_map>
#include <mutex>
#include "InputState.h"

/**
 * InputTracker - SQLite-backed input tracking system with transaction log
 *
 * This class tracks changes to form inputs and maintains both an in-memory
 * cache for fast queries and a SQLite database for persistent storage.
 *
 * Event Flow:
 *   1. OnFocus: User focuses input -> store original value in cache
 *   2. OnChange: User types -> update current value in cache only
 *   3. OnBlur: User leaves input -> if changed, write to DB and update current_edits
 *
 * Thread Safety:
 *   - Main thread calls OnFocus/OnChange/OnBlur
 *   - Command handlers (main thread) call GetEdits/ClearEdits
 *   - All access protected by mutex for future thread-safe reads
 *
 * Database Tables:
 *   - input_events: Transaction log of all input events
 *   - current_edits: Current state of modified fields per record
 */
class InputTracker {
public:
    InputTracker();
    ~InputTracker();

    // Initialize database (creates tables if needed)
    // db_path: Path to SQLite database file (creates data/ dir if needed)
    void Initialize(const std::string& db_path = "data/input_tracking.db");

    // Called by InputEventListener callbacks (main thread only)
    void OnFocus(const std::string& model, const std::string& record_id,
                 const std::string& field, const std::string& initial_value);
    void OnChange(const std::string& model, const std::string& record_id,
                  const std::string& field, const std::string& current_value);
    void OnBlur(const std::string& model, const std::string& record_id,
                const std::string& field, const std::string& final_value);

    // Query API (thread-safe, will be used by command handlers)
    // Returns map of field name -> current value for all modified fields
    PayloadMap GetEdits(const std::string& model, const std::string& record_id);

    // Clear all edits for a record (e.g., after save)
    void ClearEdits(const std::string& model, const std::string& record_id);

private:
    sqlite3* db_;
    std::mutex db_mutex_;  // Protect SQLite and cache access

    // In-memory cache for tracking active edits (fields currently being edited)
    struct EditState {
        std::string original_value;  // Value when focus occurred
        std::string current_value;   // Last known value from OnChange
        bool is_dirty;               // Has value changed from original?
        uint64_t focus_timestamp;    // When focus occurred (milliseconds since epoch)
    };

    // Key format: "model:record_id:field"
    std::unordered_map<std::string, EditState> active_edits_;

    // Helper to create cache key
    std::string MakeKey(const std::string& model, const std::string& record_id,
                        const std::string& field);

    // Create database schema
    bool CreateTables();

    // Get current time in milliseconds since epoch
    uint64_t GetTimestampMs();

    // Serialize value to JSON (extensible format)
    std::string SerializeValue(const std::string& value);

    // Deserialize JSON value
    std::string DeserializeValue(const std::string& json_str);
};
