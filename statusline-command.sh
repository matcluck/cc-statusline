#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Claude Code Powerline v2 – with agent tracking + fixes      ║
# ╚══════════════════════════════════════════════════════════════╝

input=$(cat)

# Validate JSON upfront
printf '%s' "$input" | jq empty 2>/dev/null || exit 0

# Safe extraction helpers (printf, not echo)
j()  { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
jn() { printf '%s' "$input" | jq -r "$1 // 0" 2>/dev/null; }
# Force integer (guard against non-numeric)
ji() { local v; v=$(jn "$1"); v=${v%%.*}; printf '%d' "$v" 2>/dev/null || printf '0'; }

# ── Data extraction ──────────────────────────────────────────
MODEL=$(j '.model.display_name')
MODEL_ID=$(j '.model.id')
DIR=$(j '.workspace.current_dir')
VERSION=$(j '.version')
SESSION_ID=$(j '.session_id')
SESSION_NAME=$(j '.session_name')
TRANSCRIPT=$(j '.transcript_path')
DURATION_MS=$(ji '.cost.total_duration_ms')
API_MS=$(ji '.cost.total_api_duration_ms')
LINES_ADD=$(ji '.cost.total_lines_added')
LINES_DEL=$(ji '.cost.total_lines_removed')
CTX_USED=$(ji '.context_window.used_percentage')
CTX_SIZE=$(ji '.context_window.context_window_size')
TOT_IN=$(ji '.context_window.total_input_tokens')
TOT_OUT=$(ji '.context_window.total_output_tokens')
CACHE_CREATE=$(ji '.context_window.current_usage.cache_creation_input_tokens')
CACHE_READ=$(ji '.context_window.current_usage.cache_read_input_tokens')
VIM_MODE=$(j '.vim.mode')
RL_5H_PCT=$(j '.rate_limits.five_hour.used_percentage')
RL_5H_RESET=$(j '.rate_limits.five_hour.resets_at')
RL_7D_PCT=$(j '.rate_limits.seven_day.used_percentage')
RL_7D_RESET=$(j '.rate_limits.seven_day.resets_at')
WORKTREE_NAME=$(j '.worktree.name')
WORKTREE_BRANCH=$(j '.worktree.branch')
EXCEEDS_200K=$(jn '.exceeds_200k_tokens')

# ── Terminal width / narrow mode detection ──────────────────
# Claude Code does not pass width in JSON and does not export $COLUMNS to the
# statusline command, and the script has no controlling TTY. Inside tmux we can
# ask tmux directly for the pane width – that is the actual rendering width.
COLS=0
if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]]; then
  COLS=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_width}' 2>/dev/null || echo 0)
fi
[[ "${COLS:-0}" =~ ^[0-9]+$ ]] || COLS=0
(( COLS <= 0 )) && COLS=${COLUMNS:-0}
(( COLS <= 0 )) && COLS=$(tput cols 2>/dev/null || echo 120)
NARROW=0
(( COLS < 100 )) && NARROW=1

