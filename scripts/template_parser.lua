-- Template Parser
-- Builds AST from token stream

local lexer = require("template_lexer")
local M = {}

-- AST Node types
M.NODE_TYPES = {
    ROOT = "ROOT",
    TEXT = "TEXT",
    VARIABLE = "VARIABLE",
    IF = "IF",
    EACH = "EACH"
}

-- Parser state
local function create_parser(tokens)
    return {
        tokens = tokens,
        pos = 1
    }
end

-- Peek current token
local function peek(parser)
    if parser.pos > #parser.tokens then
        return parser.tokens[#parser.tokens]  -- EOF
    end
    return parser.tokens[parser.pos]
end

-- Consume current token and advance
local function advance(parser)
    local token = parser.tokens[parser.pos]
    if parser.pos < #parser.tokens then
        parser.pos = parser.pos + 1
    end
    return token
end

-- Expect a specific token type
local function expect(parser, token_type)
    local token = peek(parser)
    if token.type ~= token_type then
        error("Expected " .. token_type .. " but got " .. token.type)
    end
    return advance(parser)
end

-- Parse variable path (e.g., "user.name.first")
local function parse_variable_path(parser)
    local parts = {}

    -- First identifier
    local token = expect(parser, lexer.TOKEN_TYPES.IDENTIFIER)
    table.insert(parts, token.value)

    -- Additional parts separated by dots
    while peek(parser).type == lexer.TOKEN_TYPES.DOT do
        advance(parser)  -- consume dot
        token = expect(parser, lexer.TOKEN_TYPES.IDENTIFIER)
        table.insert(parts, token.value)
    end

    return parts
end

-- Forward declaration
local parse_nodes

-- Parse {{#if condition}} ... {{/if}}
local function parse_if_directive(parser)
    -- Already consumed OPEN_BRACE and HASH

    -- Get "if" keyword
    local keyword = expect(parser, lexer.TOKEN_TYPES.IDENTIFIER)
    if keyword.value ~= "if" then
        error("Expected 'if' keyword but got '" .. keyword.value .. "'")
    end

    -- Get condition variable path
    local condition = parse_variable_path(parser)

    -- Expect closing }}
    expect(parser, lexer.TOKEN_TYPES.CLOSE_BRACE)

    -- Parse body until {{/if}}
    local body = parse_nodes(parser, function(p)
        local token = peek(p)
        return token.type == lexer.TOKEN_TYPES.OPEN_BRACE and
               p.pos + 1 <= #p.tokens and
               p.tokens[p.pos + 1].type == lexer.TOKEN_TYPES.SLASH
    end)

    -- Expect {{/if}}
    expect(parser, lexer.TOKEN_TYPES.OPEN_BRACE)
    expect(parser, lexer.TOKEN_TYPES.SLASH)
    local end_keyword = expect(parser, lexer.TOKEN_TYPES.IDENTIFIER)
    if end_keyword.value ~= "if" then
        error("Expected '/if' but got '/" .. end_keyword.value .. "'")
    end
    expect(parser, lexer.TOKEN_TYPES.CLOSE_BRACE)

    return {
        type = M.NODE_TYPES.IF,
        condition = condition,
        body = body
    }
end

-- Parse {{#each collection}} ... {{/each}}
local function parse_each_directive(parser)
    -- Already consumed OPEN_BRACE and HASH

    -- Get "each" keyword
    local keyword = expect(parser, lexer.TOKEN_TYPES.IDENTIFIER)
    if keyword.value ~= "each" then
        error("Expected 'each' keyword but got '" .. keyword.value .. "'")
    end

    -- Get collection variable path
    local collection = parse_variable_path(parser)

    -- Expect closing }}
    expect(parser, lexer.TOKEN_TYPES.CLOSE_BRACE)

    -- Parse body until {{/each}}
    local body = parse_nodes(parser, function(p)
        local token = peek(p)
        return token.type == lexer.TOKEN_TYPES.OPEN_BRACE and
               p.pos + 1 <= #p.tokens and
               p.tokens[p.pos + 1].type == lexer.TOKEN_TYPES.SLASH
    end)

    -- Expect {{/each}}
    expect(parser, lexer.TOKEN_TYPES.OPEN_BRACE)
    expect(parser, lexer.TOKEN_TYPES.SLASH)
    local end_keyword = expect(parser, lexer.TOKEN_TYPES.IDENTIFIER)
    if end_keyword.value ~= "each" then
        error("Expected '/each' but got '/" .. end_keyword.value .. "'")
    end
    expect(parser, lexer.TOKEN_TYPES.CLOSE_BRACE)

    return {
        type = M.NODE_TYPES.EACH,
        collection = collection,
        body = body
    }
end

-- Parse {{variable}} or {{obj.field}}
local function parse_variable_directive(parser)
    -- Already consumed OPEN_BRACE

    local path = parse_variable_path(parser)

    expect(parser, lexer.TOKEN_TYPES.CLOSE_BRACE)

    return {
        type = M.NODE_TYPES.VARIABLE,
        path = path
    }
end

-- Parse nodes until stop condition
parse_nodes = function(parser, stop_condition)
    local nodes = {}

    while peek(parser).type ~= lexer.TOKEN_TYPES.EOF do
        if stop_condition and stop_condition(parser) then
            break
        end

        local token = peek(parser)

        if token.type == lexer.TOKEN_TYPES.TEXT then
            advance(parser)
            table.insert(nodes, {
                type = M.NODE_TYPES.TEXT,
                value = token.value
            })

        elseif token.type == lexer.TOKEN_TYPES.OPEN_BRACE then
            advance(parser)

            local next_token = peek(parser)

            if next_token.type == lexer.TOKEN_TYPES.HASH then
                advance(parser)
                -- Directive: {{#if}} or {{#each}}
                local keyword_token = peek(parser)
                if keyword_token.value == "if" then
                    table.insert(nodes, parse_if_directive(parser))
                elseif keyword_token.value == "each" then
                    table.insert(nodes, parse_each_directive(parser))
                else
                    error("Unknown directive: #" .. keyword_token.value)
                end

            elseif next_token.type == lexer.TOKEN_TYPES.IDENTIFIER then
                -- Variable: {{var}} or {{obj.field}}
                table.insert(nodes, parse_variable_directive(parser))

            else
                error("Unexpected token after {{: " .. next_token.type)
            end

        else
            -- Skip unexpected tokens
            advance(parser)
        end
    end

    return nodes
end

-- Main parse function
function M.parse(tokens)
    local parser = create_parser(tokens)
    local nodes = parse_nodes(parser, nil)

    return {
        type = M.NODE_TYPES.ROOT,
        children = nodes
    }
end

return M
