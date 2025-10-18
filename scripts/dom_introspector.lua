-- DOM Introspector for Live RmlUi Elements
-- Walks rendered DOM trees, extracts metadata and structure
-- Uses C++ bridge (dom.* functions) to access RmlUi elements

local M = {}

-- Configuration
M.config = {
    max_depth = 50,              -- Maximum recursion depth
    include_hidden = false,       -- Include hidden elements
    extract_bindings = true,      -- Extract data-* bindings
    extract_events = true         -- Extract event handlers
}

-- Structure types we can detect
M.STRUCTURE_TYPES = {
    TABLE = "table",
    LIST = "list",
    FORM = "form",
    NAVIGATION = "navigation",
    CODE = "code",
    TEXT = "text",
    CONTAINER = "container"
}

-- Node type for our Lua representation
M.NODE_TYPE = {
    ELEMENT = "element",
    DOCUMENT = "document"
}

-- Detect structure type of element
local function detect_structure_type(tag, class_attr)
    -- Table
    if tag == "table" then
        return M.STRUCTURE_TYPES.TABLE
    end

    -- List
    if tag == "ul" or tag == "ol" or tag == "dl" then
        return M.STRUCTURE_TYPES.LIST
    end

    -- Form
    if tag == "form" then
        return M.STRUCTURE_TYPES.FORM
    end

    -- Code
    if tag == "pre" or tag == "code" then
        return M.STRUCTURE_TYPES.CODE
    end

    -- Navigation
    if tag == "nav" then
        return M.STRUCTURE_TYPES.NAVIGATION
    end

    -- Check class for navigation
    if class_attr and (class_attr:match("nav") or class_attr:match("menu")) then
        return M.STRUCTURE_TYPES.NAVIGATION
    end

    -- Container or text
    if tag == "div" or tag == "section" or tag == "article" then
        return M.STRUCTURE_TYPES.CONTAINER
    end

    return M.STRUCTURE_TYPES.TEXT
end

-- Extract data binding information
local function extract_data_bindings(element)
    if not M.config.extract_bindings then
        return nil
    end

    local bindings = {}

    -- data-model
    local model = dom.get_attribute(element, "data-model")
    if model and model ~= "" then
        bindings.model = model
    end

    -- data-for (iteration)
    local data_for = dom.get_attribute(element, "data-for")
    if data_for and data_for ~= "" then
        bindings.for_loop = data_for
    end

    -- data-if (conditional)
    local data_if = dom.get_attribute(element, "data-if")
    if data_if and data_if ~= "" then
        bindings.conditional = data_if
    end

    -- data-value (two-way binding)
    local data_value = dom.get_attribute(element, "data-value")
    if data_value and data_value ~= "" then
        bindings.value = data_value
    end

    if next(bindings) == nil then
        return nil
    end

    return bindings
end

-- Extract event handlers
local function extract_events(element)
    if not M.config.extract_events then
        return nil
    end

    local events = {}

    -- Common event attributes
    local event_attrs = {
        "onclick", "onchange", "onsubmit", "onblur", "onfocus",
        "onkeydown", "onkeyup", "onmouseenter", "onmouseleave"
    }

    for _, attr in ipairs(event_attrs) do
        local handler = dom.get_attribute(element, attr)
        if handler and handler ~= "" then
            local event_name = attr:gsub("^on", "")
            events[event_name] = handler
        end
    end

    -- Check for data-event-* pattern (would need attribute enumeration)
    -- For now, check common ones
    local data_events = {
        "data-event-click", "data-event-change", "data-event-submit"
    }

    for _, attr in ipairs(data_events) do
        local handler = dom.get_attribute(element, attr)
        if handler and handler ~= "" then
            local event_name = attr:gsub("^data%-event%-", "")
            events[event_name] = handler
        end
    end

    if next(events) == nil then
        return nil
    end

    return events
end