# ── Pre-expanded ANSI codes (safe for printf %s) ────────────
fg()  { printf '\x1b[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
RST=$'\x1b[0m'
BOLD=$'\x1b[1m'
DIM=$'\x1b[2m'

C_CYAN=$(fg 95 180 210)
C_BLUE=$(fg 100 140 220)
C_PURPLE=$(fg 160 120 210)
C_GREEN=$(fg 120 200 140)
C_YELLOW=$(fg 220 200 100)
C_ORANGE=$(fg 230 160 80)
C_RED=$(fg 220 90 90)
C_PINK=$(fg 210 130 170)
C_DIM=$(fg 100 100 120)
C_WHITE=$(fg 200 200 210)
C_BRIGHT=$(fg 230 230 240)
C_TEAL=$(fg 80 200 180)

# ── Progress bar ─────────────────────────────────────────────
pbar() {
  local pct=${1:-0} width=${2:-10} style=${3:-block}
  pct=${pct%%.*}
  # Clamp to 0-100
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local filled=$(( (pct * width + 50) / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  local empty=$((width - filled))

  local bar_color
  if (( pct >= 90 )); then bar_color="$C_RED"
  elif (( pct >= 75 )); then bar_color="$C_ORANGE"
  elif (( pct >= 50 )); then bar_color="$C_YELLOW"
  else bar_color="$C_GREEN"; fi

  local fill_str pad_str
  if [[ "$style" == "dots" ]]; then
    printf -v fill_str "%${filled}s"; printf -v pad_str "%${empty}s"
    printf '%s%s%s%s%s' "$bar_color" "${fill_str// /●}" "$C_DIM" "${pad_str// /○}" "$RST"
  else
    printf -v fill_str "%${filled}s"; printf -v pad_str "%${empty}s"
    printf '%s%s%s%s%s' "$bar_color" "${fill_str// /█}" "$C_DIM" "${pad_str// /░}" "$RST"
  fi
}

pct_remaining() {
  local used=${1:-0}
  used=${used%%.*}
  (( used < 0 )) && used=0
  (( used > 100 )) && used=100
  printf '%d' "$((100 - used))"
}

pbar_remaining() {
  local pct=${1:-0} width=${2:-10} style=${3:-block}
  pct=${pct%%.*}
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local filled=$(( (pct * width + 50) / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  local empty=$((width - filled))

  local bar_color
  if (( pct <= 10 )); then bar_color="$C_RED"
  elif (( pct <= 25 )); then bar_color="$C_ORANGE"
  elif (( pct <= 50 )); then bar_color="$C_YELLOW"
  else bar_color="$C_GREEN"; fi

  local fill_str pad_str
  if [[ "$style" == "dots" ]]; then
    printf -v fill_str "%${filled}s"; printf -v pad_str "%${empty}s"
    printf '%s%s%s%s%s' "$bar_color" "${fill_str// /●}" "$C_DIM" "${pad_str// /○}" "$RST"
  else
    printf -v fill_str "%${filled}s"; printf -v pad_str "%${empty}s"
    printf '%s%s%s%s%s' "$bar_color" "${fill_str// /█}" "$C_DIM" "${pad_str// /░}" "$RST"
  fi
}

# ── Formatting helpers ───────────────────────────────────────
fmt_tokens() {
  local t=${1:-0}
  if (( t >= 1000000 )); then
    printf '%d.%dM' "$((t / 1000000))" "$(( (t % 1000000) / 100000 ))"
  elif (( t >= 1000 )); then
    printf '%d.%dk' "$((t / 1000))" "$(( (t % 1000) / 100 ))"
  else
    printf '%d' "$t"
  fi
}

fmt_duration() {
  local ms=${1:-0} total_s h m s
  total_s=$((ms / 1000)); h=$((total_s / 3600)); m=$(( (total_s % 3600) / 60 )); s=$((total_s % 60))
  if (( h > 0 )); then printf '%dh %dm' "$h" "$m"
  elif (( m > 0 )); then printf '%dm %ds' "$m" "$s"
  else printf '%ds' "$s"; fi
}

fmt_reset_time() {
  local reset_epoch=${1:-0} now diff h m
  (( reset_epoch == 0 )) && return
  now=$(date +%s); diff=$((reset_epoch - now))
  (( diff <= 0 )) && { printf 'now'; return; }
  h=$((diff / 3600)); m=$(( (diff % 3600) / 60 ))
  if (( h > 0 )); then printf '%dh%dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

# ── Agent & Task tracking ────────────────────────────────────
# Single jq call over last 500 lines – no per-line process spawning
AGENT_DISPLAY=""
TASK_DISPLAY=""
ACTIVITY_LOG="$HOME/.claude/tool-activity-$PPID.log"
SESSION_FILE="$HOME/.claude/tool-activity-$PPID.session"

# Handle PID reuse: if session_id changed, this is a new Claude process reusing the PID
if [[ -n "$SESSION_ID" ]]; then
  PREV_SESSION=$(cat "$SESSION_FILE" 2>/dev/null)
  if [[ "$PREV_SESSION" != "$SESSION_ID" ]]; then
    : > "$ACTIVITY_LOG" 2>/dev/null
    printf '%s' "$SESSION_ID" > "$SESSION_FILE"
  fi
fi

# Clean up logs from dead/reused processes (not ours)
for f in "$HOME/.claude"/tool-activity-*.log; do
  [[ -f "$f" ]] || continue
  pid="${f##*-}"; pid="${pid%.log}"
  [[ "$pid" == "$PPID" ]] && continue
  # Keep only if PID is alive AND is a node process (not a reused PID)
  if kill -0 "$pid" 2>/dev/null; then
    [[ "$(cat /proc/$pid/comm 2>/dev/null)" == "node" ]] && continue
  fi
  rm -f "$f" "$HOME/.claude/tool-activity-${pid}.session" \
        "$HOME/.claude/.hook-status-${pid}" 2>/dev/null
done

if [[ -f "$ACTIVITY_LOG" ]]; then
  # One jq invocation processes everything: agents + tasks
  # Pre-filter valid JSON lines (tail -500 can bisect a line; jq -c '.' drops malformed ones)
  PARSED=$(tail -500 "$ACTIVITY_LOG" 2>/dev/null | jq -c '.' 2>/dev/null | jq -rs '
    # ── Agents: count starts vs completes per description ──
    [.[] | select(.tool == "Agent" and .input.description != null)] |
    group_by(.input.description) |
    [.[] | {
      desc: .[0].input.description,
      type: ([.[] | select(.event == "start")][0].input.subagent_type // "general"),
      model: ([.[] | select(.event == "start")][0].input.model // null),
      running: (([.[] | select(.event == "start")] | length) - ([.[] | select(.event == "complete")] | length))
    } | select(.running > 0)] as $running |

    # ── Tasks: count created vs completed ──
    [.[] | select(.tool == "TaskCreate" or .tool == "TaskUpdate")] as $tasks |
    ($tasks | map(select(.tool == "TaskCreate")) | length) as $total |
    ($tasks | map(select(.tool == "TaskUpdate" and (.input.status == "completed" or .input.status == "done"))) | length) as $completed |

    {
      agents: $running,
      tasks_total: $total,
      tasks_done: $completed
    }
  ' 2>/dev/null)

  if [[ -n "$PARSED" ]]; then
    # Read agent data
    agent_count=$(printf '%s' "$PARSED" | jq -r '.agents | length')

    if (( agent_count > 0 )); then
      running_count=0
      agent_parts=""

      while IFS=$'\t' read -r desc atype amodel; do
        (( running_count++ ))
        icon="⚙"
        case "$atype" in
          Explore)           icon="🔍" ;;
          Plan)              icon="📐" ;;
          general-purpose|general) icon="🤖" ;;
          claude-code-guide) icon="📖" ;;
          statusline-setup)  icon="📊" ;;
          code-simplifier)   icon="✨" ;;
        esac

        model_tag=""
        [[ -n "$amodel" && "$amodel" != "null" ]] && model_tag=" ${C_DIM}[$amodel]${RST}"

        [[ -n "$agent_parts" ]] && agent_parts="${agent_parts}${C_DIM}, ${RST}"
        agent_parts="${agent_parts}${icon} ${C_TEAL}${desc}${RST}${model_tag}"
      done < <(printf '%s' "$PARSED" | jq -r '.agents[] | [.desc, .type, (.model // "")] | @tsv')

      if (( running_count > 0 )); then
        AGENT_DISPLAY="${C_BRIGHT}${BOLD}⟐ ${running_count} agent$( (( running_count > 1 )) && printf 's')${RST} ${agent_parts}"
      fi
    fi

    # Read task data
    total_tasks=$(printf '%s' "$PARSED" | jq -r '.tasks_total')
    done_tasks=$(printf '%s' "$PARSED" | jq -r '.tasks_done')

    if (( total_tasks > 0 )); then
      task_pct=$(( (done_tasks * 100) / total_tasks ))
      task_bar=$(pbar "$task_pct" 6 dots)
      TASK_DISPLAY="${C_WHITE}tasks${RST} ${task_bar} ${C_BRIGHT}${done_tasks}/${total_tasks}${RST}"
    fi
  fi
fi

# ── Subagent files (if transcript path available) ────────────
SUBAGENT_EXTRA=""
SUB_IN=0
SUB_OUT=0
SUB_COUNT=0
if [[ -n "$TRANSCRIPT" && -d "${TRANSCRIPT%.jsonl}/subagents" ]]; then
  subagent_dir="${TRANSCRIPT%.jsonl}/subagents"
  meta_count=$(find "$subagent_dir" -name '*.meta.json' 2>/dev/null | wc -l)
  if (( meta_count > 0 )) && [[ -z "$AGENT_DISPLAY" ]]; then
    # Fallback: show total spawned agents from metadata if hook log didn't catch them
    SUBAGENT_EXTRA=" ${C_DIM}(${meta_count} spawned)${RST}"
  fi

  # Sum token usage across every subagent transcript belonging to this session
  # (recursive find – handles sub-subagents nested under deeper subagents/ dirs).
  # Per-instance scoping is automatic: each Claude session has its own
  # transcript path so we only walk this session's subagent tree.
  SUB_COUNT=$(find "$subagent_dir" -name '*.jsonl' -type f 2>/dev/null | wc -l)
  if (( SUB_COUNT > 0 )); then
    sums=$(find "$subagent_dir" -name '*.jsonl' -type f -print0 2>/dev/null \
      | xargs -0 -r cat 2>/dev/null \
      | jq -r 'select(.type=="assistant" and .message.usage)
          | "\(((.message.usage.input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0))) \(.message.usage.output_tokens // 0)"' 2>/dev/null \
      | awk 'BEGIN{i=0;o=0} {i+=$1; o+=$2} END{print i, o}')
    if [[ -n "$sums" ]]; then
      read -r SUB_IN SUB_OUT <<<"$sums"
      SUB_IN=${SUB_IN:-0}; SUB_OUT=${SUB_OUT:-0}
    fi
  fi
fi

# Combine main + subagent token totals.
TOT_IN_ALL=$((TOT_IN + SUB_IN))
TOT_OUT_ALL=$((TOT_OUT + SUB_OUT))

# ── Git info ─────────────────────────────────────────────────
GIT_BRANCH="" GIT_DIRTY="" GIT_AHEAD="" GIT_BEHIND=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_BRANCH=$(git branch --show-current 2>/dev/null)
  [[ -z "$GIT_BRANCH" ]] && GIT_BRANCH=$(git rev-parse --short HEAD 2>/dev/null)

  local_changes=""
  staged=$(git diff --cached --numstat 2>/dev/null | wc -l)
  unstaged=$(git diff --numstat 2>/dev/null | wc -l)
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | head -100 | wc -l)
  (( staged > 0 ))    && local_changes="${local_changes}+${staged}"
  (( unstaged > 0 ))  && local_changes="${local_changes} ~${unstaged}"
  (( untracked > 0 )) && local_changes="${local_changes} ?${untracked}"
  GIT_DIRTY="$local_changes"

  upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [[ -n "$upstream" ]]; then
    ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
    (( ahead > 0 ))  && GIT_AHEAD="↑${ahead}"
    (( behind > 0 )) && GIT_BEHIND="↓${behind}"
  fi
fi

# ── Model badge ──────────────────────────────────────────────
MODEL_ICON="◆"
case "$MODEL_ID" in
  *opus*)   MODEL_ICON="♛" ;;
  *sonnet*) MODEL_ICON="♪" ;;
  *haiku*)  MODEL_ICON="❋" ;;
