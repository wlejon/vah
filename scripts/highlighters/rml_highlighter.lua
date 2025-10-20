-- RML (XML/HTML) Syntax Highlighter
-- Returns tokens with line, start_col, end_col, and color (r, g, b, a)

local function highlight(text)
    local tokens = {}

    local tag_color = {r = 86, g = 156, b = 214, a = 255}
    local attribute_color = {r = 156, g = 220, b = 254, a = 255}
    local string_color = {r = 206, g = 145, b = 120, a = 255}
    local comment_color = {r = 106, g = 153, b = 85, a = 255}

    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    for line_num, line in ipairs(lines) do
        local line_index = line_num - 1

        -- Comments <!-- -->
        local comment_start, comment_end = line:find("<!%-%-.*%-%->")
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

        -- Tags < >
        local pos = 1
        while true do
            local tag_start = line:find("<", pos)
            if not tag_start then break end

            local tag_end = line:find(">", tag_start)
            if not tag_end then break end

            -- Skip if in comment
            if not (comment_start and tag_start >= comment_start and tag_start <= comment_end) then
                -- Highlight tag brackets
                table.insert(tokens, {
                    line = line_index,
                    start_col = tag_start - 1,
                    end_col = tag_start,
                    r = tag_color.r,
                    g = tag_color.g,
                    b = tag_color.b,
                    a = tag_color.a
                })

                table.insert(tokens, {
                    line = line_index,
                    start_col = tag_end - 1,
                    end_col = tag_end,
                    r = tag_color.r,
                    g = tag_color.g,
                    b = tag_color.b,
                    a = tag_color.a
                })

                -- Highlight tag name
                local tag_content = line:sub(tag_start + 1, tag_end - 1)
                local tag_name_end = tag_content:find("[%s/>]") or (#tag_content + 1)
                local tag_name = tag_content:sub(1, tag_name_end - 1)
                if #tag_name > 0 then
                    table.insert(tokens, {
                        line = line_index,
                        start_col = tag_start,
                        end_col = tag_start + #tag_name,
                        r = tag_color.r,
                        g = tag_color.g,
                        b = tag_color.b,
                        a = tag_color.a
                    })
                end

                -- Highlight attributes
                for attr in tag_content:gmatch("[%a_:][%w_:%-]*") do
                    if attr ~= tag_name then
                        local attr_start = tag_start + tag_content:find(attr, 1, true)
                        table.insert(tokens, {
                            line = line_index,
                            start_col = attr_start,
                            end_col = attr_start + #attr,
                            r = attribute_color.r,
                            g = attribute_color.g,
                            b = attribute_color.b,
                            a = attribute_color.a
                        })
                    end
                end

                -- Highlight attribute values (strings)
                for s, e in tag_content:gmatch("()[\"'].-()[\"']") do
                    table.insert(tokens, {
                        line = line_index,
                        start_col = tag_start + s - 1,
                        end_col = tag_start + e - 1,
                        r = string_color.r,
                        g = string_color.g,
                        b = string_color.b,
                        a = string_color.a
                    })
                end
            end

            pos = tag_end + 1
        end
    end

    return tokens
end

return {
    highlight = highlight
}
