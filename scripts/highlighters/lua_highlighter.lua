-- Lua Syntax Highlighter
-- Returns tokens with line, start_col, end_col, and color (r, g, b, a)

local function highlight(text)
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

return {
    highlight = highlight
}
