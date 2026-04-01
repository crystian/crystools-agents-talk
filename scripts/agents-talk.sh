#!/bin/bash
# =============================================================================
# Agent Chat Monitor — Claude Code Plugin
# =============================================================================
#
# PURPOSE:
#   Intercepts Claude Code's Agent tool calls to log agent-to-agent communication
#   in a chat-like format with colors and timing.
#
# HOW IT WORKS:
#   Registered as a Claude Code plugin hook for PreToolUse, PostToolUse, and
#   SubagentStop events. Claude Code pipes JSON to stdin with:
#   - PreToolUse:   tool_input.prompt (instructions sent TO the agent)
#   - PostToolUse:  tool_response (result returned FROM the agent)
#   - SubagentStop: last_assistant_message (final response from async agents)
#
# USAGE:
#   In a separate terminal, run:
#     tail -f .tmp/agents-talk.log
#
# DEPENDENCIES: bash, python3, grep
# =============================================================================

# Output dir is the project where Claude Code is running
TMP_DIR="${PWD}/.tmp"
mkdir -p "$TMP_DIR"

LOG="$TMP_DIR/agents-talk.log"
TIMERS_DIR="$TMP_DIR/agent-timers"
INPUT=$(cat)
TS=$(date '+%H:%M:%S')
NOW=$(date '+%s')

mkdir -p "$TIMERS_DIR"

# --- Colors ---
RST='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'
GRAY='\033[38;5;245m'
# Agent colors
C_API='\033[34m'      # blue
C_APP='\033[32m'      # green
C_OTHER='\033[36m'    # cyan

agent_color() {
  case "$1" in
    api-agent)     echo "$C_API" ;;
    app-agent)     echo "$C_APP" ;;
    commit-agent)  echo "$C_OTHER" ;;
    *)             echo "$C_OTHER" ;;
  esac
}

# Simple JSON value extractor (no jq dependency)
get_val() {
  echo "$INPUT" | grep -oP "\"$1\"\s*:\s*\"\K[^\"]*" | head -1
}

EVENT=$(get_val "hook_event_name")
SOURCE=$(get_val "source")
SESSION=$(get_val "session_id")
SESSION_SHORT="${SESSION:0:4}"

# --- SessionStart: show welcome message (only on fresh sessions) ---
if [ "$EVENT" = "SessionStart" ] && [ "$SOURCE" = "startup" ]; then
  {
    echo ""
    echo -e "${DIM}${TS}${RST} ${C_OTHER}${BOLD}agents-talk${RST}  plugin loaded"
  } >> "$LOG"
  echo '{"systemMessage":"[agents-talk] Watch agent communication: tail -f .tmp/agents-talk.log"}'
  exit 0
fi

# Agent type comes from different fields depending on the event
if [ "$EVENT" = "SubagentStop" ]; then
  AGENT=$(get_val "agent_type")
  DESC=""
else
  AGENT=$(get_val "subagent_type")
  DESC=$(get_val "description")
fi
# Skip SubagentStop events with no agent_type (non-agent events)
if [ -z "$AGENT" ]; then
  [ "$EVENT" = "SubagentStop" ] && exit 0
  AGENT="unknown"
fi

COLOR=$(agent_color "$AGENT")
TIMER_FILE="$TIMERS_DIR/${AGENT}_$(echo "$DESC" | tr ' ' '_')"

