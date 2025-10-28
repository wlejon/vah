# {{type}} Summary

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
## Statistics

{{#each data}}
- **{{@key}}:** {{@value}}
{{/each}}
