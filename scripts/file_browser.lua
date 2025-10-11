-- File Browser Demo
-- Displays a navigable file system browser

local current_path = fs.get_cwd()
local file_list = {}

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

    file_list = entries
    render_file_list()
end

function render_file_list()
    -- Update current path display
    ui.set_element_text("current_path", current_path)

    -- Build file list HTML
    local html = ""

    -- Add parent directory entry if not at root
    if current_path ~= "" and current_path ~= "/" then
        html = html .. '<div class="file-item" onclick="trigger(\'navigate\', {target = \'..\'})">'
        html = html .. '<span class="file-icon">📁</span>'
        html = html .. '<span class="file-name">..</span>'
        html = html .. '<span class="file-size"></span>'
        html = html .. '</div>'
    end

    -- Add files and directories
    for _, entry in ipairs(file_list) do
        local icon = entry.is_dir and "📁" or "📄"
        local size_str = entry.is_dir and "" or format_size(entry.size)

        html = html .. string.format(
            '<div class="file-item" onclick="trigger(\'navigate\', {target = \'%s\', is_dir = %s})">',
            entry.name:gsub("'", "\\'"),
            entry.is_dir and "true" or "false"
        )
        html = html .. string.format('<span class="file-icon">%s</span>', icon)
        html = html .. string.format('<span class="file-name">%s</span>', entry.name)
        html = html .. string.format('<span class="file-size">%s</span>', size_str)
        html = html .. '</div>'
    end

    ui.set_element_text("file_list", html)
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

    -- Load UI
    ui.load_document("ui/file_browser.rml")

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

    -- Initial directory listing
    update_file_list()
end

function update(dt)
    -- Nothing to do in update for now
end

function shutdown()
    print("File browser shutting down")
end
