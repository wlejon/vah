-- Template Renderer
-- Walks AST and renders output with data binding

local parser = require("template_parser")
local M = {}

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
local function to_string(value)
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
        return "[table]"
    end
    return tostring(value)
end

-- Forward declaration
local render_node

-- Render multiple nodes
local function render_nodes(nodes, context)
    local output = {}
    for _, node in ipairs(nodes) do
        table.insert(output, render_node(node, context))
    end
    return table.concat(output)
end

-- Render a single node
render_node = function(node, context)
    if node.type == parser.NODE_TYPES.ROOT then
        return render_nodes(node.children, context)

    elseif node.type == parser.NODE_TYPES.TEXT then
        return node.value

    elseif node.type == parser.NODE_TYPES.VARIABLE then
        local value = resolve_path(node.path, context)
        return to_string(value)

    elseif node.type == parser.NODE_TYPES.IF then
        local value = resolve_path(node.condition, context)
        if is_truthy(value) then
            return render_nodes(node.body, context)
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

                local rendered = render_nodes(node.body, iter_context)

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

                local rendered = render_nodes(node.body, iter_context)

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
function M.render(template, data)
    if not template or template == "" then
        return ""
    end

    data = data or {}

    -- Lex
    local lexer = require("template_lexer")
    local tokens = lexer.tokenize(template)

    -- Parse
    local ast = parser.parse(tokens)

    -- Render
    return render_node(ast, data)
end

return M