if [ "$EVENT" = "PreToolUse" ]; then
  # Save start time for duration calc
  echo "$NOW" > "$TIMER_FILE"
  # Also save by agent type (for SubagentStop which lacks description)
  echo "$NOW" > "$TIMERS_DIR/${AGENT}"

  # Extract prompt (always use python3 for reliability with escaped quotes)
  PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('prompt',''))" 2>/dev/null)
  [ -z "$PROMPT" ] && PROMPT=$(get_val "prompt")

  # Truncate
  LEN=${#PROMPT}
  PROMPT_SHORT=$(echo "$PROMPT" | head -c 500)
  EXTRA=""
  [ "$LEN" -gt 500 ] 2>/dev/null && EXTRA=" ${DIM}[...${LEN} chars]${RST}"

  BODY=$(echo "$PROMPT_SHORT" | sed 's/\\n/\n/g')

  {
    echo ""
    echo -e "${DIM}${TS} ${SESSION_SHORT}${RST} ${COLOR}▶ ${BOLD}${AGENT}${RST}  ${DIM}${DESC}${RST}"
    echo -e "${BODY}${EXTRA}"
  } >> "$LOG"

elif [ "$EVENT" = "PostToolUse" ]; then
  # Skip async tasks (SubagentStop will handle them)
  IS_ASYNC=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_response',{}).get('isAsync',''))" 2>/dev/null)
  if [ "$IS_ASYNC" = "True" ]; then
    exit 0
  fi

  # Clean up timer file
  rm -f "$TIMER_FILE"

  # Extract response + stats
  IFS=$'\t' read -r RESPONSE STATS_DURATION STATS_TOKENS STATS_TOOLS <<< $(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('tool_response', {})
# Content
content = r.get('content', '')
if isinstance(content, list):
    parts = [item.get('text', str(item)) if isinstance(item, dict) else str(item) for item in content]
    content = '\n'.join(parts)
content = str(content)[:800].replace('\n', '\\\\n')
# Stats
ms = r.get('totalDurationMs', 0)
if ms >= 60000:
    dur = f'{ms // 60000}m{(ms % 60000) // 1000}s'
else:
    dur = f'{ms // 1000}s'
tokens = r.get('totalTokens', 0)
if tokens >= 1000:
    tok_str = f'{tokens / 1000:.1f}k'
else:
    tok_str = str(tokens)
tools = r.get('totalToolUseCount', 0)
print(f'{content}\t{dur}\t{tok_str}\t{tools}')
" 2>/dev/null)
  [ -z "$RESPONSE" ] && RESPONSE="[could not parse response]"
  STATS="${GRAY}[${STATS_DURATION}  ${STATS_TOKENS} tok  ${STATS_TOOLS} tools]${RST}"

  LEN=${#RESPONSE}
  EXTRA=""
  [ "$LEN" -ge 800 ] 2>/dev/null && EXTRA=" ${DIM}[...truncated]${RST}"

  BODY=$(echo "$RESPONSE" | sed 's/\\n/\n/g')

  {
    echo ""
    echo -e "${DIM}${TS} ${SESSION_SHORT}${RST} ${COLOR}◀ ${BOLD}${AGENT}${RST}  ${DIM}${DESC}${RST}  ${STATS}"
    echo -e "${BODY}${EXTRA}"
  } >> "$LOG"

elif [ "$EVENT" = "SubagentStop" ]; then
  # Calculate duration from PreToolUse timer
  ASYNC_TIMER="$TIMERS_DIR/${AGENT}"
  STATS=""
  if [ -f "$ASYNC_TIMER" ]; then
    START=$(cat "$ASYNC_TIMER")
    ELAPSED=$((NOW - START))
    if [ "$ELAPSED" -ge 60 ] 2>/dev/null; then
      DUR="$((ELAPSED / 60))m$((ELAPSED % 60))s"
    else
      DUR="${ELAPSED}s"
    fi
    STATS="  ${GRAY}[${DUR}]${RST}"
    rm -f "$ASYNC_TIMER"
  fi

  # Extract last message from async agent
  RESPONSE=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
msg = d.get('last_assistant_message', '')
print(str(msg)[:800])
" 2>/dev/null)
  [ -z "$RESPONSE" ] && RESPONSE="[no response]"

  LEN=${#RESPONSE}
  EXTRA=""
  [ "$LEN" -ge 800 ] 2>/dev/null && EXTRA=" ${DIM}[...truncated]${RST}"

  BODY=$(echo "$RESPONSE" | sed 's/\\n/\n/g')

  {
    echo ""
    echo -e "${DIM}${TS} ${SESSION_SHORT}${RST} ${COLOR}◀ ${BOLD}${AGENT}${RST}  ${DIM}async${RST}${STATS}"
    echo -e "${BODY}${EXTRA}"
  } >> "$LOG"
fi

exit 0
