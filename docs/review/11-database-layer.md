# Code Review: Database & Schema Layer (Lua)

## Component Overview

The Database & Schema Layer provides SQLite integration for the vah application, implementing comprehensive database operations, schema management, migrations, and data introspection. The layer consists of seven Lua modules that together form a complete database abstraction and tooling ecosystem.

**Primary Functions:**
- SQLite database operations and persistence
- Schema definition, creation, and validation
- Database introspection and analysis
- Data quality validation and integrity checking
- Workflow and node type management
- Code flow visualization with database backing
- Interactive database demonstration

## Files Reviewed

| File | Lines | Purpose |
|------|-------|---------|
| `workflow_db.lua` | 672 | Workflow node type management and persistence |
| `schema_manager.lua` | 463 | Schema creation, validation, and management |
| `schema_executor.lua` | 397 | Schema execution and validation engine |
| `db_inspector.lua` | 421 | Database introspection and query analysis |
| `db_tools.lua` | 425 | Data validation and quality utilities |
| `code_flow_viewer.lua` | 657 | Code flow visualization with DB backend |
| `sqlite_demo.lua` | 223 | Interactive database demo application |
| **TOTAL** | **3,258** | |

## Architecture & Design

### Schema Management System

The schema layer uses a declarative table definition approach:

```lua
schema = {
  tables = {
    {
      name = "table_name",
      columns = {
        {name = "col", type = "INTEGER", not_null = true, default = value}
      },
      indexes = {...},
      foreign_keys = {...}
    }
  }
}
```

**Strengths:**
- Clean separation between schema definition and execution
- Type normalization system (TYPE_MAP) for SQLite compatibility
- Support for constraints (NOT NULL, UNIQUE, CHECK, DEFAULT)
- Automatic transaction management
- Comprehensive validation before execution

**Design Pattern:** The schema system follows a builder pattern with validation stages, separating concerns between definition, validation, and execution.

### Database Operations

Three distinct operation patterns are used:

1. **Direct SQL (workflow_db.lua, sqlite_demo.lua):**
   - String formatting for query construction
   - Manual escaping for single quotes
   - Both safe (parameterized) and unsafe (formatted) queries

2. **Schema-Driven (schema_manager.lua, schema_executor.lua):**
   - Programmatic SQL generation
   - Type-safe column definitions
   - Transactional schema creation

3. **Introspection (db_inspector.lua, db_tools.lua):**
   - PRAGMA queries for metadata
   - sqlite_master queries for schema info
   - Statistical analysis of data

## Code Quality Assessment

### Strengths

1. **Comprehensive Schema System**
   - Well-designed type mapping system
   - Support for all major SQL constraints
   - Automatic index creation
   - Foreign key relationship management

2. **Transaction Safety (schema_manager.lua:162-208)**
   - Proper BEGIN/COMMIT/ROLLBACK pattern
   - Automatic rollback on errors
   - Transaction wrapper function for reusability

3. **Rich Introspection (db_inspector.lua)**
   - Detailed schema information retrieval
   - Column statistics (nulls, distinct values)
   - Data sampling for preview
   - Query execution timing
   - Visualization suggestions

4. **Data Quality Tools (db_tools.lua)**
   - Pre-import validation
   - Duplicate detection
   - Referential integrity checks
   - Table statistics and analysis

5. **Parameterized Queries (sqlite_demo.lua:77-85)**
   - Proper use of parameterized queries for user input
   - SQL injection prevention in critical paths

### Issues & Concerns

#### Critical Issues

**C1. SQL Injection Vulnerabilities (workflow_db.lua)**

Multiple instances of unsafe string formatting for SQL construction:

```lua
-- Line 193-196: Unsafe string interpolation
local sql = string.format([[
    INSERT INTO node_types (name, color_r, color_g, color_b, color_a)
    VALUES ('%s', %d, %d, %d, %d)
]], escaped_name, r, g, b, a or 255)
```

**Problem:** While single quotes are escaped, this pattern is fragile and error-prone. Numeric parameters are inserted directly without validation.

**Locations:**
- workflow_db.lua:193-196 (create_node_type)
- workflow_db.lua:217-220 (add_port)
- workflow_db.lua:302-306 (update_node_type)
- workflow_db.lua:324 (delete_node_type)
- workflow_db.lua:375-378 (create_workflow)
- workflow_db.lua:419-423 (update_workflow)
- workflow_db.lua:465-468 (save_workflow nodes)
- workflow_db.lua:479-482 (save_workflow connections)