-- Extract table structure
local function extract_table_structure(element)
    local structure = {
        type = M.STRUCTURE_TYPES.TABLE,
        rows = 0,
        cols = 0,
        has_header = false,
        headers = {}
    }

    -- Walk children looking for thead and tbody
    local child_count = dom.get_child_count(element)

    for i = 0, child_count - 1 do
        local child = dom.get_child(element, i)
        if child then
            local child_tag = dom.get_tag_name(child)

            if child_tag == "thead" then
                structure.has_header = true

                -- Extract header row
                local thead_children = dom.get_child_count(child)
                for j = 0, thead_children - 1 do
                    local tr = dom.get_child(child, j)
                    if tr and dom.get_tag_name(tr) == "tr" then
                        -- Get header cells
                        local tr_children = dom.get_child_count(tr)
                        for k = 0, tr_children - 1 do
                            local th = dom.get_child(tr, k)
                            if th and dom.get_tag_name(th) == "th" then
                                local header_text = dom.get_text(th)
                                table.insert(structure.headers, header_text)
                            end
                        end
                        break  -- Only first row
                    end
                end

            elseif child_tag == "tbody" then
                -- Count rows
                local tbody_children = dom.get_child_count(child)
                for j = 0, tbody_children - 1 do
                    local tr = dom.get_child(child, j)
                    if tr and dom.get_tag_name(tr) == "tr" then
                        structure.rows = structure.rows + 1

                        -- Count columns from first row
                        if structure.cols == 0 then
                            local tr_children = dom.get_child_count(tr)
                            for k = 0, tr_children - 1 do
                                local td = dom.get_child(tr, k)
                                if td and dom.get_tag_name(td) == "td" then
                                    structure.cols = structure.cols + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- If no thead/tbody, count tr directly
    if structure.rows == 0 then
        for i = 0, child_count - 1 do
            local tr = dom.get_child(element, i)
            if tr and dom.get_tag_name(tr) == "tr" then
                structure.rows = structure.rows + 1

                if structure.cols == 0 then
                    local tr_children = dom.get_child_count(tr)
                    for k = 0, tr_children - 1 do
                        local cell = dom.get_child(tr, k)
                        local cell_tag = dom.get_tag_name(cell)
                        if cell and (cell_tag == "td" or cell_tag == "th") then
                            structure.cols = structure.cols + 1
                        end
                    end
                end
            end
        end
    end

    structure.col_count = #structure.headers > 0 and #structure.headers or structure.cols

    return structure
end

-- Extract list structure
local function extract_list_structure(element, tag)
    local structure = {
        type = M.STRUCTURE_TYPES.LIST,
        ordered = tag == "ol",
        items = 0
    }

    local child_count = dom.get_child_count(element)
    for i = 0, child_count - 1 do
        local child = dom.get_child(element, i)
        if child and dom.get_tag_name(child) == "li" then
            structure.items = structure.items + 1
        end
    end

    return structure
end

-- Extract form structure
local function extract_form_structure(element)
    local structure = {
        type = M.STRUCTURE_TYPES.FORM,
        inputs = {},
        action = dom.get_attribute(element, "action"),
        method = dom.get_attribute(element, "method")
    }

    -- Walk form to find inputs
    local function walk(elem, depth)
        if depth > 10 then return end

        local tag = dom.get_tag_name(elem)
        if tag == "input" or tag == "textarea" or tag == "select" then
            table.insert(structure.inputs, {
                type = tag,
                name = dom.get_attribute(elem, "name"),
                input_type = dom.get_attribute(elem, "type"),
                value = dom.get_attribute(elem, "value"),
                placeholder = dom.get_attribute(elem, "placeholder")
            })
        end

        local child_count = dom.get_child_count(elem)
        for i = 0, child_count - 1 do
            local child = dom.get_child(elem, i)
            if child then
                walk(child, depth + 1)
            end
        end
    end

    walk(element, 0)

    return structure
end

