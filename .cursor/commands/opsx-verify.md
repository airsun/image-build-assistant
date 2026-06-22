---
name: /opsx-verify
id: opsx-verify
category: Workflow
description: "Verify implementation matches change artifacts before archiving"
---

Verify that an implementation matches the change artifacts (specs, tasks, design).

Checks three dimensions:
- **Completeness**: Are all tasks done? Are all requirements implemented?
- **Correctness**: Does the code match the specs?
- **Coherence**: Does the code follow the design decisions?

Outputs a structured report with CRITICAL/WARNING/SUGGESTION issues.

**Input**: Optionally specify a change name (e.g., `/opsx-verify add-auth`). If omitted, prompts for selection.