**Impact:** Potential SQL injection if user-controlled data contains malicious SQL, especially in numeric fields or if escaping fails.

**Recommendation:** Use parameterized queries throughout:
```lua
local sql = "INSERT INTO node_types (name, color_r, color_g, color_b, color_a) VALUES (?, ?, ?, ?, ?)"
local success, error = db_handle:query(sql, name, r, g, b, a or 255)
```

**C2. Missing Input Validation**

No validation of numeric ranges or types before database insertion:

- Color values (r, g, b, a) not validated to be 0-255 range
- Node IDs, type IDs not validated as positive integers
- Coordinates (x, y) not validated
- Port order not validated

**Recommendation:** Add input validation layer before database operations.

**C3. Resource Leaks (code_flow_viewer.lua)**

Database connection management issues:

```lua
-- Line 584: Opens database but only closes on shutdown
local db, db_error = db.open("data/code_flows.db")
```

**Problem:** If startup() returns early due to errors after opening the database, the connection may not be closed properly.

**Recommendation:** Use error handling with proper cleanup:
```lua
local db, db_error = db.open("data/code_flows.db")
if db_error ~= "" then
    if db then db:close() end
    return
end
```

#### Major Issues

**M1. Inconsistent Error Handling**

Different error handling patterns across modules:

```lua
-- Pattern 1: Returns false, error_msg (workflow_db.lua)
if not success then
    return false
end

-- Pattern 2: Returns nil, error_msg (schema_manager.lua)
if error ~= "" then
    return nil, "Failed to get tables: " .. error
end

-- Pattern 3: Returns success, result (db_tools.lua)
if error ~= "" then
    return false, error
end
```

**Recommendation:** Standardize on one pattern, preferably: `(success: boolean, result: any | error_msg: string)`

**M2. Dual Database Handle Pattern (workflow_db.lua:6-8)**

```lua
M.db_handle = nil
local db_handle = nil
```

**Problem:** Maintains two references to the same database handle, creating confusion about which to use and potential for desynchronization.

**Recommendation:** Use only the module variable `M.db_handle` and access it directly.

**M3. Missing Index Optimization**

Critical queries lack indexes:

- workflow_db.lua:270-275: Query on `node_type_id` without index
- workflow_db.lua:617-622: Query on `workflow_id` without index
- code_flow_viewer.lua:228-235: JOIN query without indexes on foreign keys

**Recommendation:** Add indexes:
```sql
CREATE INDEX idx_node_type_ports_type_id ON node_type_ports(node_type_id);
CREATE INDEX idx_workflow_nodes_workflow_id ON workflow_nodes(workflow_id);
CREATE INDEX idx_workflow_connections_workflow_id ON workflow_connections(workflow_id);
CREATE INDEX idx_nodes_flow_id ON nodes(flow_id);
CREATE INDEX idx_connections_flow_id ON connections(flow_id);
```

**M4. Transaction Management Inconsistency**

Some multi-statement operations lack transactions:

- workflow_db.lua:459-489 (save_workflow): DELETE + multiple INSERTs without transaction
- db_tools.lua:248-280 (get_table_stats): Multiple queries without transaction

**Recommendation:** Wrap multi-statement operations in transactions for consistency and performance.

**M5. No Schema Versioning or Migration System**

All schemas use `CREATE TABLE IF NOT EXISTS` without version tracking:

- No way to detect schema changes
- No migration path for schema updates
- No rollback capability

