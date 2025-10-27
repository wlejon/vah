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

    std::tuple<sol::object, std::string> Query(sol::this_state s, const std::string& sql, sol::variadic_args va) {
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

        // Bind parameters if provided
        int param_index = 1;
        for (const auto& arg : va) {
            sol::type arg_type = arg.get_type();

            switch (arg_type) {
                case sol::type::number: {
                    // Try integer first, fall back to double
                    if (arg.is<int64_t>()) {
                        sqlite3_bind_int64(stmt, param_index, arg.as<int64_t>());
                    } else {
                        sqlite3_bind_double(stmt, param_index, arg.as<double>());
                    }
                    break;
                }
                case sol::type::string: {
                    std::string str = arg.as<std::string>();
                    sqlite3_bind_text(stmt, param_index, str.c_str(), -1, SQLITE_TRANSIENT);
                    break;
                }
                case sol::type::boolean: {
                    sqlite3_bind_int(stmt, param_index, arg.as<bool>() ? 1 : 0);
                    break;
                }
                case sol::type::nil: {
                    sqlite3_bind_null(stmt, param_index);
                    break;
                }
                default: {
                    sqlite3_finalize(stmt);
                    return {sol::nil, "Unsupported parameter type at index " + std::to_string(param_index)};
                }
            }

            param_index++;
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

    std::tuple<sol::object, std::string> QuerySingle(sol::this_state s, const std::string& sql, sol::variadic_args va) {
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

        // Bind parameters if provided
        int param_index = 1;
        for (const auto& arg : va) {
            sol::type arg_type = arg.get_type();

            switch (arg_type) {
                case sol::type::number: {
                    if (arg.is<int64_t>()) {
                        sqlite3_bind_int64(stmt, param_index, arg.as<int64_t>());
                    } else {
                        sqlite3_bind_double(stmt, param_index, arg.as<double>());
                    }
                    break;
                }
                case sol::type::string: {
                    std::string str = arg.as<std::string>();
                    sqlite3_bind_text(stmt, param_index, str.c_str(), -1, SQLITE_TRANSIENT);
                    break;
                }
                case sol::type::boolean: {
                    sqlite3_bind_int(stmt, param_index, arg.as<bool>() ? 1 : 0);
                    break;
                }
                case sol::type::nil: {
                    sqlite3_bind_null(stmt, param_index);
                    break;
                }
                default: {
                    sqlite3_finalize(stmt);
                    return {sol::nil, "Unsupported parameter type at index " + std::to_string(param_index)};
                }
            }

            param_index++;
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

    // Transaction support
    std::tuple<bool, std::string> BeginTransaction() {
        if (!db_) {
            return {false, "Database not open"};
        }

        char* error_msg = nullptr;
        int rc = sqlite3_exec(db_, "BEGIN TRANSACTION", nullptr, nullptr, &error_msg);

        if (rc != SQLITE_OK) {
            std::string error = error_msg ? error_msg : "Unknown error";
            sqlite3_free(error_msg);
            return {false, "Failed to begin transaction: " + error};
        }

        return {true, ""};
    }

    std::tuple<bool, std::string> Commit() {
        if (!db_) {
            return {false, "Database not open"};
        }

        char* error_msg = nullptr;
        int rc = sqlite3_exec(db_, "COMMIT", nullptr, nullptr, &error_msg);

        if (rc != SQLITE_OK) {
            std::string error = error_msg ? error_msg : "Unknown error";
            sqlite3_free(error_msg);
            return {false, "Failed to commit transaction: " + error};
        }

        return {true, ""};
    }

    std::tuple<bool, std::string> Rollback() {
        if (!db_) {
            return {false, "Database not open"};
        }

        char* error_msg = nullptr;
        int rc = sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, &error_msg);

        if (rc != SQLITE_OK) {
            std::string error = error_msg ? error_msg : "Unknown error";
            sqlite3_free(error_msg);
            return {false, "Failed to rollback transaction: " + error};
        }

        return {true, ""};
    }

    // Batch insert for performance
    std::tuple<int, std::string> BatchInsert(const std::string& table, sol::table columns, sol::table rows) {
        if (!db_) {
            return {0, "Database not open"};
        }

        // Build column list
        std::vector<std::string> col_names;
        for (const auto& [key, value] : columns) {
            if (value.is<std::string>()) {
                col_names.push_back(value.as<std::string>());
            }
        }

        if (col_names.empty()) {
            return {0, "No columns specified"};
        }

        // Build INSERT statement
        std::string sql = "INSERT INTO " + table + " (";
        for (size_t i = 0; i < col_names.size(); i++) {
            if (i > 0) sql += ", ";
            sql += col_names[i];
        }
        sql += ") VALUES (";
        for (size_t i = 0; i < col_names.size(); i++) {
            if (i > 0) sql += ", ";
            sql += "?";
        }
        sql += ")";

        // Prepare statement
        sqlite3_stmt* stmt = nullptr;
        int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr);

        if (rc != SQLITE_OK) {
            std::string error = sqlite3_errmsg(db_);
            return {0, "Failed to prepare insert: " + error};
        }

        // Insert rows
        int inserted_count = 0;

        for (const auto& [row_key, row_value] : rows) {
            if (!row_value.is<sol::table>()) {
                continue;
            }

            sol::table row = row_value.as<sol::table>();

            // Bind values
            for (size_t i = 0; i < col_names.size(); i++) {
                sol::object value = row[col_names[i]];
                int param_index = static_cast<int>(i) + 1;

                if (value.is<int64_t>()) {
                    sqlite3_bind_int64(stmt, param_index, value.as<int64_t>());
                } else if (value.is<int>()) {
                    sqlite3_bind_int64(stmt, param_index, value.as<int>());
                } else if (value.is<double>()) {
                    sqlite3_bind_double(stmt, param_index, value.as<double>());
                } else if (value.is<std::string>()) {
                    std::string str = value.as<std::string>();
                    sqlite3_bind_text(stmt, param_index, str.c_str(), -1, SQLITE_TRANSIENT);
                } else if (value.is<bool>()) {
                    sqlite3_bind_int(stmt, param_index, value.as<bool>() ? 1 : 0);
                } else {
                    sqlite3_bind_null(stmt, param_index);
                }
            }

            // Execute
            rc = sqlite3_step(stmt);

            if (rc != SQLITE_DONE) {
                std::string error = sqlite3_errmsg(db_);
                sqlite3_finalize(stmt);
                return {inserted_count, "Insert failed at row " + std::to_string(inserted_count + 1) + ": " + error};
            }

            inserted_count++;
            sqlite3_reset(stmt);
        }

        sqlite3_finalize(stmt);
        return {inserted_count, ""};
    }

    // Get table info for introspection
    std::tuple<sol::object, std::string> GetTableInfo(sol::this_state s, const std::string& table_name) {
        sol::state_view lua(s);

        if (!db_) {
            return {sol::nil, "Database not open"};
        }

        // Execute PRAGMA directly
        std::string sql = "PRAGMA table_info(" + table_name + ")";

        sqlite3_stmt* stmt = nullptr;
        int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr);

        if (rc != SQLITE_OK) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "Failed to get table info: " + error};
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
                    default:
                        row[col_names[i]] = sol::nil;
                        break;
                }
            }

            results[row_index++] = row;
        }

        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "Failed to read table info: " + error};
        }

        return {results, ""};
    }

    // Get list of tables
    std::tuple<sol::object, std::string> GetTables(sol::this_state s) {
        sol::state_view lua(s);

        if (!db_) {
            return {sol::nil, "Database not open"};
        }

        std::string sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name";

        sqlite3_stmt* stmt = nullptr;
        int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr);

        if (rc != SQLITE_OK) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "Failed to get tables: " + error};
        }

        // Fetch rows
        auto results = lua.create_table();
        int row_index = 1;

        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            auto row = lua.create_table();
            row["name"] = std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0)));
            results[row_index++] = row;
        }

        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE) {
            std::string error = sqlite3_errmsg(db_);
            return {sol::nil, "Failed to read tables: " + error};
        }

        return {results, ""};
    }

    // Check if table exists
    bool TableExists(const std::string& table_name) {
        if (!db_) return false;

        sqlite3_stmt* stmt = nullptr;
        std::string sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?";

        int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr);
        if (rc != SQLITE_OK) {
            return false;
        }

        sqlite3_bind_text(stmt, 1, table_name.c_str(), -1, SQLITE_TRANSIENT);
        rc = sqlite3_step(stmt);

        bool exists = (rc == SQLITE_ROW);
        sqlite3_finalize(stmt);

        return exists;
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
        "is_open", &Database::IsOpen,

        // Transaction support
        "begin_transaction", &Database::BeginTransaction,
        "commit", &Database::Commit,
        "rollback", &Database::Rollback,

        // Batch operations
        "batch_insert", &Database::BatchInsert,

        // Introspection
        "get_table_info", &Database::GetTableInfo,
        "get_tables", &Database::GetTables,
        "table_exists", &Database::TableExists
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
}

} // namespace SqliteBindings