-- Extract metadata from element
local function extract_metadata(element, tag, class_attr, depth)
    local visible = M.config.include_hidden or dom.is_visible(element)

    local metadata = {
        tag = tag,
        depth = depth,
        visible = visible,
        id = dom.get_id(element),
        class = class_attr,
        data_bindings = extract_data_bindings(element),
        events = extract_events(element),
        structure_type = detect_structure_type(tag, class_attr),
        child_count = dom.get_child_count(element)
    }

    -- Extract structure-specific info
    if metadata.structure_type == M.STRUCTURE_TYPES.TABLE then
        metadata.structure = extract_table_structure(element)
    elseif metadata.structure_type == M.STRUCTURE_TYPES.LIST then
        metadata.structure = extract_list_structure(element, tag)
    elseif metadata.structure_type == M.STRUCTURE_TYPES.FORM then
        metadata.structure = extract_form_structure(element)
    end

    -- Get text content for leaf nodes or text elements
    if metadata.child_count == 0 or metadata.structure_type == M.STRUCTURE_TYPES.TEXT then
        local text = dom.get_text(element)
        if text and #text > 0 then
            metadata.text_content = text
        end
    end

    return metadata
end

-- Convert RmlUi element to our tree node (recursive)
local function element_to_node(element, depth)
    if not element then return nil end
    if depth > M.config.max_depth then return nil end

    local tag = dom.get_tag_name(element)
    local class_attr = dom.get_class_name(element)

    -- Check visibility
    if not M.config.include_hidden and not dom.is_visible(element) then
        return nil  -- Skip hidden elements
    end

    local node = {
        type = M.NODE_TYPE.ELEMENT,
        tag = tag,
        children = {},
        metadata = extract_metadata(element, tag, class_attr, depth)
    }

    -- Process children
    local child_count = dom.get_child_count(element)
    for i = 0, child_count - 1 do
        local child = dom.get_child(element, i)
        if child then
            local child_node = element_to_node(child, depth + 1)
            if child_node then
                table.insert(node.children, child_node)
            end
        end
    end

    return node
end

-- Main introspection function
function M.introspect(element)
    if not element then
        return nil, "No element provided"
    end

    -- Check if dom bridge is available
    if not dom or not dom.get_tag_name then
        return nil, "DOM bridge not available - ensure C++ bindings are loaded"
    end

    local tree = element_to_node(element, 0)

    if not tree then
        return nil, "Failed to introspect element"
    end

    return tree
end

-- Collect statistics about the DOM
function M.collect_stats(tree)
    local stats = {
        total_elements = 0,
        total_depth = 0,
        tags = {},
        structures = {},
        data_bindings = 0,
        event_handlers = 0,
        hidden_elements = 0,
        text_nodes = 0
    }

    local function walk(node, depth)
        if depth > stats.total_depth then
            stats.total_depth = depth
        end

        if node.type == M.NODE_TYPE.ELEMENT then
            stats.total_elements = stats.total_elements + 1

            -- Count tag types
            stats.tags[node.tag] = (stats.tags[node.tag] or 0) + 1

            -- Check metadata
            if node.metadata then
                if node.metadata.structure_type then
                    local stype = node.metadata.structure_type
                    stats.structures[stype] = (stats.structures[stype] or 0) + 1
                end

                if node.metadata.data_bindings then
                    stats.data_bindings = stats.data_bindings + 1
                end

                if node.metadata.events then
                    for _ in pairs(node.metadata.events) do
                        stats.event_handlers = stats.event_handlers + 1
                    end
                end

                if not node.metadata.visible then
                    stats.hidden_elements = stats.hidden_elements + 1
                end

                if node.metadata.text_content then
                    stats.text_nodes = stats.text_nodes + 1
                end
            end

            -- Recurse
            for _, child in ipairs(node.children) do
                walk(child, depth + 1)
            end
        end
    end

    if tree then
        walk(tree, 0)
    end

    return stats
end