esac

CTX_BADGE=""
if (( CTX_SIZE >= 1000000 )); then CTX_BADGE=" 1M"
elif (( CTX_SIZE >= 200000 )); then CTX_BADGE=" 200k"; fi

MODEL_SEG="${C_PURPLE}${BOLD}${MODEL_ICON} ${MODEL}${RST}${C_DIM}${CTX_BADGE}${RST}"

# ── Caveman mode badge ───────────────────────────────────────
CAVEMAN_SEG=""
_CAVEMAN_FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [[ -f "$_CAVEMAN_FLAG" && ! -L "$_CAVEMAN_FLAG" ]]; then
  _cmode=$(head -c 64 "$_CAVEMAN_FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
  _cmode=$(printf '%s' "$_cmode" | tr -cd 'a-z0-9-')
  case "$_cmode" in
    off) ;;
    lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress|"")
      C_CAVE=$(fg 230 140 40)
      if [[ -z "$_cmode" || "$_cmode" == "full" ]]; then
        CAVEMAN_SEG=" ${C_CAVE}[CAVEMAN]${RST}"
      else
        _CSUF=$(printf '%s' "$_cmode" | tr '[:lower:]' '[:upper:]')
        CAVEMAN_SEG=" ${C_CAVE}[CAVEMAN:${_CSUF}]${RST}"
      fi
      # Savings suffix written by /caveman-stats — absent until first run
      _SAVINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-statusline-suffix"
      if [[ -f "$_SAVINGS_FILE" && ! -L "$_SAVINGS_FILE" ]]; then
        _savings=$(head -c 64 "$_SAVINGS_FILE" 2>/dev/null | tr -d '\000-\037')
        [[ -n "$_savings" ]] && CAVEMAN_SEG="${CAVEMAN_SEG} ${C_CAVE}${_savings}${RST}"
      fi
      ;;
  esac
