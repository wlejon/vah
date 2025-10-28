# System Status

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
## Application

- **App:** {{data.app}}
- **Version:** {{data.version}}
- **MCP Server:** {{data.mcp_server}}
- **Timestamp:** {{data.timestamp}}

{{#if data.threads}}
## Running Threads

{{#each data.threads}}
### {{name}}

**State:** {{state}}

{{#if details}}
{{#each details}}
- **{{@key}}:** {{@value}}
{{/each}}
{{/if}}
{{/each}}
{{/if}}
