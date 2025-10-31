-- Input Validation Module
-- Provides reusable validation functions for database inputs

local M = {}

-- Validation functions
function M.validate_color_value(value, name)
    if type(value) ~= "number" then
        return false, name .. " must be a number"
    end
    if value < 0 or value > 255 then
        return false, name .. " must be between 0 and 255"
    end
    return true, ""
end

function M.validate_positive_integer(value, name)
    if type(value) ~= "number" then
        return false, name .. " must be a number"
    end
    if value < 0 or value ~= math.floor(value) then
        return false, name .. " must be a positive integer"
    end
    return true, ""
end

function M.validate_string(value, name)
    if type(value) ~= "string" then
        return false, name .. " must be a string"
    end
    if #value == 0 then
        return false, name .. " cannot be empty"
    end
    return true, ""
end

function M.validate_port_type(value)
    if value ~= "input" and value ~= "output" then
        return false, "port_type must be 'input' or 'output'"
    end
    return true, ""
end

-- Schema-based validation
local schemas = {
    node_type = {
        {field = "name", validator = M.validate_string},
        {field = "color_r", validator = M.validate_color_value},
        {field = "color_g", validator = M.validate_color_value},
        {field = "color_b", validator = M.validate_color_value},
        {field = "color_a", validator = M.validate_color_value},
    },
    port = {
        {field = "node_type_id", validator = M.validate_positive_integer},
        {field = "port_name", validator = M.validate_string},
        {field = "port_order", validator = M.validate_positive_integer},
    },
}

-- Validate data against a schema
function M.validate(schema_name, data)
    local schema = schemas[schema_name]
    if not schema then
        return false, "Unknown validation schema: " .. tostring(schema_name)
    end

    for _, rule in ipairs(schema) do
        local value = data[rule.field]
        local valid, err = rule.validator(value, rule.field)
        if not valid then
            return false, err
        end
    end

    return true, ""
end

-- Validate port type separately since it doesn't follow the same pattern
function M.validate_port_data(node_type_id, port_name, port_type, port_order)
    local data = {
        node_type_id = node_type_id,
        port_name = port_name,
        port_order = port_order
    }

    local valid, err = M.validate("port", data)
    if not valid then
        return false, err
    end

    valid, err = M.validate_port_type(port_type)
    if not valid then
        return false, err
    end

    return true, ""
end

return M