fi

# ── Hook status badges (written by UserPromptSubmit hooks) ───────────────────
# Hooks write ~/.claude/.hook-status-$PPID with a short display string.
# This section is generic — the hook controls what text is shown.
HOOK_STATUS_SEG=""
_HOOK_STATUS_FILE="${HOME}/.claude/.hook-status-${PPID}"
if [[ -f "$_HOOK_STATUS_FILE" && ! -L "$_HOOK_STATUS_FILE" ]]; then
  _hook_text=$(head -c 128 "$_HOOK_STATUS_FILE" 2>/dev/null | tr -d '\000-\037\177')
  [[ -n "$_hook_text" ]] && HOOK_STATUS_SEG=" ${C_DIM}│${RST} ${C_TEAL}${_hook_text}${RST}"
fi

# ── Vim mode ─────────────────────────────────────────────────
VIM_SEG=""
if [[ -n "$VIM_MODE" ]]; then
  case "$VIM_MODE" in
    NORMAL) VIM_SEG=" ${C_BLUE}${BOLD} N${RST}" ;;
    INSERT) VIM_SEG=" ${C_GREEN}${BOLD} I${RST}" ;;
    *)      VIM_SEG=" ${C_YELLOW}${BOLD} ${VIM_MODE}${RST}" ;;
  esac
