# Search Results: "{{data.query}}"

{{#if recent_action}}
**Recent:** {{recent_action}}

{{/if}}
Found **{{data.total_matches}}** matches in {{type}}

---

{{#each data.items}}
## {{name}}

- **Path:** {{path}}
- **Size:** {{size}} bytes

{{/each}}