-- Generate summary of introspected tree
function M.summarize(tree)
    local stats = M.collect_stats(tree)

    local lines = {
        "DOM Summary:",
        string.format("  Total elements: %d", stats.total_elements),
        string.format("  Maximum depth: %d", stats.total_depth),
        string.format("  Text nodes: %d", stats.text_nodes),
        string.format("  Data bindings: %d", stats.data_bindings),
        string.format("  Event handlers: %d", stats.event_handlers)
    }

    if stats.hidden_elements > 0 then
        table.insert(lines, string.format("  Hidden elements: %d", stats.hidden_elements))
    end

    if next(stats.structures) then
        table.insert(lines, "  Structures:")
        for stype, count in pairs(stats.structures) do
            table.insert(lines, string.format("    - %s: %d", stype, count))
        end
    end

    if next(stats.tags) then
        table.insert(lines, "  Top tags:")
        local tag_list = {}
        for tag, count in pairs(stats.tags) do
            table.insert(tag_list, {tag = tag, count = count})
        end
        table.sort(tag_list, function(a, b) return a.count > b.count end)

        for i = 1, math.min(10, #tag_list) do
            table.insert(lines, string.format("    - <%s>: %d", tag_list[i].tag, tag_list[i].count))
        end
    end

    return table.concat(lines, '\n')
end

-- Extract all data bindings from tree
function M.extract_all_bindings(tree)
    local bindings = {
        models = {},       -- data-model references
        loops = {},        -- data-for loops
        conditionals = {}, -- data-if conditions
        values = {}        -- data-value bindings
    }

    local function get_path(node, path)
        path = path or ""
        if node.metadata and node.metadata.id and node.metadata.id ~= "" then
            return path .. "#" .. node.metadata.id
        elseif node.tag then
            return path .. "/" .. node.tag
        end
        return path
    end

    local function walk(node, path)
        if node.metadata and node.metadata.data_bindings then
            local db = node.metadata.data_bindings
            local node_path = get_path(node, path)

            if db.model then
                table.insert(bindings.models, {
                    path = node_path,
                    model = db.model,
                    tag = node.tag
                })
            end

            if db.for_loop then
                table.insert(bindings.loops, {
                    path = node_path,
                    expression = db.for_loop,
                    tag = node.tag
                })
            end

            if db.conditional then
                table.insert(bindings.conditionals, {
                    path = node_path,
                    expression = db.conditional,
                    tag = node.tag
                })
            end

            if db.value then
                table.insert(bindings.values, {
                    path = node_path,
                    expression = db.value,
                    tag = node.tag
                })
            end
        end

        for _, child in ipairs(node.children or {}) do
            walk(child, get_path(node, path))
        end
    end

    if tree then
        walk(tree, "")
    end

    return bindings
end

-- Extract all event handlers from tree
function M.extract_all_events(tree)
    local events = {}

    local function get_path(node, path)
        path = path or ""
        if node.metadata and node.metadata.id and node.metadata.id ~= "" then
            return path .. "#" .. node.metadata.id
        elseif node.tag then
            return path .. "/" .. node.tag
        end
        return path
    end

    local function walk(node, path)
        if node.metadata and node.metadata.events then
            local node_path = get_path(node, path)

            for event_type, handler in pairs(node.metadata.events) do
                table.insert(events, {
                    path = node_path,
                    event = event_type,
                    handler = handler,
                    tag = node.tag
                })
            end
        end

        for _, child in ipairs(node.children or {}) do
            walk(child, get_path(node, path))
        end
    end

    if tree then
        walk(tree, "")
    end

    return events
end

-- Walk tree with callback
function M.walk(tree, callback)
    local function walk_recursive(node)
        local should_continue = callback(node)

        if should_continue ~= false then
            for _, child in ipairs(node.children or {}) do
                walk_recursive(child)
            end
        end
    end

    if tree then
        walk_recursive(tree)
    end
end

-- Print tree structure for debugging
function M.print_tree(tree, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)

    if not tree then
        print(prefix .. "[nil]")
        return
    end

    if tree.type == M.NODE_TYPE.ELEMENT then
        local info = string.format("<%s>", tree.tag)

        if tree.metadata then
            if tree.metadata.id and tree.metadata.id ~= "" then
                info = info .. string.format(" id=%q", tree.metadata.id)
            end
            if tree.metadata.class and tree.metadata.class ~= "" then
                info = info .. string.format(" class=%q", tree.metadata.class)
            end
            if tree.metadata.text_content then
                local text_preview = tree.metadata.text_content:sub(1, 30)
                if #tree.metadata.text_content > 30 then
                    text_preview = text_preview .. "..."
                end
                info = info .. string.format(" text=%q", text_preview)
            end
            if not tree.metadata.visible then
                info = info .. " [hidden]"
            end
        end

        print(prefix .. info)

        for _, child in ipairs(tree.children) do
            M.print_tree(child, indent + 1)
        end
    end
end

return M
