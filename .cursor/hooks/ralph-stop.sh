#!/bin/bash

# Ralph Loop Stop Hook for Cursor
# Intercepts agent completion, checks for active Ralph loop,
# and feeds the same prompt back via followup_message.
#
# Cursor stop hook API:
#   stdin:  {status, loop_count, conversation_id, transcript_path, ...}
#   stdout: {followup_message?: string}

set -euo pipefail

HOOK_INPUT=$(cat)
RALPH_STATE_FILE=".ralph/scratchpad.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  echo '{}'
  exit 0
fi

STATUS=$(echo "$HOOK_INPUT" | jq -r '.status // "completed"')
if [[ "$STATUS" != "completed" ]]; then
  echo '{}'
  exit 0
fi

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: scratchpad corrupted, stopping." >&2
  rm "$RALPH_STATE_FILE"
  echo '{}'
  exit 0
fi

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Ralph loop: max iterations ($MAX_ITERATIONS) reached." >&2
  rm "$RALPH_STATE_FILE"
  echo '{}'
  exit 0
fi

# Check completion promise against transcript
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]] && [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
  LAST_TEXT=""
  if command -v jq &>/dev/null; then
    LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 100 || true)
    if [[ -n "$LAST_LINES" ]]; then
      set +e
      LAST_TEXT=$(echo "$LAST_LINES" | jq -rs '
        map(.message.content[]? | select(.type == "text") | .text) | last // ""
      ' 2>/dev/null)
      set -e
    fi
  fi

  if [[ -n "$LAST_TEXT" ]]; then
    PROMISE_TEXT=$(echo "$LAST_TEXT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
    if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
      echo "✅ Ralph loop: completion promise matched." >&2
      rm "$RALPH_STATE_FILE"
      echo '{}'
      exit 0
    fi
  fi
fi

NEXT_ITERATION=$((ITERATION + 1))
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  Ralph loop: no prompt in scratchpad, stopping." >&2
  rm "$RALPH_STATE_FILE"
  echo '{}'
  exit 0
fi

TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION | To complete: output <promise>$COMPLETION_PROMISE</promise> (ONLY when TRUE)"
else
  SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION | No completion promise — loop runs until max_iterations"
fi

FOLLOWUP=$(printf '%s\n\n%s' "$SYSTEM_MSG" "$PROMPT_TEXT")

jq -n --arg msg "$FOLLOWUP" '{"followup_message": $msg}'

exit 0
