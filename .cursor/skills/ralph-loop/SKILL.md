---
name: ralph-loop
description: Start a Ralph Loop for iterative self-referential development. Use when the user asks to run a ralph loop, start an iterative loop, or wants repeated autonomous iteration on a task until completion.
---

# Ralph Loop

## Trigger

The user wants to start a Ralph loop — an iterative development loop where the same prompt is fed back after every turn via Cursor's stop hook. The agent sees its own previous work in files each iteration.

## Prerequisites

Requires `.cursor/hooks.json` with ralph-stop registered and `loop_limit: null`. The stop hook script lives at `.cursor/hooks/ralph-stop.sh`.

Check before starting:
```bash
test -f .cursor/hooks.json && grep -q "ralph-stop" .cursor/hooks.json && echo "OK" || echo "MISSING"
```

If missing, tell the user to initialize Ralph-loop hooks for this project.

## Workflow

1. Gather the user's task prompt and optional parameters:
   - `max_iterations` (number, default 0 for unlimited)
   - `completion_promise` (text, or "null" if not set)

2. Create the directory `.ralph/` if it doesn't exist, then write the state file at `.ralph/scratchpad.md`:

   ```markdown
   ---
   iteration: 1
   max_iterations: <N or 0>
   completion_promise: "<TEXT>" or null
   started_at: "<ISO8601>"
   ---

   <the user's task prompt goes here>
   ```

   Example:
   ```markdown
   ---
   iteration: 1
   max_iterations: 20
   completion_promise: "COMPLETE"
   started_at: "2026-03-21T10:00:00Z"
   ---

   Build a REST API for todos with CRUD operations, input validation, and tests.
   ```

3. Confirm to the user that the Ralph loop is active, then begin working on the task.

4. The stop hook (`.cursor/hooks/ralph-stop.sh`) automatically intercepts each turn end and feeds the same prompt back as a followup message. You will see it prefixed with `🔄 Ralph iteration N.`

## Cancelling

To cancel a Ralph loop, delete the state file:
```bash
rm .ralph/scratchpad.md
```

## Guardrails

- If a completion promise is set, you may ONLY output `<promise>TEXT</promise>` when the statement is completely and genuinely true.
- Do not output false promises to escape the loop.
- Always recommend setting `max_iterations` as a safety net.
- Quote the `completion_promise` value in the YAML frontmatter if it contains special characters.

## Output

Confirm the loop is active (prompt, iteration limit, promise if set), then start working on the task immediately.
