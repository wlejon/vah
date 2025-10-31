-- Markdown Parser
-- Converts markdown tokens to RML markup
-- Designed for incremental/streaming parsing

local lexer = require("lib.parsers.markdown_lexer")
local M = {}

-- Verify lexer loaded correctly
if not lexer or not lexer.TOKEN_TYPES then
    error("markdown_lexer not loaded correctly")
end

-- Escape HTML/RML special characters
local function escape_html(text)
    if not text then return "" end
    local result = text:gsub("&", "&amp;")
    result = result:gsub("<", "&lt;")
    result = result:gsub(">", "&gt;")
    result = result:gsub('"', "&quot;")
    result = result:gsub("'", "&#39;")
    return result
end

-- Convert inline tokens to RML
local function inline_tokens_to_rml(tokens)
    local parts = {}

    for _, token in ipairs(tokens) do
        if token.type == lexer.TOKEN_TYPES.TEXT then
            local escaped = escape_html(token.text)
            table.insert(parts, escaped)

        elseif token.type == lexer.TOKEN_TYPES.BOLD then
            table.insert(parts, "<strong>")
            table.insert(parts, escape_html(token.text))
            table.insert(parts, "</strong>")

        elseif token.type == lexer.TOKEN_TYPES.ITALIC then
            table.insert(parts, "<em>")
            table.insert(parts, escape_html(token.text))
            table.insert(parts, "</em>")

        elseif token.type == lexer.TOKEN_TYPES.CODE then
            table.insert(parts, '<span class="inline-code">')
            table.insert(parts, escape_html(token.text))
            table.insert(parts, "</span>")

        elseif token.type == lexer.TOKEN_TYPES.LINK then
            table.insert(parts, '<a href="')
            table.insert(parts, escape_html(token.url))
            table.insert(parts, '">')
            table.insert(parts, escape_html(token.text))
            table.insert(parts, "</a>")
        end
    end

    return table.concat(parts)
end

-- Convert inline text to RML
local function inline_to_rml(text)
    if not text or text == "" then
        return ""
    end

    local inline_tokens = lexer.tokenize_inline(text)
    return inline_tokens_to_rml(inline_tokens)
end

-- Render a table to RML
local function render_table(rml_parts, rows, has_header)
    if #rows == 0 then
        return
    end

    table.insert(rml_parts, '<table class="md-table">')

    -- If has_header, first row is the header
    if has_header and #rows > 0 then
        table.insert(rml_parts, "<thead><tr>")
        for _, cell in ipairs(rows[1]) do
            table.insert(rml_parts, "<th>")
            table.insert(rml_parts, inline_to_rml(cell))
            table.insert(rml_parts, "</th>")
        end
        table.insert(rml_parts, "</tr></thead>")

        -- Remaining rows are body
        if #rows > 1 then
            table.insert(rml_parts, "<tbody>")
            for i = 2, #rows do
                table.insert(rml_parts, "<tr>")
                for _, cell in ipairs(rows[i]) do
                    table.insert(rml_parts, "<td>")
                    table.insert(rml_parts, inline_to_rml(cell))
                    table.insert(rml_parts, "</td>")
                end
                table.insert(rml_parts, "</tr>")
            end
            table.insert(rml_parts, "</tbody>")
        end
    else
        -- No header, all rows are body
        table.insert(rml_parts, "<tbody>")
        for _, row in ipairs(rows) do
            table.insert(rml_parts, "<tr>")
            for _, cell in ipairs(row) do
                table.insert(rml_parts, "<td>")
                table.insert(rml_parts, inline_to_rml(cell))
                table.insert(rml_parts, "</td>")
            end
            table.insert(rml_parts, "</tr>")
        end
        table.insert(rml_parts, "</tbody>")
    end

    table.insert(rml_parts, "</table>")
end

