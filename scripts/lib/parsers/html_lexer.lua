-- HTML/RML Lexer
-- Tokenizes HTML/RML markup into a stream of tokens
-- Handles malformed HTML gracefully for web scraping

local M = {}

-- Token types
M.TOKEN_TYPES = {
    TAG_OPEN = "tag_open",           -- <div>
    TAG_CLOSE = "tag_close",         -- </div>
    TAG_SELF_CLOSE = "tag_self_close", -- <br/>
    TEXT = "text",                   -- text content
    COMMENT = "comment",             -- <!-- -->
    DOCTYPE = "doctype",             -- <!DOCTYPE>
    EOF = "eof"
}

-- Self-closing tags (HTML void elements)
local VOID_ELEMENTS = {
    area = true, base = true, br = true, col = true, embed = true,
    hr = true, img = true, input = true, link = true, meta = true,
    param = true, source = true, track = true, wbr = true
}

-- Create new lexer instance
function M.new(html)
    return {
        html = html or "",
        pos = 1,
        len = #(html or ""),
        line = 1,
        col = 1
    }
end

-- Current character
local function current(lexer)
    if lexer.pos > lexer.len then return nil end
    return lexer.html:sub(lexer.pos, lexer.pos)
end

-- Peek ahead n characters
local function peek(lexer, n)
    n = n or 1
    local end_pos = lexer.pos + n - 1
    if end_pos > lexer.len then return nil end
    return lexer.html:sub(lexer.pos, end_pos)
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

-- Skip whitespace
local function skip_whitespace(lexer)
    while current(lexer) and current(lexer):match('%s') do
        advance(lexer)
    end
end

