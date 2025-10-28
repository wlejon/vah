# {{type}}
{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
Total: **{{data.total}}** items | Page {{data.page}} of {{data.total_pages}}

## Items
{{#each data.items}}
- **{{name}}**{{#if path}} - {{path}}{{/if}}{{#if size}} ({{size}} bytes){{/if}}{{#if status}} [{{status}}]{{/if}}{{#if row_count}} ({{row_count}} rows){{/if}}
{{/each}}
---
*Page {{data.page}} of {{data.total_pages}}, showing {{data.limit}} per page*