fi

# ── Worktree ─────────────────────────────────────────────────
# Session name intentionally omitted – duplicated by tmux tab name + CC title.
WORKTREE_SEG=""
if [[ -n "$WORKTREE_NAME" ]]; then
  WORKTREE_SEG=" ${C_DIM}│${RST} ${C_ORANGE}⎇ ${WORKTREE_NAME}${RST}"
  [[ -n "$WORKTREE_BRANCH" ]] && WORKTREE_SEG="${WORKTREE_SEG}${C_DIM}:${WORKTREE_BRANCH}${RST}"
fi

# ── Directory + git ──────────────────────────────────────────
DIR_SHORT="${DIR##*/}"
[[ "$DIR" == "$HOME" ]] && DIR_SHORT="~"
DIR_SEG="${C_CYAN}📁 ${DIR_SHORT}${RST}"

GIT_SEG=""
if [[ -n "$GIT_BRANCH" ]]; then
  GIT_SEG="${C_DIM}│${RST} ${C_GREEN} ${GIT_BRANCH}${RST}"
  [[ -n "$GIT_DIRTY" ]] && GIT_SEG="${GIT_SEG}${C_YELLOW} ${GIT_DIRTY}${RST}"
  [[ -n "$GIT_AHEAD" ]] && GIT_SEG="${GIT_SEG} ${C_GREEN}${GIT_AHEAD}${RST}"
  [[ -n "$GIT_BEHIND" ]] && GIT_SEG="${GIT_SEG} ${C_RED}${GIT_BEHIND}${RST}"
fi

# ── Context window ───────────────────────────────────────────
CTX_BAR=$(pbar "${CTX_USED}" 12)
CTX_WARN=""
(( CTX_USED >= 85 )) && CTX_WARN=" ${C_RED}${BOLD}⚠${RST}"
[[ "$EXCEEDS_200K" == "true" ]] && CTX_WARN="${CTX_WARN} ${C_ORANGE}200k+${RST}"
CTX_SEG="${C_WHITE}ctx${RST} ${CTX_BAR} ${C_BRIGHT}${CTX_USED}%${RST}${CTX_WARN}"

