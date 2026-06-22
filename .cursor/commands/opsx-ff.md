---
name: /opsx-ff
id: opsx-ff
category: Workflow
description: Fast-forward - create a change and generate all artifacts in one step
---

Fast-forward through artifact creation - create a change and generate everything needed to start implementation in one go.

I'll create a change with artifacts:
- proposal.md (what & why)
- design.md (how)
- tasks.md (implementation steps)

When ready to implement, run `/opsx-apply`

**Input**: The argument after `/opsx-ff` is the change name (kebab-case), OR a description of what you want to build.

**Example:**
```
/opsx-ff add-user-auth
/opsx-ff I want to add dark mode to the settings page
```

If no input provided, I'll ask what you want to build.
