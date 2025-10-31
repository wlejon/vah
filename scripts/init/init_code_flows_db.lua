-- Initialize Code Flows Database
-- This script creates and populates the code flows documentation database

print("Initializing code flows database...")

-- Open/create database
local database, error = db.open("data/code_flows.db")
if error ~= "" then
    print("ERROR: Failed to open database: " .. error)
    return
end

print("Database opened successfully")

-- Read and execute schema
local schema_sql, read_error = fs.read_file("data/code_flows_schema.sql")
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

-- Read and execute tetris population script
local tetris_sql, tetris_read_error = fs.read_file("data/populate_tetris_flow.sql")
if tetris_read_error ~= "" then
    print("ERROR: Failed to read tetris population file: " .. tetris_read_error)
    database:close()
    return
end

print("Populating tetris flow...")
local tetris_success, tetris_exec_error = database:execute(tetris_sql)
if not tetris_success then
    print("ERROR: Failed to populate tetris flow: " .. tetris_exec_error)
    database:close()
    return
end

print("Tetris flow populated successfully")

-- Verify the data
local count_result, count_error = database:query([[
    SELECT
        (SELECT COUNT(*) FROM flows) as flows,
        (SELECT COUNT(*) FROM node_types) as node_types,
        (SELECT COUNT(*) FROM nodes) as nodes,
        (SELECT COUNT(*) FROM connections) as connections
]])

if count_error ~= "" then
    print("ERROR: Failed to verify data: " .. count_error)
else
    if count_result and #count_result > 0 then
        local stats = count_result[1]
        print("\nDatabase statistics:")
        print("  Flows: " .. stats.flows)
        print("  Node Types: " .. stats.node_types)
        print("  Nodes: " .. stats.nodes)
        print("  Connections: " .. stats.connections)
    end
end

database:close()
print("\nCode flows database initialized successfully!")
