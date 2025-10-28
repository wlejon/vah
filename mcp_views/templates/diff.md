# Changes: {{type}} {{data.id}}

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
## Summary

{{#if data.supported}}
{{#each data.changes}}
- **{{field}}:** `{{old}}` → `{{new}}`
{{/each}}

## Before

{{#each data.before}}
**{{@key}}:** {{@value}}
{{/each}}

## After

{{#each data.after}}
**{{@key}}:** {{@value}}
{{/each}}
{{/if}}

{{#if data.not_supported}}
Diff view is not supported for this type.
{{/if}}
