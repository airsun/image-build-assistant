---
name: /opsx-sync
id: opsx-sync
category: Workflow
description: "Sync delta specs from a change to main specs"
---

Sync delta specs from a change to main specs.

Reads delta specs (ADDED/MODIFIED/REMOVED/RENAMED requirements) and intelligently merges them into `openspec/specs/`. Useful when you want to update main specs without archiving the change.

**Input**: Optionally specify a change name (e.g., `/opsx-sync add-auth`). If omitted, prompts for selection.
