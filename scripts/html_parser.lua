-- HTML/RML Parser
-- Builds a DOM tree from tokens produced by html_lexer
-- Handles malformed HTML by auto-closing tags

local lexer = require("scripts.html_lexer")

local M = {}

-- Node types
M.NODE_TYPES = {
    ELEMENT = "element",
    TEXT = "text",
    COMMENT = "comment",
    DOCUMENT = "document"
}

-- Tags that auto-close when encountering specific tags
local AUTO_CLOSE_RULES = {
    p = {p = true, div = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true},
    li = {li = true},
    dt = {dt = true, dd = true},
    dd = {dt = true, dd = true},
    td = {tr = true, td = true, th = true},
    th = {tr = true, td = true, th = true},
    tr = {tr = true},
    option = {option = true},
}

-- Create element node
local function create_element(tag, attributes, line, col)
    return {
        type = M.NODE_TYPES.ELEMENT,
        tag = tag,
        attributes = attributes or {},
        children = {},
        parent = nil,
        line = line,
        col = col
    }
end

-- Create text node
local function create_text(content, line, col)
    return {
        type = M.NODE_TYPES.TEXT,
        content = content,
        parent = nil,
        line = line,
        col = col
    }
end

-- Create comment node
local function create_comment(content, line, col)
    return {
        type = M.NODE_TYPES.COMMENT,
        content = content,
        parent = nil,
        line = line,
        col = col
    }
end

-- Create document node (root)
local function create_document()
    return {
        type = M.NODE_TYPES.DOCUMENT,
        children = {},
        parent = nil
    }
end

-- Append child to parent
local function append_child(parent, child)
    table.insert(parent.children, child)
    child.parent = parent
end

-- Remove child from parent
local function remove_child(parent, child)
    for i, c in ipairs(parent.children) do
        if c == child then
            table.remove(parent.children, i)
            child.parent = nil
            return true
        end
    end
    return false
end

-- Parser state
local function create_parser(tokens)
    return {
        tokens = tokens,
        pos = 1,
        root = create_document(),
        stack = {},  -- Stack of open elements
        errors = {}  -- Parse errors/warnings
    }
end

