-- Initialize File Index Database
-- Creates the database schema for the filesystem indexer

print("Initializing file index database...")

-- Open/create database
local database, error = db.open("data/file_index.db")
if error ~= "" then
    print("ERROR: Failed to open database: " .. error)
    return
end

print("Database opened successfully")

-- Read and execute schema
local schema_sql, read_error = fs.read_file("data/file_index_schema.sql")
if read_error ~= "" then
    print("ERROR: Failed to read schema file: " .. read_error)
    database:close()
    return
end

print("Executing schema...")
local success, exec_error = database:execute(schema_sql)
if not success then
    print("ERROR: Failed to execute schema: " .. exec_error)
    database:close()
    return
end

print("Schema created successfully")

-- Verify the tables
local tables_result, tables_error = database:query([[
    SELECT name FROM sqlite_master
    WHERE type='table'
    ORDER BY name
]])

if tables_error ~= "" then
    print("ERROR: Failed to verify tables: " .. tables_error)
else
    if tables_result and #tables_result > 0 then
        print("\nCreated tables:")
        for _, row in ipairs(tables_result) do
            print("  - " .. row.name)
        end
    end
end

database:close()
print("\nFile index database initialized successfully!")
