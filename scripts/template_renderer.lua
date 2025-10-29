-- Template Renderer
-- Walks AST and renders output with data binding

local parser = require("template_parser")
local M = {}

-- HTML escape function for XSS protection
local function escape_html(value)
    if type(value) ~= "string" then
        return value
    end
    local result = value:gsub("&", "&amp;")
    result = result:gsub("<", "&lt;")
    result = result:gsub(">", "&gt;")
    result = result:gsub('"', "&quot;")
    result = result:gsub("'", "&#39;")
    return result
end

-- Resolve variable path in context
local function resolve_path(path, context)
    if not path or #path == 0 then
        return nil
    end

    local value = context
    for _, part in ipairs(path) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
        if value == nil then
            return nil
        end
    end

    return value
end

-- Check if value is truthy
local function is_truthy(value)
    if value == nil or value == false then
        return false
    end
    if type(value) == "number" and value == 0 then
        return false
    end
    if type(value) == "string" and value == "" then
        return false
    end
    if type(value) == "table" then
        local count = 0
        for _ in pairs(value) do
            count = count + 1
            break
        end
        return count > 0
    end
    return true
end

-- Convert value to string
local function to_string(value, depth)
    depth = depth or 0

    if value == nil then
        return ""
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    if type(value) == "number" then
        return tostring(value)
    end
    if type(value) == "string" then
        return value
    end
    if type(value) == "table" then
        -- Prevent infinite recursion
        if depth > 2 then
            return "[nested table]"
        end

        -- Check if it's an array
        local is_array = #value > 0

        if is_array then
            -- For arrays, check what type of elements they contain
            local first_elem = value[1]

            if type(first_elem) == "table" then
                -- Array of objects - show count and first few items
                local count = #value
                if count <= 3 then
                    -- Show all items
                    local items = {}
                    for _, item in ipairs(value) do
                        if type(item) == "table" then
                            -- Show first property of each object
                            local first_key, first_val = next(item)
                            if first_key and first_val then
                                table.insert(items, to_string(first_val, depth + 1))
                            end
                        else
                            table.insert(items, to_string(item, depth + 1))
                        end
                    end
                    return table.concat(items, ", ")
                else
                    return count .. " items"
                end
            else
                -- Array of primitives - show as comma-separated
                local items = {}
                local max_items = 10
                for i, item in ipairs(value) do
                    if i > max_items then
                        table.insert(items, "...")
                        break
                    end
                    table.insert(items, to_string(item, depth + 1))
                end
                return table.concat(items, ", ")
            end
        else
            -- Object/dictionary - show count of keys
            local count = 0
            for _ in pairs(value) do
                count = count + 1
            end
            if count == 0 then
                return "{}"
            end
            return count .. " fields"
        end
    end
    return tostring(value)
end

-- Forward declaration
local render_node

-- Render multiple nodes
local function render_nodes(nodes, context, options)
    local output = {}
    for _, node in ipairs(nodes) do
        table.insert(output, render_node(node, context, options))
    end
    return table.concat(output)
end

-- Render a single node
-- @param node The AST node to render
-- @param context The data context
-- @param options Rendering options (e.g., {escape_html = true})
render_node = function(node, context, options)
    options = options or {}

    if node.type == parser.NODE_TYPES.ROOT then
        return render_nodes(node.children, context, options)

    elseif node.type == parser.NODE_TYPES.TEXT then
        return node.value

    elseif node.type == parser.NODE_TYPES.VARIABLE then
        local value = resolve_path(node.path, context)
        local str_value = to_string(value)
        -- Apply HTML escaping if enabled
        if options.escape_html then
            str_value = escape_html(str_value)
        end
        return str_value

    elseif node.type == parser.NODE_TYPES.IF then
        local value = resolve_path(node.condition, context)
        if is_truthy(value) then
            return render_nodes(node.body, context, options)
        end
        return ""

    elseif node.type == parser.NODE_TYPES.UNLESS then
        local value = resolve_path(node.condition, context)
        if not is_truthy(value) then
            return render_nodes(node.body, context, options)
        end
        return ""

    elseif node.type == parser.NODE_TYPES.EACH then
        local collection = resolve_path(node.collection, context)

        if not collection or type(collection) ~= "table" then
            return ""
        end

        local output = {}
        local is_array = #collection > 0

        if is_array then
            -- Array iteration
            for i, item in ipairs(collection) do
                local iter_context = {}

                -- Copy parent context
                for k, v in pairs(context) do
                    iter_context[k] = v
                end

                -- Add item fields
                if type(item) == "table" then
                    for k, v in pairs(item) do
                        iter_context[k] = v
                    end
                else
                    iter_context["@value"] = item
                end

                -- Add special variables
                iter_context["@index"] = i - 1
                iter_context["@first"] = (i == 1)
                iter_context["@last"] = (i == #collection)

                local rendered = render_nodes(node.body, iter_context, options)

                -- Trim leading newline from each iteration to avoid double newlines
                rendered = rendered:gsub("^[\r\n]+", "")

                table.insert(output, rendered)
            end
        else
            -- Object iteration
            local keys = {}
            for k in pairs(collection) do
                table.insert(keys, k)
            end

            for idx, key in ipairs(keys) do
                local value = collection[key]
                local iter_context = {}

                -- Copy parent context
                for k, v in pairs(context) do
                    iter_context[k] = v
                end

                -- Add special variables
                iter_context["@key"] = key
                iter_context["@value"] = value
                iter_context["@index"] = idx - 1
                iter_context["@first"] = (idx == 1)
                iter_context["@last"] = (idx == #keys)

                local rendered = render_nodes(node.body, iter_context, options)

                -- Trim leading newline from each iteration to avoid double newlines
                rendered = rendered:gsub("^[\r\n]+", "")

                table.insert(output, rendered)
            end
        end

        return table.concat(output)
    end

    return ""
end

-- Main render function
-- @param template The template string
-- @param data The data context
-- @param options Rendering options: {escape_html = boolean}
-- @return rendered string, errors table
function M.render(template, data, options)
    if not template or template == "" then
        return "", {}
    end

    data = data or {}
    options = options or {}

    -- Lex
    local lexer = require("template_lexer")
    local tokens = lexer.tokenize(template)

    -- Parse
    local ast, parse_errors = parser.parse(tokens)

    -- Render (even if there are errors, try to render what we can)
    return render_node(ast, data, options), parse_errors
end

return M
