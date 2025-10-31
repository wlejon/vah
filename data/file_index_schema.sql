-- File Indexer Database Schema
-- Project-oriented filesystem indexer for text files

-- Indexing runs - track when indexing occurred
CREATE TABLE IF NOT EXISTS index_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    root_path TEXT NOT NULL,
    started_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    files_indexed INTEGER DEFAULT 0,
    files_skipped INTEGER DEFAULT 0,
    total_size INTEGER DEFAULT 0,
    status TEXT DEFAULT 'running' CHECK(status IN ('running', 'completed', 'failed'))
);

-- Indexed files - core file metadata
CREATE TABLE IF NOT EXISTS indexed_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL UNIQUE,
    relative_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_extension TEXT,
    file_size INTEGER NOT NULL,
    modified_time REAL NOT NULL,
    content_hash TEXT,
    mime_type TEXT,
    is_text INTEGER DEFAULT 1,
    indexed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_run_id INTEGER REFERENCES index_runs(id)
);

-- File analysis - extensible metadata for additional analysis
-- Design supports future features like syntax errors, parser info, etc.
CREATE TABLE IF NOT EXISTS file_analysis (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL REFERENCES indexed_files(id) ON DELETE CASCADE,
    analysis_type TEXT NOT NULL,  -- 'syntax_check', 'parser_info', 'lint_results', etc.
    analysis_data TEXT,  -- JSON blob with analysis results
    analyzed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_id, analysis_type)
);

-- File content - stores actual text content for future search functionality
CREATE TABLE IF NOT EXISTS file_content (
    file_id INTEGER PRIMARY KEY REFERENCES indexed_files(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    line_count INTEGER DEFAULT 0,
    char_count INTEGER DEFAULT 0
);

-- File type statistics - aggregated view
CREATE TABLE IF NOT EXISTS file_type_stats (
    file_extension TEXT PRIMARY KEY,
    file_count INTEGER DEFAULT 0,
    total_size INTEGER DEFAULT 0,
    last_updated TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_indexed_files_path ON indexed_files(path);
CREATE INDEX IF NOT EXISTS idx_indexed_files_extension ON indexed_files(file_extension);
CREATE INDEX IF NOT EXISTS idx_indexed_files_modified ON indexed_files(modified_time);
CREATE INDEX IF NOT EXISTS idx_indexed_files_run ON indexed_files(last_run_id);
CREATE INDEX IF NOT EXISTS idx_file_analysis_file ON file_analysis(file_id);
CREATE INDEX IF NOT EXISTS idx_file_analysis_type ON file_analysis(analysis_type);

-- View: Recent files
CREATE VIEW IF NOT EXISTS recent_files AS
SELECT
    id,
    path,
    relative_path,
    file_name,
    file_extension,
    file_size,
    modified_time,
    indexed_at
FROM indexed_files
ORDER BY modified_time DESC
LIMIT 100;

-- View: File type breakdown
CREATE VIEW IF NOT EXISTS file_type_breakdown AS
SELECT
    COALESCE(file_extension, '[no extension]') as extension,
    COUNT(*) as count,
    SUM(file_size) as total_size
FROM indexed_files
GROUP BY file_extension
ORDER BY count DESC;
