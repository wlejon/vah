-- Code Flow Documentation Database Schema
-- This database stores code flow visualizations for documentation purposes

-- Main flows table - one entry per application/feature
CREATE TABLE IF NOT EXISTS flows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    app_name TEXT NOT NULL UNIQUE,  -- e.g., 'tetris', 'file_editor'
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Node types define the visual appearance and metadata for nodes
CREATE TABLE IF NOT EXISTS node_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id INTEGER NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL,  -- 'function', 'branch', 'loop', 'input', 'render', 'init'
    color_r INTEGER DEFAULT 128,
    color_g INTEGER DEFAULT 128,
    color_b INTEGER DEFAULT 128,
    color_a INTEGER DEFAULT 255,
    file_location TEXT,
    description TEXT,
    details TEXT
);

-- Nodes are instances of node types positioned in the flow
CREATE TABLE IF NOT EXISTS nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id INTEGER NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
    node_type_id INTEGER NOT NULL REFERENCES node_types(id),
    label TEXT,  -- Display label (can be multi-line)
    x REAL DEFAULT 0,
    y REAL DEFAULT 0
);

-- Connections define the edges between nodes
CREATE TABLE IF NOT EXISTS connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id INTEGER NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
    from_node_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    to_node_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    label TEXT,  -- optional: 'yes', 'no', 'success', 'fail', etc.
    UNIQUE(from_node_id, to_node_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_node_types_flow ON node_types(flow_id);
CREATE INDEX IF NOT EXISTS idx_nodes_flow ON nodes(flow_id);
CREATE INDEX IF NOT EXISTS idx_connections_flow ON connections(flow_id);
CREATE INDEX IF NOT EXISTS idx_connections_from ON connections(from_node_id);
CREATE INDEX IF NOT EXISTS idx_connections_to ON connections(to_node_id);
