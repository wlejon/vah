-- MCP Configuration
-- Defines paths and settings for the MCP server

return {
    -- Server settings
    server = {
        host = "127.0.0.1",
        port = 8765,
        endpoint = "/mcp",
        protocol_version = "2025-06-18"
    },

    -- Server capabilities
    capabilities = {
        tools = {
            listChanged = true
        }
    },

    -- Server info
    info = {
        name = "VahMCPServer",
        version = "1.0.0"
    },

    -- Navigation tools module
    navigation_tools = "mcp_tools/navigation",

    -- Type registry settings
    type_registry = {
        types_directory = "mcp_views/types",
        templates_directory = "mcp_views/templates"
    },

    -- Core navigation tool names (always available)
    core_tools = {
        "list",
        "detail",
        "summary",
        "search",
        "diff",
        "status"
    }
}
