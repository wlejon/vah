# {{type}} Database View

{{#if recent_action}}
**Recent Activity:** {{recent_action}}
**Timestamp:** {{timestamp}}

{{/if}}
## Overview

- **Total Records:** {{data.total}}
- **Current Page:** {{data.page}} of {{data.total_pages}}
- **Database:** {{metadata.database}}
- **Table:** {{metadata.table_name}}

{{#if has_recent_activity}}
## Statistics

{{#each stats}}
- **{{@key}}:** {{@value}}
{{/each}}
{{/if}}

## Contact List

{{#each data.items}}
{{#if @first}}
| ID | Name | Email | Status | Age |
|----|------|-------|--------|-----|
{{/if}}
| {{id}} | {{name}} | {{email}} | {{status}} | {{age}} |
{{/each}}

---

Page {{data.page}} of {{data.total_pages}} (showing {{data.limit}} per page)
