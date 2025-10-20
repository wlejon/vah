-- File Editor
-- Integrated file browser and text editor

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

    -- Determine file type and set syntax highlighter
    local syntax_highlighter = ""
    local ext = file_path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "lua" then
            syntax_highlighter = "lua_syntax_highlighter"
        elseif ext == "cpp" or ext == "h" or ext == "c" or ext == "hpp" or ext == "cc" or ext == "cmake" or ext == "txt" then
            syntax_highlighter = "cpp_syntax_highlighter"
        elseif ext == "js" or ext == "json" then
            syntax_highlighter = "js_syntax_highlighter"
        end
    end

    -- Set text in editor using UI command
    ui.set_texteditor_content("code_editor", content, syntax_highlighter)
    print("Loaded file: " .. file_path .. " (" .. size .. " bytes)")
end

function count_lines(text)
    local count = 1
    for _ in text:gmatch("\n") do
        count = count + 1
    end
    return count
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

-- Lua Syntax Highlighter
function lua_syntax_highlighter(text)
    local tokens = {}

    local keywords = {
        ["local"] = true, ["function"] = true, ["end"] = true,
        ["if"] = true, ["then"] = true, ["else"] = true, ["elseif"] = true,
        ["for"] = true, ["do"] = true, ["while"] = true, ["repeat"] = true,
        ["until"] = true, ["return"] = true, ["break"] = true, ["in"] = true,
        ["and"] = true, ["or"] = true, ["not"] = true, ["true"] = true, ["false"] = true,
        ["nil"] = true
    }

    local keyword_color = {r = 86, g = 156, b = 214, a = 255}
    local string_color = {r = 206, g = 145, b = 120, a = 255}
    local comment_color = {r = 106, g = 153, b = 85, a = 255}
    local number_color = {r = 181, g = 206, b = 168, a = 255}

    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    for line_num, line in ipairs(lines) do
        local line_index = line_num - 1

        -- Comments
        local comment_start = line:find("%-%-")
        if comment_start then
            table.insert(tokens, {
                line = line_index,
                start_col = comment_start - 1,
                end_col = #line,
                r = comment_color.r,
                g = comment_color.g,
                b = comment_color.b,
                a = comment_color.a
            })
        end

        -- Strings
        for s, e in line:gmatch("()[\"'].-()[\"']") do
            table.insert(tokens, {
                line = line_index,
                start_col = s - 1,
                end_col = e - 1,
                r = string_color.r,
                g = string_color.g,
                b = string_color.b,
                a = string_color.a
            })
        end

        -- Keywords
        for word in line:gmatch("[%a_][%w_]*") do
            if keywords[word] then
                local start_pos = 1
                while true do
                    local s, e = line:find("%f[%a_]" .. word .. "%f[^%w_]", start_pos)
                    if not s then break end

                    local in_comment = comment_start and s >= comment_start
                    if not in_comment then
                        table.insert(tokens, {
                            line = line_index,
                            start_col = s - 1,
                            end_col = e,
                            r = keyword_color.r,
                            g = keyword_color.g,
                            b = keyword_color.b,
                            a = keyword_color.a
                        })
                    end

                    start_pos = e + 1
                end
            end
        end

        -- Numbers
        for s, e in line:gmatch("()%d+%.?%d*()") do
            local in_comment = comment_start and s >= comment_start
            if not in_comment then
                table.insert(tokens, {
                    line = line_index,
                    start_col = s - 1,
                    end_col = e - 1,
                    r = number_color.r,
                    g = number_color.g,
                    b = number_color.b,
                    a = number_color.a
                })
            end
        end
    end

    return tokens
end

