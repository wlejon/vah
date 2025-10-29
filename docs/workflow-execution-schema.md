# Workflow Execution Database Schema

## Overview

This document defines all database tables and fields required for the workflow execution system.

## Workflow Configuration

### workflows table (modified)

```sql
-- Add execution-related columns to existing workflows table
ALTER TABLE workflows ADD COLUMN script TEXT;        -- Main workflow script (callbacks)
ALTER TABLE workflows ADD COLUMN config TEXT;        -- JSON configuration
```

**config JSON structure:**
```json
{
  "requires": ["db", "fs", "http"],
  "timeout": 3600,
  "description": "User-facing description"
}
```

### workflow_nodes table (modified)

```sql
-- Add config column for node instance data
ALTER TABLE workflow_nodes ADD COLUMN config TEXT;   -- JSON configuration
```

**config JSON structure:**
```json
{
  "script": "local result = inputs.A + inputs.B\nreturn {Result = result}",
  "inputs": ["A", "B"],
  "outputs": ["Result"],
  "label": "Add Numbers",
  "callback_type": null  -- For callback nodes: "on_start", "on_complete", etc.
}
```

## Library Registry

### library_registry table

```sql
CREATE TABLE IF NOT EXISTS library_registry (
    id TEXT PRIMARY KEY,                    -- "db", "fs", "http"
    name TEXT NOT NULL,                     -- "Database Access"
    description TEXT NOT NULL,              -- Detailed description of capabilities
    access_description TEXT NOT NULL,       -- What data/resources it can access
    is_builtin BOOLEAN DEFAULT 0,          -- 1 for C++ libs, 0 for Lua libs
    enabled BOOLEAN DEFAULT 1,             -- Global enable/disable
    lua_module_path TEXT,                  -- For Lua libs: path to module
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Default C++ Libraries

```sql
INSERT INTO library_registry (id, name, description, access_description, is_builtin) VALUES
('math', 'Math Operations', 'Standard mathematical functions and constants', 'No data access - pure computation', 1),
('string', 'String Operations', 'String manipulation and pattern matching', 'No data access - pure computation', 1),
('table', 'Table Operations', 'Table manipulation utilities', 'No data access - pure computation', 1),
('db', 'Database Access', 'Query and modify SQLite databases', 'Read/write access to execution-specific tables', 1),
('fs', 'File System Access', 'Read and write files on disk', 'Full file system access (current user permissions)', 1),
('http', 'Network Access', 'Make HTTP/HTTPS requests', 'Can send data to external services', 1),
('ui', 'User Interface', 'Create UI windows using RmlUI', 'Can display content and capture user input', 1),
('thread', 'Threading Utilities', 'Thread management and querying', 'Limited to thread queries and sleep', 1),
('event', 'Event System', 'Trigger and listen for events', 'Can communicate with other application components', 1);
```

## Workflow Approvals

### workflow_approvals table

```sql
CREATE TABLE IF NOT EXISTS workflow_approvals (
    workflow_id INTEGER PRIMARY KEY,
    approved BOOLEAN DEFAULT 0,
    requires_hash TEXT,                     -- Hash of requires list when approved
    approved_at TIMESTAMP,
    FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
);
```

**Behavior:**
- Row exists with `approved=1`: Workflow runs silently
- Row missing or `approved=0`: Show approval dialog
- `requires_hash` changes: Re-prompt user
- No persistent "deny" state - absence means prompt again

## Execution Tracking

### workflow_executions table

```sql
CREATE TABLE IF NOT EXISTS workflow_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow_id INTEGER NOT NULL,
    status TEXT NOT NULL,                   -- 'running', 'completed', 'error', 'stopped'
    thread_id INTEGER,                      -- Thread ID from application
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    error_message TEXT,
    FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
);

