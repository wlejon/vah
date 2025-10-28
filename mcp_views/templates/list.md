# {{type}}
{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
Total: **{{data.total}}** items | Page {{data.page}} of {{data.total_pages}}

## Items
{{#each data.items}}
- **{{name}}** - {{path}} ({{size}} bytes)
{{/each}}
---
*Page {{data.page}} of {{data.total_pages}}, showing {{data.limit}} per page*