# ── Tokens (main session + all subagents recursively) ────────
TOK_IN_FMT=$(fmt_tokens "$TOT_IN_ALL")
TOK_OUT_FMT=$(fmt_tokens "$TOT_OUT_ALL")
SUB_TAG=""
(( SUB_COUNT > 0 )) && SUB_TAG=" ${C_DIM}+${SUB_COUNT}sa${RST}"
TOK_SEG="${C_DIM}│${RST} ${C_BLUE}↓${TOK_IN_FMT}${RST} ${C_PURPLE}↑${TOK_OUT_FMT}${RST}${SUB_TAG}"

TOK_SPEED_SEG=""
if (( API_MS > 0 && TOT_OUT_ALL > 0 )); then
  SPEED=$(( (TOT_OUT_ALL * 1000) / API_MS ))
  TOK_SPEED_SEG=" ${C_DIM}(${SPEED} tok/s)${RST}"
fi

CACHE_SEG=""
CACHE_TOTAL=$((CACHE_READ + CACHE_CREATE))
if (( CACHE_TOTAL > 0 )); then
  CACHE_HIT=$(( (CACHE_READ * 100) / CACHE_TOTAL ))
  CACHE_SEG=" ${C_DIM}│${RST} ${C_CYAN}⚡${CACHE_HIT}% cache${RST}"
fi

# ── Duration (cost intentionally omitted) ────────────────────
DUR_FMT=$(fmt_duration "$DURATION_MS")
API_DUR_FMT=$(fmt_duration "$API_MS")
TIME_SEG="${C_CYAN}⏱ ${DUR_FMT}${RST} ${C_DIM}(${API_DUR_FMT} api)${RST}"

# ── Lines changed ────────────────────────────────────────────
LINES_SEG=""
(( LINES_ADD > 0 || LINES_DEL > 0 )) && LINES_SEG=" ${C_DIM}│${RST} ${C_GREEN}+${LINES_ADD}${RST} ${C_RED}-${LINES_DEL}${RST}"

# ── Rate limits ──────────────────────────────────────────────
# Color helper for compact remaining % (narrow mode).
remaining_color() {
  local p=$1
  if (( p <= 10 )); then printf '%s' "$C_RED"
  elif (( p <= 25 )); then printf '%s' "$C_ORANGE"
  elif (( p <= 50 )); then printf '%s' "$C_YELLOW"
  else printf '%s' "$C_GREEN"; fi
}

RATE_SEG=""           # rich – with progress bar + reset countdown
RATE_SEG_COMPACT=""   # compact – mini bar + colored % + reset countdown
RL5_INT=""; RL7_INT=""
if [[ -n "$RL_5H_PCT" ]]; then
  RL5_INT=${RL_5H_PCT%%.*}
  RL5_LEFT=$(pct_remaining "$RL5_INT")
  RL5_BAR=$(pbar_remaining "$RL5_LEFT" 8 dots)
  RL5_BAR_MINI=$(pbar_remaining "$RL5_LEFT" 4 dots)
  RL5_RESET=$(fmt_reset_time "$RL_5H_RESET")
  RATE_SEG="${C_WHITE}5h${RST} ${RL5_BAR} ${C_BRIGHT}${RL5_LEFT}% left${RST}"
  [[ -n "$RL5_RESET" ]] && RATE_SEG="${RATE_SEG} ${C_DIM}⟳${RL5_RESET}${RST}"
  c=$(remaining_color "$RL5_LEFT")
  RATE_SEG_COMPACT="${C_WHITE}5h${RST} ${RL5_BAR_MINI} ${c}${BOLD}${RL5_LEFT}%${RST}"
  [[ -n "$RL5_RESET" ]] && RATE_SEG_COMPACT="${RATE_SEG_COMPACT} ${C_DIM}⟳${RL5_RESET}${RST}"