-- C++ Syntax Highlighter (simplified)
function cpp_syntax_highlighter(text)
    local tokens = {}

    local keywords = {
        ["class"] = true, ["struct"] = true, ["enum"] = true,
        ["public"] = true, ["private"] = true, ["protected"] = true,
        ["virtual"] = true, ["static"] = true, ["const"] = true,
        ["if"] = true, ["else"] = true, ["for"] = true, ["while"] = true,
        ["return"] = true, ["break"] = true, ["continue"] = true,
        ["void"] = true, ["int"] = true, ["float"] = true, ["double"] = true,
        ["bool"] = true, ["char"] = true, ["auto"] = true,
        ["namespace"] = true, ["using"] = true, ["include"] = true
    }

    local keyword_color = {r = 86, g = 156, b = 214, a = 255}
    local string_color = {r = 206, g = 145, b = 120, a = 255}
    local comment_color = {r = 106, g = 153, b = 85, a = 255}
    local number_color = {r = 181, g = 206, b = 168, a = 255}

    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    for line_num, line in ipairs(lines) do
        local line_index = line_num - 1

        -- Comments
        local comment_start = line:find("//")
        if comment_start then
            table.insert(tokens, {
                line = line_index,
                start_col = comment_start - 1,
                end_col = #line,
                r = comment_color.r,
                g = comment_color.g,
                b = comment_color.b,
                a = comment_color.a
            })
        end

        -- Strings
        for s, e in line:gmatch("()[\"'].-()[\"']") do
            table.insert(tokens, {
                line = line_index,
                start_col = s - 1,
                end_col = e - 1,
                r = string_color.r,
                g = string_color.g,
                b = string_color.b,
                a = string_color.a
            })
        end

        -- Keywords
        for word in line:gmatch("[%a_][%w_]*") do
            if keywords[word] then
                local start_pos = 1
                while true do
                    local s, e = line:find("%f[%a_]" .. word .. "%f[^%w_]", start_pos)
                    if not s then break end

                    local in_comment = comment_start and s >= comment_start
                    if not in_comment then
                        table.insert(tokens, {
                            line = line_index,
                            start_col = s - 1,
                            end_col = e,
                            r = keyword_color.r,
                            g = keyword_color.g,
                            b = keyword_color.b,
                            a = keyword_color.a
                        })
                    end

                    start_pos = e + 1
                end
            end
        end
    end

    return tokens
end

-- JavaScript Syntax Highlighter (simplified)
function js_syntax_highlighter(text)
    local tokens = {}

    local keywords = {
        ["function"] = true, ["const"] = true, ["let"] = true, ["var"] = true,
        ["if"] = true, ["else"] = true, ["for"] = true, ["while"] = true,
        ["return"] = true, ["break"] = true, ["continue"] = true,
        ["class"] = true, ["extends"] = true, ["import"] = true, ["export"] = true,
        ["true"] = true, ["false"] = true, ["null"] = true, ["undefined"] = true
    }

    local keyword_color = {r = 86, g = 156, b = 214, a = 255}
    local string_color = {r = 206, g = 145, b = 120, a = 255}
    local comment_color = {r = 106, g = 153, b = 85, a = 255}

    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    for line_num, line in ipairs(lines) do
        local line_index = line_num - 1

        -- Comments
        local comment_start = line:find("//")
        if comment_start then
            table.insert(tokens, {
                line = line_index,
                start_col = comment_start - 1,
                end_col = #line,
                r = comment_color.r,
                g = comment_color.g,
                b = comment_color.b,
                a = comment_color.a
            })
        end

        -- Strings
        for s, e in line:gmatch("()[\"'`].-()[\"'`]") do
            table.insert(tokens, {
                line = line_index,
                start_col = s - 1,
                end_col = e - 1,
                r = string_color.r,
                g = string_color.g,
                b = string_color.b,
                a = string_color.a
            })
        end

        -- Keywords
        for word in line:gmatch("[%a_][%w_]*") do
            if keywords[word] then
                local start_pos = 1
                while true do
                    local s, e = line:find("%f[%a_]" .. word .. "%f[^%w_]", start_pos)
                    if not s then break end

                    local in_comment = comment_start and s >= comment_start
                    if not in_comment then
                        table.insert(tokens, {
                            line = line_index,
                            start_col = s - 1,
                            end_col = e,
                            r = keyword_color.r,
                            g = keyword_color.g,
                            b = keyword_color.b,
                            a = keyword_color.a
                        })
                    end

                    start_pos = e + 1
                end
            end
        end
    end

    return tokens
end