-- Parse markdown to RML
-- @param markdown The markdown text
-- @return RML string, warnings table
function M.to_rml(markdown)
    if not markdown or markdown == "" then
        return "", {}
    end

    local tokens = lexer.tokenize(markdown)
    local rml_parts = {}
    local warnings = {}
    local in_list = false
    local in_code_block = false
    local code_block_lines = {}
    local code_block_lang = ""
    local in_table = false
    local table_rows = {}
    local table_has_header = false

    for i, token in ipairs(tokens) do
        if token.type == lexer.TOKEN_TYPES.EOF then
            break

        elseif token.type == lexer.TOKEN_TYPES.CODE_BLOCK_START then
            in_code_block = true
            code_block_lang = token.lang or ""
            code_block_lines = {}

        elseif token.type == lexer.TOKEN_TYPES.CODE_BLOCK_END then
            in_code_block = false
            -- Close any open list
            if in_list then
                table.insert(rml_parts, "</ul>")
                in_list = false
            end

            -- Output code block
            if code_block_lang ~= "" then
                table.insert(rml_parts, '<pre class="code-block ' .. escape_html(code_block_lang) .. '"><code>')
            else
                table.insert(rml_parts, '<pre class="code-block"><code>')
            end
            table.insert(rml_parts, escape_html(table.concat(code_block_lines, "\n")))
            table.insert(rml_parts, "</code></pre>")

        elseif token.type == lexer.TOKEN_TYPES.CODE_BLOCK_LINE then
            table.insert(code_block_lines, token.text)

        elseif token.type == lexer.TOKEN_TYPES.HEADING then
            -- Close any open list
            if in_list then
                table.insert(rml_parts, "</ul>")
                in_list = false
            end

            local tag = "h" .. token.level
            table.insert(rml_parts, "<" .. tag .. ">")
            table.insert(rml_parts, inline_to_rml(token.text))
            table.insert(rml_parts, "</" .. tag .. ">")

        elseif token.type == lexer.TOKEN_TYPES.TABLE_ROW then
            -- Start table if not in one
            if not in_table then
                in_table = true
                table_rows = {}
                table_has_header = false
            end

            -- Check if this is a separator row
            if token.is_separator then
                -- Mark that we have a header (rows before separator are headers)
                table_has_header = true
            else
                -- Regular table row
                table.insert(table_rows, token.cells)
            end

        elseif token.type == lexer.TOKEN_TYPES.LIST_ITEM then
            -- Close table if we were in one
            if in_table then
                render_table(rml_parts, table_rows, table_has_header)
                in_table = false
                table_rows = {}
            end

            if not in_list then
                table.insert(rml_parts, "<ul>")
                in_list = true
            end

            table.insert(rml_parts, "<li>")
            table.insert(rml_parts, inline_to_rml(token.text))
            table.insert(rml_parts, "</li>")

        elseif token.type == lexer.TOKEN_TYPES.BLANK_LINE then
            -- Close table if we were in one
            if in_table then
                render_table(rml_parts, table_rows, table_has_header)
                in_table = false
                table_rows = {}
            end

            -- Close list on blank line
            if in_list then
                table.insert(rml_parts, "</ul>")
                in_list = false
            end

        elseif token.type == lexer.TOKEN_TYPES.PARAGRAPH then
            -- Close any open list
            if in_list then
                table.insert(rml_parts, "</ul>")
                in_list = false
            end

            -- Don't create empty paragraphs
            if token.text and token.text ~= "" then
                table.insert(rml_parts, "<p>")
                table.insert(rml_parts, inline_to_rml(token.text))
                table.insert(rml_parts, "</p>")
            end
        end
    end

    -- Close any open table at end
    if in_table and #table_rows > 0 then
        render_table(rml_parts, table_rows, table_has_header)
    end

    -- Close any open list at end
    if in_list then
        table.insert(rml_parts, "</ul>")
    end

    -- Close incomplete code block
    if in_code_block and #code_block_lines > 0 then
        table.insert(warnings, {
            type = "unclosed_code_block",
            message = "Code block not closed at end of file"
        })
        if code_block_lang ~= "" then
            table.insert(rml_parts, '<pre class="code-block ' .. escape_html(code_block_lang) .. '"><code>')
        else
            table.insert(rml_parts, '<pre class="code-block"><code>')
        end
        table.insert(rml_parts, escape_html(table.concat(code_block_lines, "\n")))
        table.insert(rml_parts, "</code></pre>")
    end

    return table.concat(rml_parts, "\n"), warnings
end

return M
