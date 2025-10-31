-- File Editor
-- Integrated file browser and text editor

-- Load highlighter configuration
local highlighter_config = require("lib.highlighters.config")
local loaded_highlighters = {}

-- Load MIME type detection
local mime = require("lib.mime_types")

local current_path = fs.get_cwd()
local current_file = nil
local editor_element = nil
local current_file_ext = nil

-- Data models
local browser_data = {
    current_path = current_path,
    files = {}
}

local editor_data = {
    file_path = "No file open",
    file_info = "",
    file_type = "",
    is_editable = false,
    is_modified = false
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
    datamodel.bind_table("browser_info", {{current_path = current_path}})
    datamodel.bind_table("files", browser_data.files)
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

    -- Detect file type and editability
    local file_type = mime.get_type_description(file_path)
    local is_editable = mime.is_editable(file_path) and not mime.is_binary(content)

    -- Update editor info
    editor_data.file_path = file_path
    editor_data.file_info = format_size(size) .. " · " .. count_lines(content) .. " lines"
    editor_data.file_type = file_type
    editor_data.is_editable = is_editable
    editor_data.is_modified = false
    datamodel.bind_table("editor_info", {editor_data})

    -- Set text in editor first (renders immediately with no highlighting)
    ui.set_texteditor_content("code_editor", content)

    -- Set editable state
    ui.set_texteditor_editable("code_editor", is_editable)

    if is_editable then
        print("Loaded file: " .. file_path .. " (" .. size .. " bytes) [EDITABLE]")
    else
        print("Loaded file: " .. file_path .. " (" .. size .. " bytes) [READ-ONLY]")
    end

    -- Store file extension for re-highlighting
    current_file_ext = file_path:match("%.([^%.]+)$")

    -- Skip syntax highlighting for large files (> 1MB) or binary files
    local max_size = 1024 * 1024  -- 1MB
    local is_binary_file = mime.is_binary(content)

    if size <= max_size and not is_binary_file then
        compute_and_bind_tokens(current_file_ext, content)
    else
        if is_binary_file then
            print("Skipping syntax highlighting: Binary file detected")
        else
            print("Skipping syntax highlighting: File too large (" .. format_size(size) .. ")")
        end
        -- Clear any existing tokens
        ui.set_texteditor_tokens("code_editor", {})
        current_file_ext = nil  -- Disable re-highlighting for large/binary files
    end
end

-- Compute syntax tokens and send them via command
function compute_and_bind_tokens(ext, content)
    local highlighter = get_highlighter_for_extension(ext)
    if not highlighter then
        -- No highlighter available, clear tokens
        ui.set_texteditor_tokens("code_editor", {})
        return
    end

    -- Call the highlighter function
    local tokens = highlighter(content)
    if tokens and #tokens > 0 then
        -- Send tokens to ElementTextEditor via command
        ui.set_texteditor_tokens("code_editor", tokens)
        print("Applied syntax highlighting: " .. #tokens .. " tokens")
    else
        -- No tokens, clear
        ui.set_texteditor_tokens("code_editor", {})
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

function save_file()
    if not current_file then
        print("No file is currently open")
        return
    end

    if not editor_data.is_editable then
        print("Cannot save: File is read-only")
        return
    end

    -- Get content from editor (we'll receive it via the save event)
    -- This function will be called by the save event handler
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

    -- Register save event handler (triggered by Ctrl+S in editor)
    event.register("save", function(payload)
        if not current_file then
            print("No file to save")
            return
        end

        local content = payload.content
        if not content then
            print("No content to save")
            return
        end

        -- Write file
        local success, error = fs.write_file(current_file, content)
        if error ~= "" then
            print("Error saving file: " .. error)
            return
        end

        print("Saved: " .. current_file .. " (" .. #content .. " bytes)")

        -- Re-compute syntax highlighting with the new content
        local ext = current_file:match("%.([^%.]+)$")
        if ext then
            compute_and_bind_tokens(ext, content)
        end

        -- Mark as not modified
        ui.set_texteditor_modified("code_editor", false)
        editor_data.is_modified = false
        datamodel.bind_table("editor_info", {editor_data})
    end)

    -- Register modified event handler (triggered when editor content changes)
    event.register("modified", function(payload)
        if payload.element_id == "code_editor" then
            editor_data.is_modified = payload.modified
            datamodel.bind_table("editor_info", {editor_data})

            -- Re-highlight immediately when content is modified
            if payload.modified and payload.content and current_file_ext then
                compute_and_bind_tokens(current_file_ext, payload.content)
            end
        end
    end)

    -- Initial directory listing
    update_file_list()

    -- Update editor info (no file open)
    datamodel.bind_table("editor_info", {editor_data})

    -- Load UI
    ui.load_document("ui/file_editor.rml", true, "file_editor")
end

function update(dt)
    -- Nothing to do
end

function shutdown()
    print("File editor shutting down")
end
