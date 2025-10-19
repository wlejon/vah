-- Markdown Lexer
-- Tokenizes markdown into a stream of tokens for incremental parsing
-- Designed for real-time streaming (can parse incomplete markdown)

local M = {}

-- Token types
M.TOKEN_TYPES = {
    -- Block-level tokens
    HEADING = "heading",              -- # Heading
    CODE_BLOCK_START = "code_block_start",  -- ```
    CODE_BLOCK_END = "code_block_end",      -- ```
    CODE_BLOCK_LINE = "code_block_line",    -- line inside code block
    LIST_ITEM = "list_item",          -- - item or * item
    TABLE_ROW = "table_row",          -- | cell | cell |
    BLANK_LINE = "blank_line",        -- empty line
    PARAGRAPH = "paragraph",          -- regular text line

    -- Inline tokens
    BOLD = "bold",                    -- **text** or __text__
    ITALIC = "italic",                -- *text* or _text_
    CODE = "code",                    -- `code`
    LINK = "link",                    -- [text](url)
    TEXT = "text",                    -- plain text

    EOF = "eof"
}

-- Create new lexer instance
function M.new(markdown)
    return {
        markdown = markdown or "",
        pos = 1,
        len = #(markdown or ""),
        line = 1,
        col = 1,
        in_code_block = false
    }
end

-- Current character
local function current(lexer)
    if lexer.pos > lexer.len then return nil end
    return lexer.markdown:sub(lexer.pos, lexer.pos)
end

-- Peek ahead n characters
local function peek(lexer, n)
    n = n or 1
    local end_pos = lexer.pos + n - 1
    if end_pos > lexer.len then return nil end
    return lexer.markdown:sub(lexer.pos, end_pos)
end

-- Peek at string
local function peek_str(lexer, str)
    local end_pos = lexer.pos + #str - 1
    if end_pos > lexer.len then return false end
    return lexer.markdown:sub(lexer.pos, end_pos) == str
end

-- Advance position
local function advance(lexer, n)
    n = n or 1
    for i = 1, n do
        local char = current(lexer)
        if not char then break end

        if char == '\n' then
            lexer.line = lexer.line + 1
            lexer.col = 1
        else
            lexer.col = lexer.col + 1
        end
        lexer.pos = lexer.pos + 1
    end
end

-- Read until end of line
local function read_line(lexer)
    local start = lexer.pos
    while current(lexer) and current(lexer) ~= '\n' do
        advance(lexer)
    end
    local line = lexer.markdown:sub(start, lexer.pos - 1)
    if current(lexer) == '\n' then
        advance(lexer) -- consume newline
    end
    return line
end

-- Check if at start of line
local function at_line_start(lexer)
    return lexer.col == 1 or lexer.pos == 1
end

-- Tokenize a block (line-level)
local function next_block_token(lexer)
    -- EOF
    if not current(lexer) then
        return {type = M.TOKEN_TYPES.EOF}
    end

    -- Code block delimiters (must be at start of line)
    if at_line_start(lexer) and peek_str(lexer, "```") then
        advance(lexer, 3)
        local lang = read_line(lexer):match("^%s*(.-)%s*$") -- trim

        if lexer.in_code_block then
            lexer.in_code_block = false
            return {type = M.TOKEN_TYPES.CODE_BLOCK_END}
        else
            lexer.in_code_block = true
            return {type = M.TOKEN_TYPES.CODE_BLOCK_START, lang = lang}
        end
    end

    -- Inside code block - everything is literal
    if lexer.in_code_block then
        local line = read_line(lexer)
        return {type = M.TOKEN_TYPES.CODE_BLOCK_LINE, text = line}
    end

    -- Blank line
    if at_line_start(lexer) and (current(lexer) == '\n' or peek_str(lexer, "\r\n")) then
        advance(lexer)
        return {type = M.TOKEN_TYPES.BLANK_LINE}
    end

    -- Heading (must be at start of line)
    if at_line_start(lexer) and current(lexer) == '#' then
        local level = 0
        while current(lexer) == '#' and level < 6 do
            level = level + 1
            advance(lexer)
        end

        -- Skip whitespace after #
        while current(lexer) and current(lexer):match('%s') and current(lexer) ~= '\n' do
            advance(lexer)
        end

        local text = read_line(lexer)
        return {type = M.TOKEN_TYPES.HEADING, level = level, text = text}
    end

    -- Table row (must start with |)
    if at_line_start(lexer) and current(lexer) == '|' then
        local line = read_line(lexer)
        -- Parse cells
        local cells = {}
        local is_separator = true

        -- Split by | and trim
        for cell in line:gmatch("[^|]+") do
            local trimmed = cell:match("^%s*(.-)%s*$")
            table.insert(cells, trimmed)
            -- Check if this is a separator row (contains only -, :, and whitespace)
            if not trimmed:match("^[%-%s:]*$") then
                is_separator = false
            end
        end

        return {
            type = M.TOKEN_TYPES.TABLE_ROW,
            cells = cells,
            is_separator = is_separator
        }
    end

    -- List item (must be at start of line)
    if at_line_start(lexer) and (current(lexer) == '-' or current(lexer) == '*') then
        local marker = current(lexer)
        local next_char = peek(lexer, 2)
        if next_char and next_char:sub(2,2):match('%s') then
            advance(lexer) -- consume marker
            -- Skip whitespace
            while current(lexer) and current(lexer):match('%s') and current(lexer) ~= '\n' do
                advance(lexer)
            end
            local text = read_line(lexer)
            return {type = M.TOKEN_TYPES.LIST_ITEM, text = text}
        end
    end

    -- Regular paragraph line
    local text = read_line(lexer)
    return {type = M.TOKEN_TYPES.PARAGRAPH, text = text}
