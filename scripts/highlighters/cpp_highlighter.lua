-- C++ Syntax Highlighter
-- Returns tokens with line, start_col, end_col, and color (r, g, b, a)

local function highlight(text)
    local tokens = {}

    local keywords = {
        ["class"] = true, ["struct"] = true, ["enum"] = true,
        ["public"] = true, ["private"] = true, ["protected"] = true,
        ["virtual"] = true, ["static"] = true, ["const"] = true, ["constexpr"] = true,
        ["if"] = true, ["else"] = true, ["for"] = true, ["while"] = true, ["do"] = true,
        ["return"] = true, ["break"] = true, ["continue"] = true,
        ["void"] = true, ["int"] = true, ["float"] = true, ["double"] = true,
        ["bool"] = true, ["char"] = true, ["auto"] = true, ["long"] = true, ["short"] = true,
        ["unsigned"] = true, ["signed"] = true,
        ["namespace"] = true, ["using"] = true, ["typedef"] = true,
        ["template"] = true, ["typename"] = true,
        ["new"] = true, ["delete"] = true,
        ["this"] = true, ["nullptr"] = true,
        ["true"] = true, ["false"] = true,
        ["switch"] = true, ["case"] = true, ["default"] = true,
        ["try"] = true, ["catch"] = true, ["throw"] = true,
        ["extern"] = true, ["inline"] = true, ["explicit"] = true,
        ["friend"] = true, ["mutable"] = true, ["operator"] = true,
        ["sizeof"] = true, ["alignof"] = true, ["decltype"] = true
    }

    local preprocessor_color = {r = 155, g = 155, b = 155, a = 255}
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

        -- Preprocessor directives (#include, #define, etc)
        local preprocessor_start = line:find("^%s*#")
        if preprocessor_start then
            table.insert(tokens, {
                line = line_index,
                start_col = line:find("#") - 1,
                end_col = #line,
                r = preprocessor_color.r,
                g = preprocessor_color.g,
                b = preprocessor_color.b,
                a = preprocessor_color.a
            })
        end

        -- Single-line comments
        local comment_start = line:find("//")
        if comment_start and not preprocessor_start then
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

        -- Strings (only if not in comment or preprocessor)
        if not comment_start and not preprocessor_start then
            local pos = 1
            while true do
                local s = line:find('["]', pos)
                if not s then break end

                local e = s
                repeat
                    e = line:find('["]', e + 1)
                    if not e then break end
                until line:sub(e-1, e-1) ~= '\\'

                if e then
                    table.insert(tokens, {
                        line = line_index,
                        start_col = s - 1,
                        end_col = e,
                        r = string_color.r,
                        g = string_color.g,
                        b = string_color.b,
                        a = string_color.a
                    })
                    pos = e + 1
                else
                    break
                end
            end
        end

        -- Keywords (only if not in comment or preprocessor)
        if not comment_start and not preprocessor_start then
            for word in line:gmatch("[%a_][%w_]*") do
                if keywords[word] then
                    local start_pos = 1
                    while true do
                        local s, e = line:find("%f[%a_]" .. word .. "%f[^%w_]", start_pos)
                        if not s then break end

                        table.insert(tokens, {
                            line = line_index,
                            start_col = s - 1,
                            end_col = e,
                            r = keyword_color.r,
                            g = keyword_color.g,
                            b = keyword_color.b,
                            a = keyword_color.a
                        })

                        start_pos = e + 1
                    end
                end
            end

            -- Numbers
            for s, e in line:gmatch("()%d+%.?%d*[fFlLuU]*()") do
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