-- Current token
local function current_token(parser)
    if parser.pos > #parser.tokens then
        return parser.tokens[#parser.tokens]  -- EOF
    end
    return parser.tokens[parser.pos]
end

-- Advance to next token
local function advance_token(parser)
    parser.pos = parser.pos + 1
end

-- Get current parent (top of stack or root)
local function current_parent(parser)
    if #parser.stack > 0 then
        return parser.stack[#parser.stack]
    end
    return parser.root
end

-- Push element onto stack
local function push_element(parser, element)
    table.insert(parser.stack, element)
end

-- Pop element from stack
local function pop_element(parser)
    if #parser.stack > 0 then
        return table.remove(parser.stack)
    end
    return nil
end

-- Find element in stack by tag name
local function find_in_stack(parser, tag)
    for i = #parser.stack, 1, -1 do
        if parser.stack[i].tag == tag then
            return i
        end
    end
    return nil
end

-- Auto-close elements based on rules
local function auto_close_elements(parser, new_tag)
    if #parser.stack == 0 then return end

    local top = parser.stack[#parser.stack]
    local rules = AUTO_CLOSE_RULES[top.tag]

    if rules and rules[new_tag] then
        -- Auto-close the top element
        table.insert(parser.errors, {
            type = "auto_close",
            message = string.format("Auto-closing <%s> before <%s>", top.tag, new_tag),
            line = top.line,
            col = top.col
        })
        pop_element(parser)
    end
end

-- Handle opening tag
local function handle_tag_open(parser, token)
    -- Check for auto-close
    auto_close_elements(parser, token.tag)

    -- Create element
    local element = create_element(token.tag, token.attributes, token.line, token.col)

    -- Add to parent
    local parent = current_parent(parser)
    append_child(parent, element)

    -- Push onto stack
    push_element(parser, element)
end

-- Handle closing tag
local function handle_tag_close(parser, token)
    -- Find matching opening tag
    local index = find_in_stack(parser, token.tag)

    if not index then
        -- No matching opening tag - ignore or warn
        table.insert(parser.errors, {
            type = "unmatched_close",
            message = string.format("No matching opening tag for </%s>", token.tag),
            line = token.line,
            col = token.col
        })
        return
    end

    -- Close all tags up to and including the matching tag
    -- This handles cases like: <div><p></div> -> auto-close <p>
    local closed_count = #parser.stack - index + 1
    for i = 1, closed_count do
        local closed = pop_element(parser)
        -- Defensive check: ensure we got a valid element
        if not closed then
            table.insert(parser.errors, {
                type = "stack_underflow",
                message = "Internal error: stack underflow during tag close",
                line = token.line,
                col = token.col
            })
            break
        end
        if i > 1 then
            table.insert(parser.errors, {
                type = "unclosed_tag",
                message = string.format("Tag <%s> was not properly closed before </%s>",
                    closed.tag, token.tag),
                line = closed.line,
                col = closed.col
            })
        end
    end
end

-- Handle self-closing tag
local function handle_tag_self_close(parser, token)
    local element = create_element(token.tag, token.attributes, token.line, token.col)
    local parent = current_parent(parser)
    append_child(parent, element)
end

-- Handle text content
local function handle_text(parser, token)
    -- Skip empty/whitespace-only text at document level
    local parent = current_parent(parser)
    if parent.type == M.NODE_TYPES.DOCUMENT then
        if token.content:match('^%s*$') then
            return
        end
    end

    local text_node = create_text(token.content, token.line, token.col)
    append_child(parent, text_node)
end

-- Handle comment
local function handle_comment(parser, token)
    local comment_node = create_comment(token.content, token.line, token.col)
    local parent = current_parent(parser)
    append_child(parent, comment_node)
end

-- Parse tokens into tree
function M.parse(tokens)
    local parser = create_parser(tokens)

    while parser.pos <= #parser.tokens do
        local token = current_token(parser)

        if token.type == lexer.TOKEN_TYPES.TAG_OPEN then
            handle_tag_open(parser, token)
        elseif token.type == lexer.TOKEN_TYPES.TAG_CLOSE then
            handle_tag_close(parser, token)
        elseif token.type == lexer.TOKEN_TYPES.TAG_SELF_CLOSE then
            handle_tag_self_close(parser, token)
        elseif token.type == lexer.TOKEN_TYPES.TEXT then
            handle_text(parser, token)
        elseif token.type == lexer.TOKEN_TYPES.COMMENT then
            handle_comment(parser, token)
        elseif token.type == lexer.TOKEN_TYPES.EOF then
            break
        end

        advance_token(parser)
    end

    -- Close any remaining open tags
    while #parser.stack > 0 do
        local unclosed = pop_element(parser)
        if unclosed then
            table.insert(parser.errors, {
                type = "unclosed_tag",
                message = string.format("Tag <%s> was not closed", unclosed.tag),
                line = unclosed.line,
                col = unclosed.col
            })
        else
            -- Should never happen, but break to prevent infinite loop
            break
        end
    end

    return parser.root, parser.errors
end

-- Parse HTML string directly
function M.parse_html(html)
    local tokens = lexer.tokenize(html)
    return M.parse(tokens)
end

-- Helper: Find all elements by tag name
function M.find_by_tag(node, tag_name)
    local results = {}

    local function walk(n)
        if n.type == M.NODE_TYPES.ELEMENT then
            if n.tag == tag_name then
                table.insert(results, n)
            end
            for _, child in ipairs(n.children) do
                walk(child)
            end
        end
    end

    walk(node)
    return results
end

-- Helper: Find element by ID
function M.find_by_id(node, id)
    local function walk(n)
        if n.type == M.NODE_TYPES.ELEMENT then
            if n.attributes.id == id then
                return n
            end
            for _, child in ipairs(n.children) do
                local found = walk(child)
                if found then return found end
            end
        end
        return nil
    end

    return walk(node)
end

-- Helper: Get all text content from node and descendants
function M.get_text_content(node)
    local parts = {}

    local function walk(n)
        if n.type == M.NODE_TYPES.TEXT then
            table.insert(parts, n.content)
        elseif n.type == M.NODE_TYPES.ELEMENT then
            for _, child in ipairs(n.children) do
                walk(child)
            end
        end
    end

    walk(node)
    return table.concat(parts, '')
end

-- Helper: Get inner HTML (children as HTML string)
function M.get_inner_html(node)
    local parts = {}

    local function serialize(n)
        if n.type == M.NODE_TYPES.TEXT then
            -- Escape special chars
            local text = n.content
            text = text:gsub('&', '&amp;')
            text = text:gsub('<', '&lt;')
            text = text:gsub('>', '&gt;')
            table.insert(parts, text)
        elseif n.type == M.NODE_TYPES.ELEMENT then
            -- Opening tag
            table.insert(parts, '<' .. n.tag)
            for k, v in pairs(n.attributes) do
                if v == true then
                    table.insert(parts, ' ' .. k)
                else
                    table.insert(parts, string.format(' %s="%s"', k, v))
                end
            end

            if #n.children == 0 then
                table.insert(parts, '/>')
            else
                table.insert(parts, '>')
                for _, child in ipairs(n.children) do
                    serialize(child)
                end
                table.insert(parts, '</' .. n.tag .. '>')
            end
        elseif n.type == M.NODE_TYPES.COMMENT then
            table.insert(parts, '<!-- ' .. n.content .. ' -->')
        end
    end

    if node.type == M.NODE_TYPES.ELEMENT then
        for _, child in ipairs(node.children) do
            serialize(child)
        end
    end

    return table.concat(parts)
end

-- Helper: Print tree for debugging
function M.print_tree(node, indent)
    indent = indent or 0
    local prefix = string.rep('  ', indent)

    if node.type == M.NODE_TYPES.DOCUMENT then
        print(prefix .. "[DOCUMENT]")
        for _, child in ipairs(node.children) do
            M.print_tree(child, indent + 1)
        end
    elseif node.type == M.NODE_TYPES.ELEMENT then
        local attrs = {}
        for k, v in pairs(node.attributes) do
            if v == true then
                table.insert(attrs, k)
            else
                table.insert(attrs, string.format('%s=%q', k, v))
            end
        end
        local attrs_str = #attrs > 0 and (' ' .. table.concat(attrs, ' ')) or ''
        print(string.format("%s<%s%s> [%d:%d]", prefix, node.tag, attrs_str, node.line, node.col))
        for _, child in ipairs(node.children) do
            M.print_tree(child, indent + 1)
        end
    elseif node.type == M.NODE_TYPES.TEXT then
        local preview = node.content:gsub('\n', '\\n'):sub(1, 50)
        if #node.content > 50 then preview = preview .. "..." end
        print(string.format('%s"%s"', prefix, preview))
    elseif node.type == M.NODE_TYPES.COMMENT then
        local preview = node.content:sub(1, 30)
        if #node.content > 30 then preview = preview .. "..." end
        print(string.format('%s<!-- %s -->', prefix, preview))
    end
end

-- Helper: Print parse errors
function M.print_errors(errors)
    if #errors == 0 then
        print("No parse errors")
        return
    end

    print(string.format("Parse errors/warnings (%d):", #errors))
    for i, err in ipairs(errors) do
        print(string.format("  [%d:%d] %s: %s",
            err.line or 0, err.col or 0, err.type, err.message))
    end
end

-- Helper: Get element path (like XPath)
function M.get_path(node)
    local parts = {}

    local current = node
    while current and current.type ~= M.NODE_TYPES.DOCUMENT do
        if current.type == M.NODE_TYPES.ELEMENT then
            -- Find index among siblings of same tag
            local index = 0
            if current.parent then
                local sibling_index = 1
                for _, sibling in ipairs(current.parent.children) do
                    if sibling.type == M.NODE_TYPES.ELEMENT and sibling.tag == current.tag then
                        if sibling == current then
                            index = sibling_index
                            break
                        end
                        sibling_index = sibling_index + 1
                    end
                end
            end

            table.insert(parts, 1, string.format("%s[%d]", current.tag, index))
        end

        current = current.parent
    end

    return '/' .. table.concat(parts, '/')
end

-- Helper: Walk tree with callback
function M.walk(node, callback)
    local should_continue = callback(node)

    if should_continue ~= false and node.children then
        for _, child in ipairs(node.children) do
            M.walk(child, callback)
        end
    end
end

-- Helper: Query selector (simple CSS selector support)
-- Supports: tag, #id, .class, tag#id, tag.class
function M.query_selector(node, selector)
    -- Parse selector
    local tag = selector:match('^([%w%-]+)')
    local id = selector:match('#([%w%-_]+)')
    local class = selector:match('%.([%w%-_]+)')

    local function matches(n)
        if n.type ~= M.NODE_TYPES.ELEMENT then
            return false
        end

        if tag and n.tag ~= tag then
            return false
        end

        if id and n.attributes.id ~= id then
            return false
        end

        if class then
            local classes = n.attributes.class or ""
            local found = false
            for cls in classes:gmatch('[^%s]+') do
                if cls == class then
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end

        return true
    end

    local result = nil
    M.walk(node, function(n)
        if matches(n) then
            result = n
            return false  -- Stop walking
        end
    end)

    return result
end

-- Helper: Query selector all
function M.query_selector_all(node, selector)
    local tag = selector:match('^([%w%-]+)')
    local id = selector:match('#([%w%-_]+)')
    local class = selector:match('%.([%w%-_]+)')

    local function matches(n)
        if n.type ~= M.NODE_TYPES.ELEMENT then
            return false
        end

        if tag and n.tag ~= tag then
            return false
        end

        if id and n.attributes.id ~= id then
            return false
        end

        if class then
            local classes = n.attributes.class or ""
            local found = false
            for cls in classes:gmatch('[^%s]+') do
                if cls == class then
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end

        return true
    end

    local results = {}
    M.walk(node, function(n)
        if matches(n) then
            table.insert(results, n)
        end
    end)

    return results
end

return M