-- Read until pattern matches
local function read_until(lexer, pattern)
    local start = lexer.pos
    while current(lexer) do
        if peek(lexer, #pattern) == pattern then
            break
        end
        advance(lexer)
    end
    return lexer.html:sub(start, lexer.pos - 1)
end

-- Read tag/attribute name
local function read_name(lexer)
    local start = lexer.pos
    while current(lexer) and current(lexer):match('[%w%-_:.]') do
        advance(lexer)
    end
    return lexer.html:sub(start, lexer.pos - 1)
end

-- Decode HTML entities
local function decode_entities(text)
    if not text then return "" end

    -- Common HTML5 named entities (expanded from 6 to 50+ most common)
    local named_entities = {
        -- Basic entities
        ['lt'] = '<',
        ['gt'] = '>',
        ['amp'] = '&',
        ['quot'] = '"',
        ['apos'] = "'",
        ['nbsp'] = ' ',

        -- Common punctuation and symbols
        ['mdash'] = '—',
        ['ndash'] = '–',
        ['copy'] = '©',
        ['reg'] = '®',
        ['trade'] = '™',
        ['hellip'] = '…',
        ['lsquo'] = ''',
        ['rsquo'] = ''',
        ['ldquo'] = '"',
        ['rdquo'] = '"',
        ['bull'] = '•',
        ['middot'] = '·',
        ['deg'] = '°',
        ['prime'] = '′',
        ['Prime'] = '″',
        ['sect'] = '§',
        ['para'] = '¶',
        ['dagger'] = '†',
        ['Dagger'] = '‡',

        -- Mathematical symbols
        ['times'] = '×',
        ['divide'] = '÷',
        ['plusmn'] = '±',
        ['minus'] = '−',
        ['sup1'] = '¹',
        ['sup2'] = '²',
        ['sup3'] = '³',
        ['frac14'] = '¼',
        ['frac12'] = '½',
        ['frac34'] = '¾',

        -- Currency
        ['cent'] = '¢',
        ['pound'] = '£',
        ['yen'] = '¥',
        ['euro'] = '€',
        ['curren'] = '¤',

        -- Accented characters (common)
        ['Agrave'] = 'À', ['Aacute'] = 'Á', ['Acirc'] = 'Â', ['Atilde'] = 'Ã',
        ['Auml'] = 'Ä', ['Aring'] = 'Å', ['AElig'] = 'Æ',
        ['Ccedil'] = 'Ç',
        ['Egrave'] = 'È', ['Eacute'] = 'É', ['Ecirc'] = 'Ê', ['Euml'] = 'Ë',
        ['Igrave'] = 'Ì', ['Iacute'] = 'Í', ['Icirc'] = 'Î', ['Iuml'] = 'Ï',
        ['Ntilde'] = 'Ñ',
        ['Ograve'] = 'Ò', ['Oacute'] = 'Ó', ['Ocirc'] = 'Ô', ['Otilde'] = 'Õ',
        ['Ouml'] = 'Ö', ['Oslash'] = 'Ø',
        ['Ugrave'] = 'Ù', ['Uacute'] = 'Ú', ['Ucirc'] = 'Û', ['Uuml'] = 'Ü',
        ['Yacute'] = 'Ý',
        ['agrave'] = 'à', ['aacute'] = 'á', ['acirc'] = 'â', ['atilde'] = 'ã',
        ['auml'] = 'ä', ['aring'] = 'å', ['aelig'] = 'æ',
        ['ccedil'] = 'ç',
        ['egrave'] = 'è', ['eacute'] = 'é', ['ecirc'] = 'ê', ['euml'] = 'ë',
        ['igrave'] = 'ì', ['iacute'] = 'í', ['icirc'] = 'î', ['iuml'] = 'ï',
        ['ntilde'] = 'ñ',
        ['ograve'] = 'ò', ['oacute'] = 'ó', ['ocirc'] = 'ô', ['otilde'] = 'õ',
        ['ouml'] = 'ö', ['oslash'] = 'ø',
        ['ugrave'] = 'ù', ['uacute'] = 'ú', ['ucirc'] = 'û', ['uuml'] = 'ü',
        ['yacute'] = 'ý', ['yuml'] = 'ÿ'
    }

    -- Replace named entities
    text = text:gsub('&([%w]+);', function(entity)
        return named_entities[entity] or ('&' .. entity .. ';')
    end)

    -- Numeric entities (decimal)
    text = text:gsub('&#(%d+);', function(n)
        local num = tonumber(n)
        if num and num < 256 then
            return string.char(num)
        end
        return '&#' .. n .. ';'
    end)

    -- Numeric entities (hexadecimal)
    text = text:gsub('&#x(%x+);', function(n)
        local num = tonumber(n, 16)
        if num and num < 256 then
            return string.char(num)
        end
        return '&#x' .. n .. ';'
    end)

    return text
end

-- Read attribute value (quoted or unquoted)
local function read_attribute_value(lexer)
    local quote = current(lexer)

    if quote == '"' or quote == "'" then
        advance(lexer)  -- skip opening quote
        local start = lexer.pos
        while current(lexer) and current(lexer) ~= quote do
            if current(lexer) == '\\' then
                advance(lexer)  -- skip escape char
                if current(lexer) then
                    advance(lexer)  -- skip escaped char
                end
            else
                advance(lexer)
            end
        end
        local value = lexer.html:sub(start, lexer.pos - 1)
        if current(lexer) == quote then
            advance(lexer)  -- skip closing quote
        end
        return decode_entities(value)
    else
        -- Unquoted value (rare but valid in HTML)
        local start = lexer.pos
        while current(lexer) and not current(lexer):match('[%s>]') do
            advance(lexer)
        end
        local value = lexer.html:sub(start, lexer.pos - 1)
        return decode_entities(value)
    end
end

-- Parse attributes from tag
local function read_attributes(lexer)
    local attributes = {}

    while current(lexer) do
        skip_whitespace(lexer)

        local char = current(lexer)
        if not char or char == '>' or char == '/' then
            break
        end

        -- Read attribute name
        local name = read_name(lexer)
        if name == '' then break end

        name = name:lower()

        skip_whitespace(lexer)

        -- Check for '='
        local value = true  -- Boolean attribute (e.g., <input checked>)
        if current(lexer) == '=' then
            advance(lexer)
            skip_whitespace(lexer)
            value = read_attribute_value(lexer)
        end

        attributes[name] = value
    end

    return attributes
end

-- Tokenize comment
local function lex_comment(lexer)
    local line_start = lexer.line
    local col_start = lexer.col

    advance(lexer, 4)  -- Skip <!--
    local content = read_until(lexer, '-->')
    if peek(lexer, 3) == '-->' then
        advance(lexer, 3)
    end

    return {
        type = M.TOKEN_TYPES.COMMENT,
        content = content,
        line = line_start,
        col = col_start
    }
end

-- Tokenize DOCTYPE
local function lex_doctype(lexer)
    local line_start = lexer.line
    local col_start = lexer.col

    advance(lexer, 2)  -- Skip <!
    local content = read_until(lexer, '>')
    if current(lexer) == '>' then
        advance(lexer)
    end

    return {
        type = M.TOKEN_TYPES.DOCTYPE,
        content = content,
        line = line_start,
        col = col_start
    }
end

-- Tokenize tag
local function lex_tag(lexer)
    local line_start = lexer.line
    local col_start = lexer.col

    advance(lexer)  -- Skip <

    skip_whitespace(lexer)

    -- Check if closing tag
    local is_closing = current(lexer) == '/'
    if is_closing then
        advance(lexer)
        skip_whitespace(lexer)
    end

    -- Read tag name
    local tag_name = read_name(lexer):lower()

    if tag_name == '' then
        -- Malformed tag, treat as text
        return {
            type = M.TOKEN_TYPES.TEXT,
            content = '<',
            line = line_start,
            col = col_start
        }
    end

    skip_whitespace(lexer)

    -- Read attributes (only for opening tags)
    local attributes = {}
    if not is_closing then
        attributes = read_attributes(lexer)
    end

    skip_whitespace(lexer)

    -- Check for self-closing
    local is_self_closing = current(lexer) == '/'
    if is_self_closing then
        advance(lexer)
        skip_whitespace(lexer)
    end

    -- Skip closing >
    if current(lexer) == '>' then
        advance(lexer)
    end

    -- Determine token type
    if is_closing then
        return {
            type = M.TOKEN_TYPES.TAG_CLOSE,
            tag = tag_name,
            line = line_start,
            col = col_start
        }
    elseif is_self_closing or VOID_ELEMENTS[tag_name] then
        return {
            type = M.TOKEN_TYPES.TAG_SELF_CLOSE,
            tag = tag_name,
            attributes = attributes,
            line = line_start,
            col = col_start
        }
    else
        return {
            type = M.TOKEN_TYPES.TAG_OPEN,
            tag = tag_name,
            attributes = attributes,
            line = line_start,
            col = col_start
        }
    end
end

-- Tokenize text content
local function lex_text(lexer)
    local line_start = lexer.line
    local col_start = lexer.col

    local start = lexer.pos
    while current(lexer) and current(lexer) ~= '<' do
        advance(lexer)
    end

    local text = lexer.html:sub(start, lexer.pos - 1)
    text = decode_entities(text)

    return {
        type = M.TOKEN_TYPES.TEXT,
        content = text,
        line = line_start,
        col = col_start
    }
end

-- Get next token
function M.next_token(lexer)
    if lexer.pos > lexer.len then
        return {
            type = M.TOKEN_TYPES.EOF,
            line = lexer.line,
            col = lexer.col
        }
    end

    local char = current(lexer)

    if char == '<' then
        local next2 = peek(lexer, 2)
        local next4 = peek(lexer, 4)

        if next4 == '<!--' then
            return lex_comment(lexer)
        elseif next2 and next2:sub(1, 2) == '<!' then
            return lex_doctype(lexer)
        else
            return lex_tag(lexer)
        end
    else
        return lex_text(lexer)
    end
end

-- Tokenize entire document
function M.tokenize(html)
    local lexer = M.new(html)
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

-- Helper: Print tokens for debugging
function M.print_tokens(tokens)
    for i, token in ipairs(tokens) do
        if token.type == M.TOKEN_TYPES.TAG_OPEN then
            local attrs = {}
            for k, v in pairs(token.attributes or {}) do
                table.insert(attrs, string.format('%s=%q', k, v))
            end
            print(string.format("[%d:%d] TAG_OPEN: <%s %s>",
                token.line, token.col, token.tag, table.concat(attrs, ' ')))
        elseif token.type == M.TOKEN_TYPES.TAG_CLOSE then
            print(string.format("[%d:%d] TAG_CLOSE: </%s>",
                token.line, token.col, token.tag))
        elseif token.type == M.TOKEN_TYPES.TAG_SELF_CLOSE then
            local attrs = {}
            for k, v in pairs(token.attributes or {}) do
                table.insert(attrs, string.format('%s=%q', k, v))
            end
            print(string.format("[%d:%d] TAG_SELF_CLOSE: <%s %s/>",
                token.line, token.col, token.tag, table.concat(attrs, ' ')))
        elseif token.type == M.TOKEN_TYPES.TEXT then
            local preview = token.content:sub(1, 50):gsub('\n', '\\n')
            if #token.content > 50 then preview = preview .. "..." end
            print(string.format("[%d:%d] TEXT: %q",
                token.line, token.col, preview))
        elseif token.type == M.TOKEN_TYPES.COMMENT then
            local preview = token.content:sub(1, 30)
            if #token.content > 30 then preview = preview .. "..." end
            print(string.format("[%d:%d] COMMENT: <!-- %s -->",
                token.line, token.col, preview))
        elseif token.type == M.TOKEN_TYPES.DOCTYPE then
            print(string.format("[%d:%d] DOCTYPE: <!%s>",
                token.line, token.col, token.content))
        elseif token.type == M.TOKEN_TYPES.EOF then
            print(string.format("[%d:%d] EOF", token.line, token.col))
        end
    end
end

return M
