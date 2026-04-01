# Agents Talk Plugin

## Project Overview

Claude Code plugin that monitors agent-to-agent communication in a chat-like format. Hooks into Agent tool events to log colored, timestamped messages with duration, tokens, and tool counts.

## Repository Structure

```
.claude-plugin/
  plugin.json       — plugin manifest (name, version, description)
.github/workflows/
  bump-version.yml  — GitHub Actions auto version bump on push to main
hooks/
  hooks.json        — hook event definitions (PreToolUse, PostToolUse, SubagentStop, SessionStart)
scripts/
  agents-talk.sh    — main hook script (bash + python3)
```

## Version Management

Versions are managed via GitHub Actions (`.github/workflows/bump-version.yml`). On every push to main, the workflow auto-bumps patch version in `plugin.json`. Can also be triggered manually for minor/major bumps via workflow_dispatch. Never bump versions manually.

## Git

**NEVER run `git push`.** Pushing is done manually by the user.

**NEVER commit automatically.** Do NOT commit after finishing work unless the user explicitly asks. Completing tasks ≠ commit.
