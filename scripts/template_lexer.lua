-- Template Lexer
-- Character-by-character tokenization of template strings

local M = {}

-- Token types
M.TOKEN_TYPES = {
    TEXT = "TEXT",
    OPEN_BRACE = "OPEN_BRACE",      -- {
    CLOSE_BRACE = "CLOSE_BRACE",    -- }
    HASH = "HASH",                  -- #
    SLASH = "SLASH",                -- /
    IDENTIFIER = "IDENTIFIER",      -- variable name or keyword
    DOT = "DOT",                    -- .
    WHITESPACE = "WHITESPACE",
    EOF = "EOF"
}

-- Lexer state
local function create_lexer(input)
    return {
        input = input,
        pos = 1,
        len = #input
    }
end

-- Peek current character without consuming
local function peek(lexer)
    if lexer.pos > lexer.len then
        return nil
    end
    return lexer.input:sub(lexer.pos, lexer.pos)
end

-- Consume and return current character
local function advance(lexer)
    if lexer.pos > lexer.len then
        return nil
    end
    local ch = lexer.input:sub(lexer.pos, lexer.pos)
    lexer.pos = lexer.pos + 1
    return ch
end

-- Check if character is whitespace
local function is_whitespace(ch)
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r'
end

-- Check if character can start an identifier
local function is_alpha(ch)
    if not ch then return false end
    local byte = ch:byte()
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or ch == '_' or ch == '@'
end

-- Check if character can be in an identifier
local function is_alnum(ch)
    if not ch then return false end
    local byte = ch:byte()
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or
           (byte >= 48 and byte <= 57) or ch == '_' or ch == '@'
end

-- Scan identifier
local function scan_identifier(lexer)
    local start = lexer.pos
    while is_alnum(peek(lexer)) do
        advance(lexer)
    end
    return lexer.input:sub(start, lexer.pos - 1)
end

-- Scan text (everything until we hit {{)
local function scan_text(lexer)
    local start = lexer.pos

    while lexer.pos <= lexer.len do
        local ch = peek(lexer)
        if ch == '{' then
            -- Check if it's {{
            if lexer.pos + 1 <= lexer.len and lexer.input:sub(lexer.pos + 1, lexer.pos + 1) == '{' then
                break
            end
        end
        advance(lexer)
    end

    return lexer.input:sub(start, lexer.pos - 1)
end

-- Main tokenization function
function M.tokenize(input)
    if not input or input == "" then
        return {{type = M.TOKEN_TYPES.EOF}}
    end

    local lexer = create_lexer(input)
    local tokens = {}
    local in_directive = false

    while lexer.pos <= lexer.len do
        local ch = peek(lexer)

        if not in_directive then
            -- Outside {{ }}, scan for text or directive start
            if ch == '{' and lexer.pos + 1 <= lexer.len and
               lexer.input:sub(lexer.pos + 1, lexer.pos + 1) == '{' then
                -- Found {{
                advance(lexer)  -- consume first {
                advance(lexer)  -- consume second {
                table.insert(tokens, {type = M.TOKEN_TYPES.OPEN_BRACE})
                in_directive = true
            else
                -- Scan text until we hit {{
                local text = scan_text(lexer)
                if text ~= "" then
                    table.insert(tokens, {
                        type = M.TOKEN_TYPES.TEXT,
                        value = text
                    })
                end
            end
        else
            -- Inside {{ }}, tokenize directive content
            if ch == '}' and lexer.pos + 1 <= lexer.len and
               lexer.input:sub(lexer.pos + 1, lexer.pos + 1) == '}' then
                -- Found }}
                advance(lexer)  -- consume first }
                advance(lexer)  -- consume second }
                table.insert(tokens, {type = M.TOKEN_TYPES.CLOSE_BRACE})
                in_directive = false

            elseif is_whitespace(ch) then
                -- Skip whitespace in directives
                advance(lexer)

            elseif ch == '#' then
                advance(lexer)
                table.insert(tokens, {type = M.TOKEN_TYPES.HASH})

            elseif ch == '/' then
                advance(lexer)
                table.insert(tokens, {type = M.TOKEN_TYPES.SLASH})

            elseif ch == '.' then
                advance(lexer)
                table.insert(tokens, {type = M.TOKEN_TYPES.DOT})

            elseif is_alpha(ch) then
                local ident = scan_identifier(lexer)
                table.insert(tokens, {
                    type = M.TOKEN_TYPES.IDENTIFIER,
                    value = ident
                })

            else
                -- Unknown character, skip it
                advance(lexer)
            end
        end
    end

    table.insert(tokens, {type = M.TOKEN_TYPES.EOF})
    return tokens
end

return M
