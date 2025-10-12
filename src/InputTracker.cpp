#include "InputTracker.h"
#include "Logger.h"
#include <nlohmann/json.hpp>
#include <chrono>
#include <filesystem>

using json = nlohmann::json;

InputTracker::InputTracker() : db_(nullptr) {
}

InputTracker::~InputTracker() {
    if (db_) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

void InputTracker::Initialize(const std::string& db_path) {
    std::lock_guard<std::mutex> lock(db_mutex_);

    // Create data directory if it doesn't exist
    std::filesystem::path path(db_path);
    std::filesystem::path dir = path.parent_path();
    if (!dir.empty() && !std::filesystem::exists(dir)) {
        std::filesystem::create_directories(dir);
        LOG_INFO("Created directory: {}", dir.string());
    }

    // Open database
    int rc = sqlite3_open(db_path.c_str(), &db_);
    if (rc != SQLITE_OK) {
        LOG_ERROR("Failed to open InputTracker database at {}: {}", db_path, sqlite3_errmsg(db_));
        sqlite3_close(db_);
        db_ = nullptr;
        return;
    }

    LOG_INFO("Opened InputTracker database: {}", db_path);

    // Create tables
    if (!CreateTables()) {
        LOG_ERROR("Failed to create InputTracker tables");
        sqlite3_close(db_);
        db_ = nullptr;
        return;
    }

    LOG_INFO("InputTracker initialized successfully");
}

bool InputTracker::CreateTables() {
    // Note: db_mutex_ should already be locked by caller

    const char* sql = R"(
        CREATE TABLE IF NOT EXISTS input_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            model TEXT NOT NULL,
            record_id TEXT NOT NULL,
            field TEXT NOT NULL,
            value TEXT,
            session_id TEXT
        );

        CREATE TABLE IF NOT EXISTS current_edits (
            model TEXT NOT NULL,
            record_id TEXT NOT NULL,
            field TEXT NOT NULL,
            original_value TEXT,
            current_value TEXT,
            modified_at INTEGER,
            PRIMARY KEY (model, record_id, field)
        );

        CREATE INDEX IF NOT EXISTS idx_events_lookup ON input_events(model, record_id, field);
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON input_events(timestamp);
    )";

    char* error_msg = nullptr;
    int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &error_msg);

    if (rc != SQLITE_OK) {
        std::string error = error_msg ? error_msg : "Unknown error";
        sqlite3_free(error_msg);
        LOG_ERROR("Failed to create tables: {}", error);
        return false;
    }

    LOG_DEBUG("InputTracker tables created/verified");
    return true;
}

uint64_t InputTracker::GetTimestampMs() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

std::string InputTracker::SerializeValue(const std::string& value) {
    // Create extensible JSON format for values
    // Start simple with text type, can expand to checkbox, file refs, etc.
    json j;
    j["type"] = "text";
    j["value"] = value;
    return j.dump();
}

std::string InputTracker::DeserializeValue(const std::string& json_str) {
    try {
        json j = json::parse(json_str);
        if (j.contains("value")) {
            return j["value"].get<std::string>();
        }
        return "";
    }
    catch (const std::exception& e) {
        LOG_ERROR("Failed to deserialize value JSON: {}", e.what());
        return "";
    }
}

std::string InputTracker::MakeKey(const std::string& model, const std::string& record_id,
                                   const std::string& field) {
    return model + ":" + record_id + ":" + field;
}

void InputTracker::OnFocus(const std::string& model, const std::string& record_id,
                           const std::string& field, const std::string& initial_value) {
    std::lock_guard<std::mutex> lock(db_mutex_);

    std::string key = MakeKey(model, record_id, field);
    uint64_t timestamp = GetTimestampMs();

    // Store in cache
    EditState state;
    state.original_value = initial_value;
    state.current_value = initial_value;
    state.is_dirty = false;
    state.focus_timestamp = timestamp;

    active_edits_[key] = state;

    LOG_DEBUG("InputTracker: FOCUS on {} = '{}'", key, initial_value);

    // Record focus event in database
    if (!db_) return;

    std::string value_json = SerializeValue(initial_value);
    const char* sql = "INSERT INTO input_events (timestamp, event_type, model, record_id, field, value) "
                      "VALUES (?, 'focus', ?, ?, ?, ?)";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        LOG_ERROR("Failed to prepare focus insert: {}", sqlite3_errmsg(db_));
        return;
    }

    sqlite3_bind_int64(stmt, 1, timestamp);
    sqlite3_bind_text(stmt, 2, model.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, record_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, field.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, value_json.c_str(), -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        LOG_ERROR("Failed to insert focus event: {}", sqlite3_errmsg(db_));
    }

    sqlite3_finalize(stmt);
}

