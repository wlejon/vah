-- RCSS (CSS) Syntax Highlighter
-- Returns tokens with line, start_col, end_col, and color (r, g, b, a)

local function highlight(text)
    local tokens = {}

    local selector_color = {r = 215, g = 186, b = 125, a = 255}
    local property_color = {r = 156, g = 220, b = 254, a = 255}
    local value_color = {r = 206, g = 145, b = 120, a = 255}
    local comment_color = {r = 106, g = 153, b = 85, a = 255}
    local number_color = {r = 181, g = 206, b = 168, a = 255}

    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    for line_num, line in ipairs(lines) do
        local line_index = line_num - 1

        -- Comments /* */
        local comment_start, comment_end = line:find("/%*.-%*/")
        if comment_start then
            table.insert(tokens, {
                line = line_index,
                start_col = comment_start - 1,
                end_col = comment_end,
                r = comment_color.r,
                g = comment_color.g,
                b = comment_color.b,
                a = comment_color.a
            })
        end

        -- Skip if entire line is comment
        if comment_start and comment_start == 1 and comment_end == #line then
            goto continue
        end

        -- Properties (word followed by colon)
        for prop_start, prop_name, prop_end in line:gmatch("()([%a%-]+)()%s*:") do
            if not (comment_start and prop_start >= comment_start) then
                table.insert(tokens, {
                    line = line_index,
                    start_col = prop_start - 1,
                    end_col = prop_end - 1,
                    r = property_color.r,
                    g = property_color.g,
                    b = property_color.b,
                    a = property_color.a
                })
            end
        end

        -- Numbers with units
        for s, num, e in line:gmatch("()(%d+%.?%d*)([px%%emdptrch]*)") do
            if not (comment_start and s >= comment_start) then
                table.insert(tokens, {
                    line = line_index,
                    start_col = s - 1,
                    end_col = s + #num + #e - 1,
                    r = number_color.r,
                    g = number_color.g,
                    b = number_color.b,
                    a = number_color.a
                })
            end
        end

        -- Color values (#hex)
        for s, e in line:gmatch("()(#[0-9a-fA-F]+)()") do
            if not (comment_start and s >= comment_start) then
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

        ::continue::
    end

    return tokens
end

return {
    highlight = highlight
}
