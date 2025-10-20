-- File Editor
-- Integrated file browser and text editor

-- Load highlighter configuration
local highlighter_config = require("highlighters.config")
local loaded_highlighters = {}

local current_path = fs.get_cwd()
local current_file = nil
local editor_element = nil

-- Data models
local browser_data = {
    current_path = current_path,
    files = {}
}

local editor_data = {
    file_path = "No file open",
    file_info = ""
}

function format_size(size)
    if size < 1024 then
        return string.format("%d B", size)
    elseif size < 1024 * 1024 then
        return string.format("%.1f KB", size / 1024)
    elseif size < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", size / (1024 * 1024))
    else
        return string.format("%.1f GB", size / (1024 * 1024 * 1024))
    end
end

function update_file_list()
    local entries, error = fs.list_dir(current_path)

    if error ~= "" then
        print("Error listing directory: " .. error)
        return
    end

    -- Sort: directories first, then files
    table.sort(entries, function(a, b)
        if a.is_dir and not b.is_dir then
            return true
        elseif not a.is_dir and b.is_dir then
            return false
        else
            return a.name < b.name
        end
    end)

    -- Update data model
    browser_data.files = {}

    -- Add parent directory entry if not at root
    if current_path ~= "" and current_path ~= "/" then
        table.insert(browser_data.files, {
            icon = "[D]",
            name = "..",
            target = "..",
            is_dir = true
        })
    end

    -- Add files and directories
    for _, entry in ipairs(entries) do
        table.insert(browser_data.files, {
            icon = entry.is_dir and "[D]" or "[F]",
            name = entry.name,
            target = entry.name,
            is_dir = entry.is_dir
        })
    end

    -- Update browser info
    data.bind("browser_info", {{current_path = current_path}})
    data.bind("files", browser_data.files)
end

function navigate_to(target)
    if target == ".." then
        -- Go up one directory
        local parent = current_path:match("(.+)[/\\][^/\\]+$")
        if parent then
            current_path = parent
        else
            if current_path:match("^[A-Za-z]:") then
                current_path = current_path:match("^[A-Za-z]:\\?") or current_path
            else
                current_path = "/"
            end
        end
    else
        -- Navigate into directory
        if current_path:sub(-1) == "/" or current_path:sub(-1) == "\\" then
            current_path = current_path .. target
        else
            local sep = current_path:match("\\") and "\\" or "/"
            current_path = current_path .. sep .. target
        end
    end

    update_file_list()
end

function get_full_path(filename)
    local sep = current_path:match("\\") and "\\" or "/"
    return current_path .. sep .. filename
end

function open_file(file_path)
    print("Opening file: " .. file_path)

    -- Read file content
    local content, error = fs.read_file(file_path)
    if error ~= "" then
        print("Error reading file: " .. error)
        return
    end

    current_file = file_path

    -- Get file size
    local size = #content

    -- Update editor info
    editor_data.file_path = file_path
    editor_data.file_info = format_size(size) .. " · " .. count_lines(content) .. " lines"
    data.bind("editor_info", {editor_data})

    -- Set text in editor first (renders immediately with no highlighting)
    ui.set_texteditor_content("code_editor", content)
    print("Loaded file: " .. file_path .. " (" .. size .. " bytes)")

    -- Determine file type and compute syntax highlighting
    local ext = file_path:match("%.([^%.]+)$")

    -- Skip syntax highlighting for large files (> 1MB) or binary files
    local max_size = 1024 * 1024  -- 1MB
    local is_binary = content:find('\0') ~= nil

    if size <= max_size and not is_binary then
        compute_and_bind_tokens(ext, content)
    else
        if is_binary then
            print("Skipping syntax highlighting: Binary file detected")
        else
            print("Skipping syntax highlighting: File too large (" .. format_size(size) .. ")")
        end
        -- Clear any existing tokens
        data.bind("editor_tokens_code_editor", {})
    end
end

-- Compute syntax tokens and bind them to the data model
function compute_and_bind_tokens(ext, content)
    local highlighter = get_highlighter_for_extension(ext)
    if not highlighter then
        -- No highlighter available, clear tokens
        data.bind("editor_tokens_code_editor", {})
        return
    end

    -- Call the highlighter function
    local tokens = highlighter(content)
    if tokens and #tokens > 0 then
        -- Bind the tokens to the data model
        -- ElementTextEditor will read from "editor_tokens_code_editor"
        data.bind("editor_tokens_code_editor", tokens)
        print("Applied syntax highlighting: " .. #tokens .. " tokens")
    else
        -- No tokens, clear
        data.bind("editor_tokens_code_editor", {})
    end
end

function count_lines(text)
    local count = 1
    for _ in text:gmatch("\n") do
        count = count + 1
    end
    return count
end

-- Get highlighter function for a file extension
function get_highlighter_for_extension(ext)
    if not ext then return nil end

    ext = ext:lower()
    local module_path = highlighter_config[ext]
    if not module_path then
        return nil
    end

    -- Load and cache highlighter module
    if not loaded_highlighters[module_path] then
        local success, module = pcall(require, module_path)
        if success then
            loaded_highlighters[module_path] = module
        else
            print("Warning: Failed to load highlighter: " .. module_path .. " - " .. tostring(module))
            return nil
        end
    end

    local highlighter = loaded_highlighters[module_path]
    if highlighter and highlighter.highlight then
        -- Wrap in pcall to catch any errors during highlighting
        return function(text)
            local success, result = pcall(highlighter.highlight, text)
            if success then
                return result
            else
                print("Warning: Syntax highlighter error for " .. ext .. ": " .. tostring(result))
                return {}  -- Return empty tokens on error
            end
        end
    end

    return nil
end

function startup()
    print("File editor started (thread_id: " .. thread_id .. ")")

    -- Register file click handler
    event.register("file_clicked", function(payload)
        if payload.is_dir or payload.target == ".." then
            navigate_to(payload.target)
        else
            -- File clicked - open in editor
            local full_path = get_full_path(payload.target)
            open_file(full_path)
        end
    end)

    -- Initial directory listing
    update_file_list()

    -- Update editor info (no file open)
    data.bind("editor_info", {editor_data})

    -- Load UI
    ui.load_document("ui/file_editor.rml")
end

function update(dt)
    -- Nothing to do
end

function shutdown()
    print("File editor shutting down")
end