fi
if [[ -n "$RL_7D_PCT" ]]; then
  RL7_INT=${RL_7D_PCT%%.*}
  RL7_LEFT=$(pct_remaining "$RL7_INT")
  RL7_BAR=$(pbar_remaining "$RL7_LEFT" 8 dots)
  RL7_BAR_MINI=$(pbar_remaining "$RL7_LEFT" 4 dots)
  RL7_RESET=$(fmt_reset_time "$RL_7D_RESET")
  [[ -n "$RATE_SEG" ]] && RATE_SEG="${RATE_SEG} ${C_DIM}│${RST} "
  RATE_SEG="${RATE_SEG}${C_WHITE}7d${RST} ${RL7_BAR} ${C_BRIGHT}${RL7_LEFT}% left${RST}"
  [[ -n "$RL7_RESET" ]] && RATE_SEG="${RATE_SEG} ${C_DIM}⟳${RL7_RESET}${RST}"
  c=$(remaining_color "$RL7_LEFT")
  [[ -n "$RATE_SEG_COMPACT" ]] && RATE_SEG_COMPACT="${RATE_SEG_COMPACT} "
  RATE_SEG_COMPACT="${RATE_SEG_COMPACT}${C_WHITE}7d${RST} ${RL7_BAR_MINI} ${c}${BOLD}${RL7_LEFT}%${RST}"
  [[ -n "$RL7_RESET" ]] && RATE_SEG_COMPACT="${RATE_SEG_COMPACT} ${C_DIM}⟳${RL7_RESET}${RST}"
fi

# Compact ctx (no bar) for narrow mode.
CTX_SEG_COMPACT="${C_WHITE}ctx${RST} ${C_BRIGHT}${BOLD}${CTX_USED}%${RST}${CTX_WARN}"

# ── Version ──────────────────────────────────────────────────
VER_SEG="${C_DIM}v${VERSION}${RST}"

# ═══════════════════════════════════════════════════════════════
# ── Assemble (printf %s – no escape interpretation on data) ──
# ═══════════════════════════════════════════════════════════════

if (( NARROW )); then
  # ── Narrow mode (half-width tmux pane etc.) ──
  # Three lines so rate limits keep the full bar + countdown treatment.
  # L1: model │ dir │ git
  L1="${MODEL_SEG}${CAVEMAN_SEG}${HOOK_STATUS_SEG} ${C_DIM}│${RST} ${DIR_SEG} ${GIT_SEG}"

  # L2: ctx │ tokens
  L2="${CTX_SEG_COMPACT} ${C_DIM}│${RST} ${C_BLUE}↓${TOK_IN_FMT}${RST} ${C_PURPLE}↑${TOK_OUT_FMT}${RST}${SUB_TAG}"

  # L3: rate limits (full form – critical signal, deserves real estate)
  L3_RATE="$RATE_SEG"
else
  # Line 1: Model │ Dir │ Git │ Worktree │ Vim │ Version
  L1="${MODEL_SEG}${CAVEMAN_SEG}${HOOK_STATUS_SEG}${WORKTREE_SEG} ${C_DIM}│${RST} ${DIR_SEG} ${GIT_SEG}${VIM_SEG} ${C_DIM}│${RST} ${VER_SEG}"

  # Line 2: Context │ Tokens │ Cache │ Time │ Lines │ Rate limits
  L2="${CTX_SEG} ${TOK_SEG}${TOK_SPEED_SEG}${CACHE_SEG} ${C_DIM}│${RST} ${TIME_SEG}${LINES_SEG}"
  [[ -n "$RATE_SEG" ]] && L2="${L2} ${C_DIM}│${RST} ${RATE_SEG}"
  L3_RATE=""
fi

# Optional extra line: in narrow mode this is the rate-limits line; in
# wide mode it's running agents + task progress (with rate limits already
# embedded in L2).
L3=""
if [[ -n "$L3_RATE" ]]; then
  L3="$L3_RATE"
fi
if [[ -n "$AGENT_DISPLAY" || -n "$TASK_DISPLAY" ]]; then
  AGENTS_LINE="${AGENT_DISPLAY}${SUBAGENT_EXTRA}"
  [[ -n "$AGENT_DISPLAY" && -n "$TASK_DISPLAY" ]] && AGENTS_LINE="${AGENTS_LINE} ${C_DIM}│${RST} "
  AGENTS_LINE="${AGENTS_LINE}${TASK_DISPLAY}"
  if [[ -n "$L3" ]]; then
    L4="$AGENTS_LINE"
  else
    L3="$AGENTS_LINE"
  fi
fi

printf '%s\n' "$L1"
printf '%s\n' "$L2"
[[ -n "$L3" ]] && printf '%s\n' "$L3"
[[ -n "${L4:-}" ]] && printf '%s\n' "$L4"

exit 0
