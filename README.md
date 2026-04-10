# Claude Code Powerline Statusline

A rich, informative statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays model info, context usage, token stats, cost tracking, git status, agent activity, and more -- all rendered with ANSI color in your terminal.

![Bash](https://img.shields.io/badge/Bash-4.0%2B-green) ![License](https://img.shields.io/badge/License-MIT-blue)

## Features

- **Model badge** -- shows current model (Opus/Sonnet/Haiku) with icon and context window size
- **Context window** -- progress bar with usage percentage and 200k+ overflow warning
- **Token stats** -- input/output tokens, tokens/sec throughput, cache hit rate
- **Cost tracking** -- session cost with burn rate ($/hr) for longer sessions
- **Git integration** -- branch, staged/unstaged/untracked counts, ahead/behind remote
- **Agent tracking** -- live count of running subagents with type icons and descriptions
- **Task progress** -- dot-style progress bar for TaskCreate/TaskUpdate activity
- **Rate limits** -- 5-hour and 7-day usage with progress bars and reset countdowns
- **Session/worktree** -- session name and worktree info when active
- **Vim mode** -- displays current vim mode (Normal/Insert) when enabled
- **Lines changed** -- additions and deletions in the current session

## Screenshot

```
♛ Claude Opus 4.6 200k │ 📁 my-project │  main +2 ~1 │ v1.0.30
ctx ████████░░░░ 65% │ ↓12.3k ↑4.2k (45 tok/s) │ ⚡82% cache │ 💰 $0.47 ($2.14/h) │ ⏱ 13m 12s (8m 4s api) │ +42 -18
⟐ 2 agents 🔍 Explore codebase, 🤖 Fix auth bug │ tasks ●●●○○○ 3/6
```

## Requirements

- Bash 4.0+
- `jq` for JSON parsing
- Claude Code CLI

## Installation

### 1. Configure the statusline command

Add the following to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusline": {
    "command": "/path/to/statusline-command.sh"
  }
}
```

### 2. Enable agent tracking (optional)

To track running agents and task progress, add hooks that log tool activity. Add to your Claude Code settings:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent|TaskCreate|TaskUpdate",
        "hooks": [
          {
            "type": "command",
            "command": "printf '{\"tool\":\"%s\",\"event\":\"start\",\"input\":%s}\\n' \"$CLAUDE_TOOL_NAME\" \"$CLAUDE_TOOL_INPUT\" >> \"$HOME/.claude/tool-activity-$PPID.log\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Agent|TaskCreate|TaskUpdate",
        "hooks": [
          {
            "type": "command",
            "command": "printf '{\"tool\":\"%s\",\"event\":\"complete\",\"input\":%s}\\n' \"$CLAUDE_TOOL_NAME\" \"$CLAUDE_TOOL_INPUT\" >> \"$HOME/.claude/tool-activity-$PPID.log\""
          }
        ]
      }
    ]
  }
}
```

## How it works

The script reads JSON status data from stdin (provided by Claude Code) and renders a multi-line statusline using ANSI escape codes. It processes:

1. **Model and session metadata** -- extracted from the JSON payload
2. **Git status** -- gathered via local git commands
3. **Agent/task activity** -- parsed from hook-generated log files (keyed by PID with session-aware cleanup)

The output is typically 2--3 lines depending on whether agents or tasks are active.

## License

MIT
