# {{type}}
{{#if recent_action}}
**Recent:** {{recent_action}}
{{/if}}
Total: **{{data.total}}** items | Page {{data.page}} of {{data.total_pages}}
{{#if data.columns}}
**Columns:** {{#each data.columns}}{{@value}}{{#unless @last}} | {{/unless}}{{/each}}
{{/if}}
## Items
{{#each data.items}}
- {{name}}
{{/each}}
---
*Page {{data.page}} of {{data.total_pages}}, showing {{data.limit}} per page*
