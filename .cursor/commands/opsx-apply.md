---
name: /opsx-apply
id: opsx-apply
category: Workflow
description: "Implement tasks from an OpenSpec change"
---

Implement tasks from an OpenSpec change.

**Input**: Optionally specify a change name (e.g., `/opsx-apply add-auth`). If omitted, infer from context or prompt.

**Workflow:**
1. Select change → read context files → show progress
2. Implement each pending task → mark complete
3. All done → suggest `/opsx-archive`

**Resume support:** If tasks are partially complete, continues from next pending task.

**On completion:** Suggests `/opsx-archive <name>`.