void InputTracker::OnChange(const std::string& model, const std::string& record_id,
                            const std::string& field, const std::string& current_value) {
    std::lock_guard<std::mutex> lock(db_mutex_);

    std::string key = MakeKey(model, record_id, field);

    // Update cache only - no DB write for change events
    auto it = active_edits_.find(key);
    if (it != active_edits_.end()) {
        it->second.current_value = current_value;
        it->second.is_dirty = (current_value != it->second.original_value);

        LOG_DEBUG("InputTracker: CHANGE on {} = '{}' (dirty: {})",
                  key, current_value, it->second.is_dirty);
    } else {
        LOG_WARN("InputTracker: CHANGE on {} without prior FOCUS - ignoring", key);
    }
}

void InputTracker::OnBlur(const std::string& model, const std::string& record_id,
                          const std::string& field, const std::string& final_value) {
    std::lock_guard<std::mutex> lock(db_mutex_);

    std::string key = MakeKey(model, record_id, field);
    uint64_t timestamp = GetTimestampMs();

    // Check cache
    auto it = active_edits_.find(key);
    if (it == active_edits_.end()) {
        LOG_WARN("InputTracker: BLUR on {} without prior FOCUS - ignoring", key);
        return;
    }

    EditState& state = it->second;
    bool value_changed = (final_value != state.original_value);

    LOG_DEBUG("InputTracker: BLUR on {} = '{}' (changed: {})",
              key, final_value, value_changed);

    if (!db_) {
        // Just remove from cache if DB not available
        active_edits_.erase(it);
        return;
    }

    // Always record blur event
    std::string value_json = SerializeValue(final_value);
    const char* blur_sql = "INSERT INTO input_events (timestamp, event_type, model, record_id, field, value) "
                           "VALUES (?, 'blur', ?, ?, ?, ?)";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, blur_sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        LOG_ERROR("Failed to prepare blur insert: {}", sqlite3_errmsg(db_));
        active_edits_.erase(it);
        return;
    }

    sqlite3_bind_int64(stmt, 1, timestamp);
    sqlite3_bind_text(stmt, 2, model.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, record_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, field.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, value_json.c_str(), -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        LOG_ERROR("Failed to insert blur event: {}", sqlite3_errmsg(db_));
    }
    sqlite3_finalize(stmt);

    // If value changed, update current_edits table
    if (value_changed) {
        std::string original_json = SerializeValue(state.original_value);

        const char* upsert_sql = "INSERT INTO current_edits (model, record_id, field, original_value, current_value, modified_at) "
                                 "VALUES (?, ?, ?, ?, ?, ?) "
                                 "ON CONFLICT(model, record_id, field) DO UPDATE SET "
                                 "current_value = excluded.current_value, "
                                 "modified_at = excluded.modified_at";

        stmt = nullptr;
        rc = sqlite3_prepare_v2(db_, upsert_sql, -1, &stmt, nullptr);
        if (rc != SQLITE_OK) {
            LOG_ERROR("Failed to prepare current_edits upsert: {}", sqlite3_errmsg(db_));
            active_edits_.erase(it);
            return;
        }

        sqlite3_bind_text(stmt, 1, model.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, record_id.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, field.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, original_json.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, value_json.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 6, timestamp);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            LOG_ERROR("Failed to upsert current_edits: {}", sqlite3_errmsg(db_));
        } else {
            LOG_DEBUG("Updated current_edits for {}", key);
        }
        sqlite3_finalize(stmt);
    }

    // Remove from active edits cache
    active_edits_.erase(it);
}

PayloadMap InputTracker::GetEdits(const std::string& model, const std::string& record_id) {
    std::lock_guard<std::mutex> lock(db_mutex_);

    PayloadMap result;

    if (!db_) return result;

    // Query current_edits table for this model/record
    const char* sql = "SELECT field, current_value FROM current_edits WHERE model = ? AND record_id = ?";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        LOG_ERROR("Failed to prepare GetEdits query: {}", sqlite3_errmsg(db_));
        return result;
    }

    sqlite3_bind_text(stmt, 1, model.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, record_id.c_str(), -1, SQLITE_TRANSIENT);

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        const char* field = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        const char* value_json = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));

        if (field && value_json) {
            std::string value = DeserializeValue(value_json);
            result[field] = value;
        }
    }

    if (rc != SQLITE_DONE) {
        LOG_ERROR("Error reading GetEdits results: {}", sqlite3_errmsg(db_));
    }

    sqlite3_finalize(stmt);

    LOG_DEBUG("GetEdits({}, {}) returned {} fields", model, record_id, result.size());
    return result;
}

void InputTracker::ClearEdits(const std::string& model, const std::string& record_id) {
    std::lock_guard<std::mutex> lock(db_mutex_);

    if (!db_) return;

    // Delete from current_edits table
    const char* sql = "DELETE FROM current_edits WHERE model = ? AND record_id = ?";

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
        LOG_ERROR("Failed to prepare ClearEdits: {}", sqlite3_errmsg(db_));
        return;
    }

    sqlite3_bind_text(stmt, 1, model.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, record_id.c_str(), -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        LOG_ERROR("Failed to clear edits: {}", sqlite3_errmsg(db_));
    } else {
        int deleted = sqlite3_changes(db_);
        LOG_DEBUG("ClearEdits({}, {}) deleted {} records", model, record_id, deleted);
    }

    sqlite3_finalize(stmt);
}
