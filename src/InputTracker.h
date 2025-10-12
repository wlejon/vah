#pragma once

#include <sqlite3.h>
#include <string>
#include <unordered_map>
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
 * Threading Model:
 *   - MAIN THREAD ONLY - no synchronization needed
 *   - OnFocus/OnChange/OnBlur called from RmlUi event callbacks (main thread)
 *   - GetEdits/ClearEdits called from command queue processor (main thread)
 *   - Lua threads access via Commands::GetInputEdits/ClearInputEdits
 *   - Single sqlite3 handle accessed from single thread only
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
    void Initialize(const std::string& db_path = "data/input_tracking.db");

    // Event callbacks from InputEventListener (main thread)
    void OnFocus(const std::string& model, const std::string& record_id,
                 const std::string& field, const std::string& initial_value);
    void OnChange(const std::string& model, const std::string& record_id,
                  const std::string& field, const std::string& current_value);
    void OnBlur(const std::string& model, const std::string& record_id,
                const std::string& field, const std::string& final_value);

    // Query current edits for a record (main thread via command handlers)
    PayloadMap GetEdits(const std::string& model, const std::string& record_id);

    // Clear all edits for a record (main thread via command handlers)
    void ClearEdits(const std::string& model, const std::string& record_id);

private:
    sqlite3* db_;

    struct EditState {
        std::string original_value;
        std::string current_value;
        bool is_dirty;
        uint64_t focus_timestamp;
    };

    std::unordered_map<std::string, EditState> active_edits_;

    std::string MakeKey(const std::string& model, const std::string& record_id,
                        const std::string& field);
    bool CreateTables();
    uint64_t GetTimestampMs();
    std::string SerializeValue(const std::string& value);
    std::string DeserializeValue(const std::string& json_str);
};
