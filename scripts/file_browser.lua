-- File Browser Demo
-- Displays a navigable file system browser

local current_path = fs.get_cwd()

-- Data model
local browser_data = {
    current_path = current_path,
    files = {}
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
    browser_data.current_path = current_path
    browser_data.files = {}

    -- Add parent directory entry if not at root
    if current_path ~= "" and current_path ~= "/" then
        table.insert(browser_data.files, {
            icon = "📁",
            name = "..",
            size = "",
            target = "..",
            is_dir = true
        })
    end

    -- Add files and directories
    for _, entry in ipairs(entries) do
        table.insert(browser_data.files, {
            icon = entry.is_dir and "📁" or "📄",
            name = entry.name,
            size = entry.is_dir and "" or format_size(entry.size),
            target = entry.name,
            is_dir = entry.is_dir
        })
    end

    -- Bind updated models separately
    -- browser_info contains just the current_path for display
    datamodel.bind_table("browser_info", {{current_path = current_path}})
    -- files is the flat array of file entries for iteration and event handling
    datamodel.bind_table("files", browser_data.files)
end

function navigate_to(target)
    if target == ".." then
        -- Go up one directory
        local parent = current_path:match("(.+)[/\\][^/\\]+$")
        if parent then
            current_path = parent
        else
            -- Already at root or near root
            if current_path:match("^[A-Za-z]:") then
                -- Windows: if we're at "C:\something", go to "C:\"
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
            -- Determine separator based on OS
            local sep = current_path:match("\\") and "\\" or "/"
            current_path = current_path .. sep .. target
        end
    end

    update_file_list()
end

function read_file_content(file_path)
    local content, error = fs.read_file(file_path)
    if error ~= "" then
        return "Error reading file: " .. error
    end

    -- Limit to first 1000 characters for preview
    if #content > 1000 then
        content = content:sub(1, 1000) .. "\n\n... (truncated)"
    end

    return content
end

function startup()
    print("File browser started (thread_id: " .. thread_id .. ")")

    -- Register navigation event handler
    event.register("navigate", function(payload)
        if payload.is_dir or payload.target == ".." then
            navigate_to(payload.target)
        else
            -- File clicked - show content preview
            local sep = current_path:match("\\") and "\\" or "/"
            local full_path = current_path .. sep .. payload.target
            local content = read_file_content(full_path)
            print("File content preview:")
            print(content)
        end
    end)

    -- Initial directory listing (before loading UI)
    update_file_list()

    -- Load UI
    ui.load_document("ui/file_browser.rml", true, "file_browser")
end

function update(dt)
    -- Nothing to do in update for now
end

function shutdown()
    print("File browser shutting down")
end
