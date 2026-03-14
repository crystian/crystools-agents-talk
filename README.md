# agents-talk

Claude Code plugin that monitors agent-to-agent communication in a chat-like format.

Logs colored, timestamped messages with duration, token usage, and tool counts to a file you can `tail -f`.

## Output example

```
14:32:05 a1b2 ▶ api-agent  Create user endpoint
  Create a POST /users endpoint that accepts name and email...

14:32:18 a1b2 ◀ api-agent  Create user endpoint  [13s  4.2k tok  8 tools]
  Created POST /users endpoint with validation...
```

## Requirements

- bash
- python3
- grep with `-P` (Perl regex) support

## Installation

### From marketplace (recommended)

```bash
# Add the marketplace
/plugin marketplace add crystian/claude-agents-talk

# Install the plugin
/plugin install agents-talk@claude-agents-talk
```

### Local (for development)

```bash
claude --plugin-dir /path/to/claude-agents-talk/plugins/agents-talk
```

## Usage

In a separate terminal, watch the log:

```bash
tail -f .tmp/agents-talk.log
```

The plugin automatically logs:
- **▶ Outbound** — prompts sent to agents (PreToolUse)
- **◀ Inbound** — responses from agents (PostToolUse / SubagentStop)

## Tracked events

| Event | What it captures |
|---|---|
| `PreToolUse` (Agent) | Prompt sent to the agent |
| `PostToolUse` (Agent) | Response + stats (duration, tokens, tools) |
| `SubagentStop` | Final response from background agents |

## Agent colors

| Agent | Color |
|---|---|
| api-agent | Blue |
| app-agent | Green |
| commit-agent | Cyan |
| Others | Cyan |

## License

MIT
