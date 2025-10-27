# MCP Markdown Templates

## Overview

Markdown templates are used to render data views for LLM consumption. Templates are generic and work with any data type by using a simple variable substitution system.

## Template Location

Generic templates: `mcp_views/templates/`
- `list.md`
- `detail.md`
- `summary.md`
- `search.md`
- `diff.md`
- `status.md`

Type-specific overrides: Defined in type definition's `templates` field

## Template Syntax

We use a Mustache-like syntax that's simple to parse in Lua:

### Variable Substitution
```markdown
{{variable_name}}
```

### Conditionals
```markdown
{{#if variable}}
Content shown if variable is truthy
{{/if}}
```

### Loops
```markdown
{{#each items}}
- {{name}}: {{value}}
{{/each}}
```

### Nested Access
```markdown
{{object.field.subfield}}
```

## Standard Data Structure

All view types receive a standardized data structure:

```lua
{
    -- Metadata
    type = "contacts",          -- Data type name
    view = "list",              -- View type
    timestamp = "2025-01-15",   -- When rendered

    -- View-specific data
    data = {...},               -- The actual data

    -- Context
    context = {...},            -- Current context

    -- Recent activity
    recent_action = "Created contact 'John Doe'",  -- Optional
}
```

## Template Examples

### List Template (list.md)

```markdown
# {{type}} ({{data.total}})

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
{{#each data.items}}
{{#first}}
| {{#each @keys}}{{.}} | {{/each}}
|{{#each @keys}}---|{{/each}}
{{/first}}
| {{#each @values}}{{.}} | {{/each}}
{{/each}}

Page {{data.page}} of {{data.total_pages}} ({{data.limit}} per page)
```

### Detail Template (detail.md)

```markdown
# {{type}}: {{data.id}}

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
{{#each data}}
**{{@key}}:** {{@value}}
{{/each}}
```

### Summary Template (summary.md)

```markdown
# {{type}} Summary

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
{{#each data}}
- **{{@key}}:** {{@value}}
{{/each}}
```

### Search Template (search.md)

```markdown
# Search Results: "{{data.query}}"

Found {{data.total_matches}} matches in {{type}}

{{#each data.items}}
{{#first}}
| {{#each @keys}}{{.}} | {{/each}}
|{{#each @keys}}---|{{/each}}
{{/first}}
| {{#each @values}}{{.}} | {{/each}}
{{/each}}
```

### Diff Template (diff.md)

```markdown
# Changes to {{type}}: {{data.id}}

## Before
{{#each data.before}}
**{{@key}}:** {{@value}}
{{/each}}

## After
{{#each data.after}}
**{{@key}}:** {{@value}}
{{/each}}

## Summary
{{#each data.changes}}
- {{field}}: `{{old}}` → `{{new}}`
{{/each}}
```

### Status Template (status.md)

```markdown
# System Status

**Status:** {{data.status}}
{{#if data.message}}
**Message:** {{data.message}}
{{/if}}

## Details
{{#each data.details}}
- **{{@key}}:** {{@value}}
{{/each}}
```

## Template Helpers

The template renderer provides these special variables:

- `@key` - Current key in object iteration
- `@value` - Current value in object iteration
- `@keys` - Array of all keys in object
- `@values` - Array of all values in object
- `@index` - Current index in array iteration (0-based)
- `@first` - True for first iteration
- `@last` - True for last iteration

## Implementation Notes

The template system should:
1. Be implemented in pure Lua
2. Not require external dependencies
3. Handle missing variables gracefully (show empty string)
4. Support nested object access
5. Keep token count low (limit array iterations, truncate long strings)

## Token Optimization

Views should be designed to minimize tokens:
- Limit list views to 10-20 items
- Show pagination info for navigation
- Truncate long text fields
- Use tables for structured data (more compact)
- Omit empty/null fields in detail views
