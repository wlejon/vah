-- Database Example
-- Comprehensive demonstration of schema management, validation, and best practices

local schema_manager = require("schema_manager")
local db_tools = require("db_tools")

-- Example: Create a well-structured database for a project management system

function startup()
    print("=== Database Best Practices Example ===\n")

    -- 1. Open database
    local db, error = db.open("data/projects.db")
    if error ~= "" then
        print("ERROR: Failed to open database: " .. error)
        return
    end

    print("✓ Database opened: data/projects.db")

    -- 2. Define schema programmatically
    local schema = {
        tables = {
            -- Projects table
            {
                name = "projects",
                columns = {
                    {name = "id", type = "INTEGER PRIMARY KEY AUTOINCREMENT"},
                    {name = "name", type = "TEXT", not_null = true},
                    {name = "description", type = "TEXT"},
                    {name = "status", type = "TEXT", not_null = true, default = "active"},
                    {name = "created_at", type = "TEXT", not_null = true},
                    {name = "budget", type = "REAL", check = "budget >= 0"}
                },
                indexes = {
                    {columns = {"status"}},
                    {columns = {"created_at"}}
                }
            },

            -- Tasks table with foreign key
            {
                name = "tasks",
                columns = {
                    {name = "id", type = "INTEGER PRIMARY KEY AUTOINCREMENT"},
                    {name = "project_id", type = "INTEGER", not_null = true},
                    {name = "title", type = "TEXT", not_null = true},
                    {name = "description", type = "TEXT"},
                    {name = "priority", type = "INTEGER", default = 1},
                    {name = "completed", type = "INTEGER", default = 0},
                    {name = "due_date", type = "TEXT"}
                },
                foreign_keys = {
                    {
                        column = "project_id",
                        references_table = "projects",
                        references_column = "id",
                        on_delete = "CASCADE"
                    }
                },
                indexes = {
                    {columns = {"project_id"}},
                    {columns = {"completed"}},
                    {columns = {"priority", "due_date"}}
                }
            },

            -- Team members
            {
                name = "team_members",
                columns = {
                    {name = "id", type = "INTEGER PRIMARY KEY AUTOINCREMENT"},
                    {name = "name", type = "TEXT", not_null = true},
                    {name = "email", type = "TEXT", not_null = true, unique = true},
                    {name = "role", type = "TEXT"},
                    {name = "active", type = "INTEGER", default = 1}
                }
            },

            -- Project assignments (many-to-many)
            {
                name = "project_assignments",
                columns = {
                    {name = "project_id", type = "INTEGER", not_null = true},
                    {name = "member_id", type = "INTEGER", not_null = true}
                },
                primary_key = {"project_id", "member_id"},
                foreign_keys = {
                    {
                        column = "project_id",
                        references_table = "projects",
                        references_column = "id",
                        on_delete = "CASCADE"
                    },
                    {
                        column = "member_id",
                        references_table = "team_members",
                        references_column = "id",
                        on_delete = "CASCADE"
                    }
                }
            }
        }
    }

    print("\n✓ Schema defined with 4 tables:")
    schema_manager.print_schema(schema)

    -- 3. Create schema
    local success, create_error = schema_manager.create_schema(db, schema)
    if not success then
        print("\nERROR: Schema creation failed: " .. create_error)
        db:close()
        return
    end

    print("\n✓ Schema created successfully")

    -- 4. Validate schema
    local valid, validate_error = schema_manager.validate_schema(db, schema)
    if valid then
        print("✓ Schema validation passed")
    else
        print("⚠ Schema validation failed: " .. validate_error)
    end

    -- 5. Insert sample data using transactions
    print("\n--- Inserting sample data ---")

    local insert_success, insert_error = schema_manager.transaction(db, function(db)
        -- Insert projects
        db:query([[
            INSERT INTO projects (name, description, status, created_at, budget)
            VALUES (?, ?, ?, ?, ?)
        ]], "Website Redesign", "Complete overhaul of company website", "active", "2025-01-15", 50000.00)

        db:query([[
            INSERT INTO projects (name, description, status, created_at, budget)
            VALUES (?, ?, ?, ?, ?)
        ]], "Mobile App", "iOS and Android app development", "active", "2025-01-20", 120000.00)

        db:query([[
            INSERT INTO projects (name, description, status, created_at, budget)
            VALUES (?, ?, ?, ?, ?)
        ]], "Database Migration", "Move from MySQL to PostgreSQL", "planning", "2025-01-25", 30000.00)

        -- Insert team members
        db:query("INSERT INTO team_members (name, email, role) VALUES (?, ?, ?)",
            "Alice Johnson", "alice@example.com", "Project Manager")

        db:query("INSERT INTO team_members (name, email, role) VALUES (?, ?, ?)",
            "Bob Smith", "bob@example.com", "Lead Developer")

        db:query("INSERT INTO team_members (name, email, role) VALUES (?, ?, ?)",
            "Carol Davis", "carol@example.com", "Designer")

        -- Insert tasks for website project
        for i = 1, 5 do
            db:query([[
                INSERT INTO tasks (project_id, title, priority, completed)
                VALUES (?, ?, ?, ?)
            ]], 1, "Website Task " .. i, math.random(1, 3), math.random(0, 1))
        end

        return true
    end)

    if insert_success then
        print("✓ Sample data inserted in transaction")
    else
        print("ERROR: Insert failed: " .. (insert_error or "unknown"))
    end

    -- 6. Batch insert example (for large datasets)
    print("\n--- Batch insert demonstration ---")

    local large_dataset = {}
    for i = 1, 100 do
        table.insert(large_dataset, {
            project_id = math.random(1, 3),
            title = "Auto-generated task " .. i,
            priority = math.random(1, 3),
            completed = math.random(0, 1)
        })
    end

    local columns = {"project_id", "title", "priority", "completed"}
    local inserted_count, batch_error = schema_manager.batch_insert(db, "tasks", columns, large_dataset, 50)

    if batch_error == "" then
        print(string.format("✓ Batch inserted %d tasks", inserted_count))
    else
        print("ERROR: Batch insert failed: " .. batch_error)
    end

    -- 7. Analyze data quality
    print("\n--- Data quality analysis ---")

    local analysis, analysis_error = db_tools.analyze_table(db, "tasks")
    if analysis then
        db_tools.print_analysis(analysis)
    else
        print("ERROR: Analysis failed: " .. analysis_error)
    end

    -- 8. Find duplicates
    print("\n--- Checking for duplicate emails ---")

    local duplicates, dup_error = db_tools.find_duplicates(db, "team_members", {"email"})
    if duplicates then
        if #duplicates > 0 then
            print("⚠ Found duplicate emails:")
            for _, dup in ipairs(duplicates) do
                print(string.format("  %s (count: %d)", dup.email, dup.count))
            end
        else
            print("✓ No duplicate emails found")
        end
    else
        print("ERROR: " .. dup_error)
    end

    -- 9. Test query
    print("\n--- Testing complex query ---")

    local test_sql = [[
        SELECT p.name as project_name, COUNT(t.id) as task_count
        FROM projects p
        LEFT JOIN tasks t ON p.id = t.project_id
        GROUP BY p.id
        ORDER BY task_count DESC
    ]]

    local query_success, query_result = db_tools.test_query(db, test_sql)
    if query_success then
        print(string.format("✓ Query executed successfully (%d rows)", query_result.row_count))
        for _, row in ipairs(query_result.rows or {}) do
            print(string.format("  %s: %d tasks", row.project_name, row.task_count))
        end
    else
        print("ERROR: Query test failed: " .. query_result)
    end

    -- 10. Get database statistics
    print("\n--- Database statistics ---")

    local stats, stats_error = db_tools.get_table_stats(db)
    if stats then
        print("Table row counts:")
        for _, stat in ipairs(stats) do
            print(string.format("  %s: %d rows", stat.name, stat.row_count))
        end
    else
        print("ERROR: " .. stats_error)
    end

    -- 11. Get current schema (introspection)
    print("\n--- Schema introspection ---")

    local current_schema, schema_error = schema_manager.get_schema(db)
    if current_schema then
        print(string.format("✓ Database contains %d tables", #current_schema.tables))
    else
        print("ERROR: " .. schema_error)
    end

    -- 12. Vacuum database
    print("\n--- Optimizing database ---")

    local vacuum_success, vacuum_error = db_tools.vacuum(db)
    if vacuum_success then
        print("✓ Database optimized (VACUUM completed)")
    else
        print("ERROR: " .. vacuum_error)
    end

    -- 13. Close database
    db:close()
    print("\n✓ Database closed properly")

    print("\n=== Example completed successfully ===")
    print("\nBest practices demonstrated:")
    print("  ✓ Schema-first design")
    print("  ✓ Parameterized queries")
    print("  ✓ Transaction management")
    print("  ✓ Batch operations for performance")
    print("  ✓ Data validation and quality checks")
    print("  ✓ Foreign key constraints")
    print("  ✓ Indexes for query performance")
    print("  ✓ Schema introspection")
    print("  ✓ Proper resource cleanup")
end

function update(dt)
    -- This is a one-shot example
end

function shutdown()
    print("Database example shutting down")
end
