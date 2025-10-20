-- MIME Type Detection
-- Determines the MIME type and editability of files based on extension

local M = {}

-- Map file extensions to MIME types
local mime_map = {
    -- Text files
    txt = "text/plain",
    md = "text/markdown",
    markdown = "text/markdown",

    -- Code files
    lua = "text/x-lua",
    cpp = "text/x-c++",
    h = "text/x-c++",
    hpp = "text/x-c++",
    c = "text/x-c",
    py = "text/x-python",
    js = "text/javascript",
    ts = "text/typescript",
    json = "application/json",
    xml = "application/xml",
    html = "text/html",
    css = "text/css",

    -- RmlUi specific
    rml = "text/rml",
    rcss = "text/rcss",

    -- Config files
    ini = "text/plain",
    conf = "text/plain",
    cfg = "text/plain",
    yaml = "text/yaml",
    yml = "text/yaml",
    toml = "text/toml",

    -- Shell scripts
    sh = "text/x-sh",
    bash = "text/x-sh",
    bat = "text/x-bat",

    -- Build files
    cmake = "text/x-cmake",

    -- Binary/Non-editable
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    bmp = "image/bmp",
    ico = "image/x-icon",

    exe = "application/x-executable",
    dll = "application/x-executable",
    so = "application/x-executable",

    zip = "application/zip",
    tar = "application/x-tar",
    gz = "application/gzip",

    pdf = "application/pdf",

    -- Database files
    db = "application/x-sqlite3",
    sqlite = "application/x-sqlite3",
    sqlite3 = "application/x-sqlite3"
}

-- Determine if a MIME type is editable as text
local function is_text_editable(mime_type)
    if not mime_type then return false end

    -- Text types are editable
    if mime_type:match("^text/") then
        return true
    end

    -- Some application types are editable text
    if mime_type == "application/json" or
       mime_type == "application/xml" then
        return true
    end

    return false
end

-- Get MIME type from file path
function M.get_mime_type(file_path)
    local ext = file_path:match("%.([^%.]+)$")
    if not ext then
        return "application/octet-stream"
    end

    ext = ext:lower()
    return mime_map[ext] or "application/octet-stream"
end

-- Check if file is editable based on path
function M.is_editable(file_path)
    local mime_type = M.get_mime_type(file_path)
    return is_text_editable(mime_type)
end

-- Check if file content is binary (contains null bytes)
function M.is_binary(content)
    if not content then return true end
    return content:find('\0') ~= nil
end

-- Get a user-friendly description of the file type
function M.get_type_description(file_path)
    local mime_type = M.get_mime_type(file_path)

    local descriptions = {
        ["text/plain"] = "Text File",
        ["text/markdown"] = "Markdown",
        ["text/x-lua"] = "Lua Script",
        ["text/x-c++"] = "C++ Source",
        ["text/x-c"] = "C Source",
        ["text/x-python"] = "Python Script",
        ["text/javascript"] = "JavaScript",
        ["text/typescript"] = "TypeScript",
        ["application/json"] = "JSON Data",
        ["text/html"] = "HTML Document",
        ["text/css"] = "CSS Stylesheet",
        ["text/rml"] = "RmlUi Document",
        ["text/rcss"] = "RmlUi Stylesheet",
        ["image/png"] = "PNG Image",
        ["image/jpeg"] = "JPEG Image",
        ["application/x-executable"] = "Executable",
        ["application/x-sqlite3"] = "SQLite Database",
        ["application/pdf"] = "PDF Document"
    }

    return descriptions[mime_type] or "Unknown File Type"
end

return M
