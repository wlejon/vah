-- Markdown Syntax Highlighter
-- Returns tokens with line, start_col, end_col, and color (r, g, b, a)

local function highlight(text)
    local tokens = {}

    -- Color scheme
    local heading_color = {r = 86, g = 156, b = 214, a = 255}      -- Blue for headings
    local bold_color = {r = 220, g = 220, b = 170, a = 255}        -- Yellow for bold
    local italic_color = {r = 206, g = 145, b = 120, a = 255}      -- Orange for italic
    local code_color = {r = 206, g = 145, b = 120, a = 255}        -- Orange for inline code
    local code_block_color = {r = 181, g = 206, b = 168, a = 255}  -- Green for code blocks
    local link_color = {r = 78, g = 201, b = 176, a = 255}         -- Teal for links
    local quote_color = {r = 106, g = 153, b = 85, a = 255}        -- Green for blockquotes
    local list_color = {r = 197, g = 134, b = 192, a = 255}        -- Purple for list markers
    local hr_color = {r = 128, g = 128, b = 128, a = 255}          -- Gray for horizontal rules

    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    local in_code_block = false
    local code_block_fence = nil

    for line_num, line in ipairs(lines) do
        local line_index = line_num - 1

        -- Code block fences (``` or ~~~)
        local fence_match = line:match("^%s*(```+|~~~+)")
        if fence_match then
            if not in_code_block then
                in_code_block = true
                code_block_fence = fence_match
            elseif fence_match:sub(1, 3) == code_block_fence:sub(1, 3) then
                in_code_block = false
                code_block_fence = nil
            end

            table.insert(tokens, {
                line = line_index,
                start_col = 0,
                end_col = #line,
                r = code_block_color.r,
                g = code_block_color.g,
                b = code_block_color.b,
                a = code_block_color.a
            })
            goto continue
        end

        -- Inside code block
        if in_code_block then
            table.insert(tokens, {
                line = line_index,
                start_col = 0,
                end_col = #line,
                r = code_block_color.r,
                g = code_block_color.g,
                b = code_block_color.b,
                a = code_block_color.a
            })
            goto continue
        end

        -- Headings (# ## ### etc)
        local heading_match = line:match("^%s*(#+)%s")
        if heading_match then
            local start_pos = line:find("#")
            table.insert(tokens, {
                line = line_index,
                start_col = start_pos - 1,
                end_col = #line,
                r = heading_color.r,
                g = heading_color.g,
                b = heading_color.b,
                a = heading_color.a
            })
            goto continue
        end

        -- Alternative heading styles (underline with === or ---)
        if line:match("^=+%s*$") or line:match("^%-+%s*$") then
            table.insert(tokens, {
                line = line_index,
                start_col = 0,
                end_col = #line,
                r = heading_color.r,
                g = heading_color.g,
                b = heading_color.b,
                a = heading_color.a
            })
            goto continue
        end

        -- Horizontal rules (---, ***, ___)
        if line:match("^%s*%-%-%-") or line:match("^%s*%*%*%*") or line:match("^%s*___") then
            table.insert(tokens, {
                line = line_index,
                start_col = 0,
                end_col = #line,
                r = hr_color.r,
                g = hr_color.g,
                b = hr_color.b,
                a = hr_color.a
            })
            goto continue
        end

        -- Blockquotes (> at start of line)
        local quote_match = line:match("^%s*>")
        if quote_match then
            local start_pos = line:find(">")
            table.insert(tokens, {
                line = line_index,
                start_col = start_pos - 1,
                end_col = start_pos,
                r = quote_color.r,
                g = quote_color.g,
                b = quote_color.b,
                a = quote_color.a
            })
        end

        -- Unordered list markers (-, *, +)
        local list_marker = line:match("^%s*([%-%*%+])%s")
        if list_marker then
            local start_pos = line:find("[%-%*%+]")
            table.insert(tokens, {
                line = line_index,
                start_col = start_pos - 1,
                end_col = start_pos,
                r = list_color.r,
                g = list_color.g,
                b = list_color.b,
                a = list_color.a
            })
        end

        -- Ordered list markers (1. 2. etc)
        local ordered_list = line:match("^%s*%d+%.")
        if ordered_list then
            local start_pos = line:find("%d")
            local end_pos = line:find("%.", start_pos)
            table.insert(tokens, {
                line = line_index,
                start_col = start_pos - 1,
                end_col = end_pos,
                r = list_color.r,
                g = list_color.g,
                b = list_color.b,
                a = list_color.a
            })
        end

        -- Inline code (`code`)
        local pos = 1
        while true do
            local s, e = line:find("`[^`]+`", pos)
            if not s then break end

            table.insert(tokens, {
                line = line_index,
                start_col = s - 1,
                end_col = e,
                r = code_color.r,
                g = code_color.g,
                b = code_color.b,
                a = code_color.a
            })
            pos = e + 1
        end

        -- Bold (**text** or __text__)
        pos = 1
        while true do
            local s, e = line:find("%*%*[^%*]+%*%*", pos)
            if not s then
                s, e = line:find("__[^_]+__", pos)
            end
            if not s then break end

            table.insert(tokens, {
                line = line_index,
                start_col = s - 1,
                end_col = e,
                r = bold_color.r,
                g = bold_color.g,
                b = bold_color.b,
                a = bold_color.a
            })
            pos = e + 1
        end

        -- Italic (*text* or _text_)
        pos = 1
        while true do
            local s, e = line:find("%*[^%*]+%*", pos)
            if s then
                -- Check it's not part of **
                local before = s > 1 and line:sub(s-1, s-1) or ""
                local after = e <= #line and line:sub(e+1, e+1) or ""
                if before ~= "*" and after ~= "*" then
                    table.insert(tokens, {
                        line = line_index,
                        start_col = s - 1,
                        end_col = e,
                        r = italic_color.r,
                        g = italic_color.g,
                        b = italic_color.b,
                        a = italic_color.a
                    })
                end
                pos = e + 1
            else
                s, e = line:find("_[^_]+_", pos)
                if s then
                    -- Check it's not part of __
                    local before = s > 1 and line:sub(s-1, s-1) or ""
                    local after = e <= #line and line:sub(e+1, e+1) or ""
                    if before ~= "_" and after ~= "_" then
                        table.insert(tokens, {
                            line = line_index,
                            start_col = s - 1,
                            end_col = e,
                            r = italic_color.r,
                            g = italic_color.g,
                            b = italic_color.b,
                            a = italic_color.a
                        })
                    end
                    pos = e + 1
                else
                    break
                end
            end
        end

        -- Links [text](url) and images ![alt](url)
        pos = 1
        while true do
            local s, e = line:find("!?%[[^%]]+%]%([^%)]+%)", pos)
            if not s then break end

            table.insert(tokens, {
                line = line_index,
                start_col = s - 1,
                end_col = e,
                r = link_color.r,
                g = link_color.g,
                b = link_color.b,
                a = link_color.a
            })
            pos = e + 1
        end

        ::continue::
    end

    return tokens
end

return {
    highlight = highlight
}