**Recommendation:** Implement schema versioning:
```sql
CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**M6. Hard-Coded SQL in Multiple Locations**

Code flow schema is defined externally (code_flows_schema.sql) but executed as one large string:

- code_flow_viewer.lua:499-504: Reads external SQL file
- No validation of SQL before execution
- Difficult to test or modify

**Recommendation:** Use the schema_manager system for all schema creation.

#### Minor Issues

**m1. Magic Numbers (code_flow_viewer.lua:123-126)**

```lua
local LAYER_SPACING = 300
local NODE_SPACING = 250
local START_X = 100
local START_Y = 100
```

**Recommendation:** Move to configuration or make adjustable.

**m2. Incomplete Error Messages**

Some error messages lack context:

```lua
-- workflow_db.lua:186
print("Database not initialized")
return nil
```

**Recommendation:** Include function name and operation being attempted.

**m3. Unused Return Values**

Multiple locations ignore success/error returns:

```lua
-- workflow_db.lua:460-461
db_handle:execute(string.format("DELETE FROM workflow_nodes WHERE workflow_id = %d", workflow_id))
db_handle:execute(string.format("DELETE FROM workflow_connections WHERE workflow_id = %d", workflow_id))
```

**Recommendation:** Check return values and handle errors.

**m4. String Concatenation for Complex Queries**

```lua
-- db_tools.lua:200-206
local sql = string.format([[
    SELECT %s, COUNT(*) as count
    FROM %s
    GROUP BY %s
    HAVING COUNT(*) > 1
]], col_list, table_name, col_list)
```

**Problem:** Column list is concatenated directly without validation.

**Recommendation:** Validate column names against schema before concatenation.

**m5. Inconsistent Naming Conventions**

- `db_handle` vs `db` vs `database` for database handles
- `table_def` vs `table_info` vs `table_row`
- `success` vs `exec_success` vs `fn_success`

**Recommendation:** Standardize naming conventions.

**m6. No Query Result Limit Protection**

Queries can return unlimited rows:

```lua
-- workflow_db.lua:239-243
local results, error = db_handle:query([[
    SELECT id, name, color_r, color_g, color_b, color_a
    FROM node_types
    ORDER BY name
]])
```

**Recommendation:** Add LIMIT clause or paginate large result sets.

### Schema Management

#### Type System

The type mapping system is well-designed:

```lua
-- schema_manager.lua:8-37
local TYPE_MAP = {
    integer = "INTEGER",
    text = "TEXT",
    boolean = "INTEGER",  -- SQLite convention
    timestamp = "TEXT",   -- ISO 8601 strings
    id = "INTEGER PRIMARY KEY AUTOINCREMENT"
}
```

**Strengths:**
- Handles common type aliases
- Auto-increment support
- Boolean mapping to INTEGER (SQLite best practice)

**Weaknesses:**
- No type validation for incompatible conversions
- No support for custom types
- Date/time always stored as TEXT (no validation)

#### Constraint Support

Comprehensive constraint system (schema_manager.lua:50-90):

- NOT NULL
- UNIQUE
- DEFAULT values (with type-aware quoting)
- CHECK constraints
- PRIMARY KEY (single and composite)
- FOREIGN KEY with ON DELETE/UPDATE actions

**Missing:**
- COLLATE clauses
- Generated columns (SQLite 3.31+)
- Partial indexes
- WITHOUT ROWID optimization

#### Validation System

Schema validation (schema_executor.lua:31-99) checks:

- Schema structure (tables, columns present)
- Foreign key references exist
- Primary key presence (warning only)
- Invalid foreign key format

**Missing:**
- Data type compatibility
- Constraint conflicts
- Circular foreign key dependencies
- Index size/complexity limits

### Query Performance

#### Current Performance Characteristics

**Strengths:**
1. Batch insert support (schema_manager.lua:347-383)
2. PRAGMA usage for efficient metadata queries
3. LIMIT clauses in sample queries

**Weaknesses:**

1. **Missing Indexes on Foreign Keys**
   - All foreign key columns lack indexes
   - JOINs will perform full table scans
   - Impact: O(n*m) instead of O(n log m)

2. **N+1 Query Pattern (workflow_db.lua:232-291)**
```lua
for _, node_type_row in ipairs(results) do
    -- Individual query per node type
    local ports, port_error = db_handle:query(string.format([[
        SELECT port_name, port_type, port_order
        FROM node_type_ports
        WHERE node_type_id = %d
    ]], node_type_row.id))
end
```

**Recommendation:** Use JOIN or single IN query:
```sql
SELECT nt.*, p.port_name, p.port_type, p.port_order
FROM node_types nt
LEFT JOIN node_type_ports p ON p.node_type_id = nt.id
ORDER BY nt.name, p.port_order
```

3. **Unnecessary Multiple Queries (db_inspector.lua:119-166)**
   - Separate query for NULL count
   - Separate query for DISTINCT count
   - Can be combined into single query

**Recommendation:**
```sql
SELECT
    COUNT(*) as total,
    COUNT(col_name) as non_null,
    COUNT(DISTINCT col_name) as distinct_count
FROM table_name
```

4. **No Query Result Caching**
   - Same introspection queries executed repeatedly
   - Schema rarely changes but queried frequently

**Recommendation:** Cache PRAGMA results with invalidation on schema changes.

5. **No EXPLAIN QUERY PLAN Usage**
   - No performance analysis tooling
   - Can't identify slow queries

**Recommendation:** Add query profiling wrapper.

#### Recommended Indexes

```sql
-- workflow_db.lua
CREATE INDEX idx_node_type_ports_type_id ON node_type_ports(node_type_id);
CREATE INDEX idx_workflow_nodes_workflow_id ON workflow_nodes(workflow_id);
CREATE INDEX idx_workflow_nodes_type_id ON workflow_nodes(node_type_id);
CREATE INDEX idx_workflow_connections_workflow_id ON workflow_connections(workflow_id);
CREATE INDEX idx_workflow_connections_from_node ON workflow_connections(from_node);
CREATE INDEX idx_workflow_connections_to_node ON workflow_connections(to_node);

