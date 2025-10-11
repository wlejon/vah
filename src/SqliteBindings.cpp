#include "SqliteBindings.h"
#include "Logger.h"
#include <sqlite3.h>
#include <memory>
#include <vector>
#include <string>

namespace SqliteBindings {

// Database handle wrapper for RAII
class Database {
public:
    Database() : db_(nullptr) {}

    ~Database() {
        Close();
    }

    std::tuple<bool, std::string> Open(const std::string& path) {
        if (db_) {
            Close();
        }

        int rc = sqlite3_open(path.c_str(), &db_);
        if (rc != SQLITE_OK) {
            std::string error = sqlite3_errmsg(db_);
            sqlite3_close(db_);
            db_ = nullptr;
            return {false, "Failed to open database: " + error};
        }

        return {true, ""};
    }

    void Close() {
        if (db_) {
            sqlite3_close(db_);
            db_ = nullptr;
        }
    }

    std::tuple<bool, std::string> Execute(const std::string& sql) {
        if (!db_) {
            return {false, "Database not open"};
        }

        char* error_msg = nullptr;
        int rc = sqlite3_exec(db_, sql.c_str(), nullptr, nullptr, &error_msg);

        if (rc != SQLITE_OK) {
            std::string error = error_msg ? error_msg : "Unknown error";
            sqlite3_free(error_msg);
            return {false, "SQL execution error: " + error};
        }

        return {true, ""};
    }

    std::tuple<sol::object, std::string> Query(sol::this_state s, const std::string& sql) {
        sol::state_view lua(s);

        if (!db_) {
            return {sol::nil, "Database not open"};
        }

        sqlite3_stmt* stmt = nullptr;
        int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr);

        if (rc != SQLITE_OK) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "SQL prepare error: " + error};
        }

        // Get column info
        int col_count = sqlite3_column_count(stmt);
        std::vector<std::string> col_names;
        for (int i = 0; i < col_count; i++) {
            col_names.push_back(sqlite3_column_name(stmt, i));
        }

        // Fetch rows
        auto results = lua.create_table();
        int row_index = 1;

        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            auto row = lua.create_table();

            for (int i = 0; i < col_count; i++) {
                int col_type = sqlite3_column_type(stmt, i);

                switch (col_type) {
                    case SQLITE_INTEGER:
                        row[col_names[i]] = sqlite3_column_int64(stmt, i);
                        break;
                    case SQLITE_FLOAT:
                        row[col_names[i]] = sqlite3_column_double(stmt, i);
                        break;
                    case SQLITE_TEXT:
                        row[col_names[i]] = std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, i)));
                        break;
                    case SQLITE_NULL:
                        row[col_names[i]] = sol::nil;
                        break;
                    case SQLITE_BLOB:
                        // For now, skip blobs or convert to hex string
                        row[col_names[i]] = sol::nil;
                        break;
                }
            }

            results[row_index++] = row;
        }

        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "SQL execution error: " + error};
        }

        return {results, ""};
    }

    std::tuple<sol::object, std::string> QuerySingle(sol::this_state s, const std::string& sql) {
        sol::state_view lua(s);

        if (!db_) {
            return {sol::nil, "Database not open"};
        }

        sqlite3_stmt* stmt = nullptr;
        int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr);

        if (rc != SQLITE_OK) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "SQL prepare error: " + error};
        }

        // Get column info
        int col_count = sqlite3_column_count(stmt);
        std::vector<std::string> col_names;
        for (int i = 0; i < col_count; i++) {
            col_names.push_back(sqlite3_column_name(stmt, i));
        }

        // Fetch first row only
        rc = sqlite3_step(stmt);

        if (rc == SQLITE_ROW) {
            auto row = lua.create_table();

            for (int i = 0; i < col_count; i++) {
                int col_type = sqlite3_column_type(stmt, i);

                switch (col_type) {
                    case SQLITE_INTEGER:
                        row[col_names[i]] = sqlite3_column_int64(stmt, i);
                        break;
                    case SQLITE_FLOAT:
                        row[col_names[i]] = sqlite3_column_double(stmt, i);
                        break;
                    case SQLITE_TEXT:
                        row[col_names[i]] = std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, i)));
                        break;
                    case SQLITE_NULL:
                        row[col_names[i]] = sol::nil;
                        break;
                    case SQLITE_BLOB:
                        row[col_names[i]] = sol::nil;
                        break;
                }
            }

            sqlite3_finalize(stmt);
            return {row, ""};
        }
        else if (rc == SQLITE_DONE) {
            sqlite3_finalize(stmt);
            return {sol::nil, ""};  // No rows, but not an error
        }
        else {
            std::string error = sqlite3_errmsg(db_);
            sqlite3_finalize(stmt);
            return {sol::nil, "SQL execution error: " + error};
        }
    }

    int64_t LastInsertRowId() {
        if (!db_) return 0;
        return sqlite3_last_insert_rowid(db_);
    }

    int ChangesCount() {
        if (!db_) return 0;
        return sqlite3_changes(db_);
    }

    bool IsOpen() const {
        return db_ != nullptr;
    }

private:
    sqlite3* db_;
};

void SetupBindings(sol::state& lua) {
    // Register Database class
    lua.new_usertype<Database>("Database",
        sol::constructors<Database()>(),

        "open", &Database::Open,
        "close", &Database::Close,
        "execute", &Database::Execute,
        "query", &Database::Query,
        "query_single", &Database::QuerySingle,
        "last_insert_rowid", &Database::LastInsertRowId,
        "changes_count", &Database::ChangesCount,
        "is_open", &Database::IsOpen
    );

    // Create db namespace with constructor
    auto db_table = lua.create_table();
    db_table["open"] = [](const std::string& path) -> std::tuple<std::shared_ptr<Database>, std::string> {
        auto db = std::make_shared<Database>();
        auto [success, error] = db->Open(path);
        if (!success) {
            return {nullptr, error};
        }
        return {db, ""};
    };

    lua["db"] = db_table;

    LOG_INFO("SQLite bindings initialized");
}

} // namespace SqliteBindings