CREATE INDEX idx_executions_workflow ON workflow_executions(workflow_id);
CREATE INDEX idx_executions_status ON workflow_executions(status);
```

### execution_nodes table

```sql
CREATE TABLE IF NOT EXISTS execution_nodes (
    execution_id INTEGER NOT NULL,
    node_id INTEGER NOT NULL,
    status TEXT NOT NULL,                   -- 'pending', 'running', 'completed', 'error', 'skipped'
    inputs TEXT,                            -- JSON: input values
    outputs TEXT,                           -- JSON: output values
    error_message TEXT,
    execution_order INTEGER,                -- Order in which node was executed
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    PRIMARY KEY (execution_id, node_id),
    FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
);

CREATE INDEX idx_execution_nodes_execution ON execution_nodes(execution_id);
```

### execution_trace table

```sql
CREATE TABLE IF NOT EXISTS execution_trace (
    execution_id INTEGER NOT NULL,
    sequence INTEGER NOT NULL,              -- Order of execution
    node_id INTEGER NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (execution_id, sequence),
    FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
);
```

## Per-Execution State Tables

These tables are created dynamically for each execution:

### exec_{execution_id}_state

```sql
-- Created per execution for custom state storage
CREATE TABLE IF NOT EXISTS exec_{execution_id}_state (
    key TEXT PRIMARY KEY,
    value TEXT,                             -- JSON-encoded value
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

Accessed via:
```lua
execution.set("my_key", {data = "value"})
local data = execution.get("my_key")
```

### exec_{execution_id}_log

```sql
-- Created per execution for logging
CREATE TABLE IF NOT EXISTS exec_{execution_id}_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    level TEXT,                             -- 'debug', 'info', 'warning', 'error'
    node_id INTEGER,                        -- NULL for workflow-level logs
    message TEXT
);
```

Accessed via:
```lua
execution.log("info", "Processing started")
execution.log("error", "Failed to parse input", node_id)
```

## Execution Control

### execution_control table

```sql
CREATE TABLE IF NOT EXISTS execution_control (
    execution_id INTEGER PRIMARY KEY,
    command TEXT NOT NULL,                  -- 'run', 'pause', 'stop', 'step'
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
);
```

**Usage:**
- UI updates this table when user clicks pause/stop
- Execution thread polls this table to check for control commands
- Commands: 'run', 'pause', 'stop', 'step'

## Node Type Extensions

### Callback Node Types

Add to `node_types` table with special names:

```sql
INSERT INTO node_types (name, color_r, color_g, color_b) VALUES
('On Start', 100, 200, 100),
('On Complete', 100, 200, 100),
('On Node Start', 150, 200, 100),
('On Node Complete', 150, 200, 100),
('On Error', 200, 100, 100);
```

These nodes have special `callback_type` in their config:
```json
{
  "callback_type": "on_node_complete",
  "target_node_id": 42,  // For on_node_* callbacks
  "script": "print('Node completed')"
}
```

## Cleanup

### execution_cleanup table

```sql
CREATE TABLE IF NOT EXISTS execution_cleanup (
    execution_id INTEGER PRIMARY KEY,
    cleanup_after TIMESTAMP,                -- When to delete execution data
    keep_indefinitely BOOLEAN DEFAULT 0,
    FOREIGN KEY (execution_id) REFERENCES workflow_executions(id) ON DELETE CASCADE
);
```

Automated cleanup process:
- Delete `exec_{execution_id}_*` tables after retention period
- Configurable per-workflow or globally
- Option to keep important executions indefinitely

## Indexes for Performance

```sql
-- Execution lookups
CREATE INDEX idx_executions_status_date ON workflow_executions(status, started_at DESC);

-- Node execution progress
CREATE INDEX idx_execution_nodes_status ON execution_nodes(execution_id, status);

-- Trace playback
CREATE INDEX idx_trace_sequence ON execution_trace(execution_id, sequence);
```

## Migration Path

1. Add columns to existing `workflows` and `workflow_nodes` tables
2. Create new tables: `library_registry`, `workflow_approvals`, execution tables
3. Populate `library_registry` with default C++ libraries
4. Create indexes for performance
5. Add cleanup job for old execution data