-- code_flow_viewer.lua
CREATE INDEX idx_node_types_flow_id ON node_types(flow_id);
CREATE INDEX idx_ports_node_type_id ON ports(node_type_id);
CREATE INDEX idx_nodes_flow_id ON nodes(flow_id);
CREATE INDEX idx_connections_flow_id ON connections(flow_id);
CREATE INDEX idx_flows_app_name ON flows(app_name);
```

### Security Analysis

#### SQL Injection Risk Assessment

**HIGH RISK - String Formatting (workflow_db.lua):**

All CRUD operations in workflow_db.lua use string formatting:

```lua
-- Line 193-196: Name with manual escaping, numbers without validation
local sql = string.format([[
    INSERT INTO node_types (name, color_r, color_g, color_b, color_a)
    VALUES ('%s', %d, %d, %d, %d)
]], escaped_name, r, g, b, a or 255)
```

**Attack Vector:**
```lua
-- If a malicious user provides:
name = "Test'; DROP TABLE node_types; --"
-- Even with escaping, this becomes:
-- VALUES ('Test''; DROP TABLE node_types; --', ...)
-- The double quote escapes it, BUT:

-- If they provide:
color_r = "0); DROP TABLE node_types; --"
-- This becomes:
-- VALUES ('name', 0); DROP TABLE node_types; --, ...)
-- SUCCESSFUL INJECTION because numbers aren't quoted!
```

**MEDIUM RISK - Table/Column Name Injection (db_tools.lua):**

```lua
-- Line 200-206
local col_list = table.concat(columns, ", ")
local sql = string.format([[
    SELECT %s, COUNT(*) as count
    FROM %s
    GROUP BY %s
]], col_list, table_name, col_list)
```

**Attack Vector:**
```lua
-- If columns contains:
columns = {"id", "name; DROP TABLE contacts; --"}
-- Results in:
-- SELECT id, name; DROP TABLE contacts; --, COUNT(*) as count
```

**LOW RISK - Parameterized Queries (sqlite_demo.lua):**

```lua
-- Line 77-82: SAFE
local sql = "INSERT INTO contacts (name, email, phone, company, notes) VALUES (?, ?, ?, ?, ?)"
local result, error = database:query(sql, name, email, phone or "", company or "", notes or "")
```

#### Security Recommendations

1. **Immediate Action Required:**
   - Replace ALL string.format SQL with parameterized queries
   - Add type validation for numeric parameters
   - Whitelist table/column names against schema

2. **Input Validation:**
   - Validate all numeric inputs are actually numbers
   - Validate color values in range 0-255
   - Validate IDs are positive integers
   - Validate string length limits

3. **Database Security:**
   - Enable foreign_keys pragma by default
   - Set query timeout limits
   - Implement prepared statement caching
   - Add query complexity limits

4. **Audit Trail:**
   - Log all schema modifications
   - Track data changes (created_at, updated_at)
   - Record last access times

#### Data Validation

**Current Validation (db_tools.lua:8-73):**

Validates:
- Required column presence
- Basic type checking (INTEGER, REAL, TEXT)
- NOT NULL constraints

**Missing Validation:**
- String length limits
- Numeric range constraints
- Email/phone format validation
- Date/time format validation
- Enum value validation
- Custom CHECK constraint validation

**Recommendation:** Enhance validation with regex patterns and range checks.

## Recommendations

### Priority 1 (Critical - Security)

1. **Replace all string formatting with parameterized queries**
   - Affects: workflow_db.lua (all CRUD operations)
   - Estimated effort: ~100 lines changed
   - Risk: High SQL injection vulnerability

2. **Add input validation layer**
   - Validate types, ranges, and formats before DB operations
   - Create validation helper module
   - Estimated effort: ~200 lines new code

3. **Fix resource leak in code_flow_viewer.lua**
   - Add proper cleanup on early returns
   - Use pcall for error handling

### Priority 2 (Major - Performance & Reliability)

4. **Add database indexes**
   - Create indexes on all foreign keys
   - Add composite indexes for common queries
   - Estimated improvement: 10-100x for large datasets

5. **Implement transaction management**
   - Wrap multi-statement operations
   - Add transaction helper utilities
   - Use WAL mode for better concurrency

6. **Fix N+1 query patterns**
   - Combine queries in load_node_types
   - Use JOINs instead of loops with queries

7. **Standardize error handling**
   - Choose single return pattern
   - Add error context information
   - Create error handling utilities

8. **Add schema versioning system**
   - Track schema version in database
   - Implement migration framework
   - Add rollback support

### Priority 3 (Minor - Code Quality)

9. **Improve error messages**
   - Add context (function name, operation)
   - Include relevant IDs/names
   - Log errors consistently

10. **Eliminate magic numbers**
    - Move to configuration
    - Document constants
    - Make layout parameters adjustable

11. **Add query result limits**
    - Default LIMIT for SELECT queries
    - Pagination support
    - Warning for large result sets

12. **Standardize naming conventions**
    - Document naming standards
    - Refactor inconsistent names
    - Use clear, descriptive names

### Priority 4 (Enhancement - Features)

13. **Add query profiling**
    - EXPLAIN QUERY PLAN wrapper
    - Query timing statistics
    - Slow query logging

14. **Implement result caching**
    - Cache schema introspection results
    - Cache-aside pattern
    - Invalidation on schema changes

15. **Enhance schema validation**
    - Check for circular dependencies
    - Validate constraint compatibility
    - Suggest optimizations

16. **Add batch operation support**
    - Batch updates
    - Batch deletes
    - Progress reporting

## Dependencies & Integration

### External Dependencies

1. **SQLite C Library**
   - Accessed via C++ bindings (db.open, db:query, db:execute)
   - Assumed to support:
     - Parameterized queries (?)
     - Transactions (BEGIN, COMMIT, ROLLBACK)
     - PRAGMA queries
     - Foreign key constraints
     - Triggers (implied)

2. **Lua Standard Library**
   - string manipulation (format, gsub, match, lower, upper, concat)
   - table operations (insert, concat, sort)
   - math (random, floor, min, max)
   - io (file operations in db_tools.lua:368-387)
   - os (time, clock)
   - pcall for error handling

3. **File System Module (fs)**
   - fs.exists(path)
   - fs.stat(path) -> {size}
   - fs.dirname(path)
   - fs.create_dir(path)
   - fs.read_file(path)

4. **Data Binding System (data)**
   - data.bind(key, value)
   - Used for UI updates

5. **Event System (event)**
   - event.register(name, handler)
   - Used for UI interactions

6. **UI System (ui)**
   - ui.load_document(path, modal, id)

### Integration Points

1. **Workflow Editor**
   - workflow_db.lua provides node type management
   - Uses data binding for node_types
   - Persists workflow state

2. **Code Flow Viewer**
   - code_flow_viewer.lua uses db_inspector patterns
   - Loads from separate code_flows.db
   - Auto-layout algorithm for visualization

3. **Data Import Pipeline**
   - schema_manager for schema creation
   - schema_executor for validation and execution
   - db_tools for data quality checks

4. **UI Components**
   - sqlite_demo shows integration pattern
   - Data binding for reactive updates
   - Event handlers for user actions

### Coupling Analysis

**Tight Coupling:**
- workflow_db.lua tightly coupled to specific table schema
- code_flow_viewer.lua tightly coupled to flows schema
- sqlite_demo.lua tightly coupled to contacts schema

**Loose Coupling:**
- schema_manager.lua is schema-agnostic
- db_inspector.lua works with any SQLite database
- db_tools.lua provides generic utilities

**Recommendation:** Extract schema definitions to separate files, use schema_manager consistently.

## Summary

The Database & Schema Layer is a comprehensive and well-architected system with strong introspection and analysis capabilities. The schema management system is particularly well-designed with its declarative approach and transaction safety.

**Critical security vulnerabilities exist** in the form of SQL injection risks due to string formatting for SQL construction. This must be addressed immediately by converting to parameterized queries.

Performance can be significantly improved by adding indexes on foreign keys and eliminating N+1 query patterns.

The lack of a schema versioning and migration system will become problematic as the application evolves. Implementing this should be a priority before the schema becomes more complex.

Overall code quality is good, with clear separation of concerns and comprehensive error handling in most areas. Standardizing error handling patterns and improving input validation would enhance robustness.

**Risk Level:** MEDIUM-HIGH (due to SQL injection vulnerabilities)

**Recommended Action:** Address Priority 1 security issues immediately, then proceed with performance optimizations and code quality improvements.