end

-- Tokenize inline content (for paragraphs, headings, list items)
function M.tokenize_inline(text)
    local tokens = {}
    local pos = 1
    local len = #text

    while pos <= len do
        -- Bold: ** or __
        if text:sub(pos, pos + 1) == '**' or text:sub(pos, pos + 1) == '__' then
            local delimiter = text:sub(pos, pos + 1)
            local start = pos + 2
            local close = text:find(delimiter, start, true)

            if close then
                local content = text:sub(start, close - 1)
                table.insert(tokens, {type = M.TOKEN_TYPES.BOLD, text = content})
                pos = close + 2
            else
                -- No closing delimiter - treat as text
                table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = text:sub(pos, pos + 1)})
                pos = pos + 2
            end

        -- Italic: * or _
        elseif text:sub(pos, pos) == '*' or text:sub(pos, pos) == '_' then
            local delimiter = text:sub(pos, pos)
            -- Make sure it's not part of ** or __
            if text:sub(pos, pos + 1) ~= '**' and text:sub(pos, pos + 1) ~= '__' then
                local start = pos + 1
                local close = text:find(delimiter, start, true)

                if close then
                    local content = text:sub(start, close - 1)
                    table.insert(tokens, {type = M.TOKEN_TYPES.ITALIC, text = content})
                    pos = close + 1
                else
                    -- No closing delimiter - treat as text
                    table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = delimiter})
                    pos = pos + 1
                end
            else
                -- Part of ** or __, skip (will be handled by bold)
                table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = delimiter})
                pos = pos + 1
            end

        -- Inline code: `
        elseif text:sub(pos, pos) == '`' then
            local start = pos + 1
            local close = text:find('`', start, true)

            if close then
                local content = text:sub(start, close - 1)
                table.insert(tokens, {type = M.TOKEN_TYPES.CODE, text = content})
                pos = close + 1
            else
                -- No closing backtick - treat as text
                table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = '`'})
                pos = pos + 1
            end

        -- Link: [text](url)
        elseif text:sub(pos, pos) == '[' then
            local text_start = pos + 1
            local text_close = text:find(']', text_start, true)

            if text_close and text:sub(text_close + 1, text_close + 1) == '(' then
                local url_start = text_close + 2
                local url_close = text:find(')', url_start, true)

                if url_close then
                    local link_text = text:sub(text_start, text_close - 1)
                    local url = text:sub(url_start, url_close - 1)
                    table.insert(tokens, {type = M.TOKEN_TYPES.LINK, text = link_text, url = url})
                    pos = url_close + 1
                else
                    -- No closing paren - treat as text
                    table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = '['})
                    pos = pos + 1
                end
            else
                -- No link syntax - treat as text
                table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = '['})
                pos = pos + 1
            end

        -- Regular text
        else
            -- Read until next special character
            local text_start = pos
            while pos <= len do
                local char = text:sub(pos, pos)
                if char == '*' or char == '_' or char == '`' or char == '[' then
                    break
                end
                pos = pos + 1
            end

            if pos > text_start then
                table.insert(tokens, {type = M.TOKEN_TYPES.TEXT, text = text:sub(text_start, pos - 1)})
            end
        end
    end

    return tokens
end

-- Get next token
function M.next_token(lexer)
    return next_block_token(lexer)
end

-- Tokenize all blocks
function M.tokenize(markdown)
    local lexer = M.new(markdown)
    local tokens = {}

    while true do
        local token = M.next_token(lexer)
        table.insert(tokens, token)
        if token.type == M.TOKEN_TYPES.EOF then
            break
        end
    end

    return tokens
end

return M
