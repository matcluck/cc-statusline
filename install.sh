#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Configure Claude Code to use this checkout's statusline-command.sh.

Options:
  --settings FILE   Claude settings file to update
                    default: $HOME/.claude/settings.json
  --script FILE     Statusline script path to install
                    default: ./statusline-command.sh from this checkout
  --no-backup       Do not create a timestamped settings backup
  --dry-run         Print the updated JSON without writing it
  -h, --help        Show this help
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
statusline_script="$script_dir/statusline-command.sh"
settings_file="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
make_backup=1
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --settings)
      [[ $# -ge 2 ]] || { echo "error: --settings requires a file path" >&2; exit 2; }
      settings_file=$2
      shift 2
      ;;
    --script)
      [[ $# -ge 2 ]] || { echo "error: --script requires a file path" >&2; exit 2; }
      statusline_script=$2
      shift 2
      ;;
    --no-backup)
      make_backup=0
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to update Claude settings" >&2
  exit 1
fi

if [[ ! -f "$statusline_script" ]]; then
  echo "error: statusline script not found: $statusline_script" >&2
  exit 1
fi

statusline_script=$(realpath "$statusline_script")
settings_dir=$(dirname -- "$settings_file")
tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.base"' EXIT

mkdir -p "$settings_dir"

if [[ -f "$settings_file" ]]; then
  jq empty "$settings_file" >/dev/null
  cp "$settings_file" "$tmp.base"
  if (( make_backup && ! dry_run )); then
    cp "$settings_file" "$settings_file.bak.$(date +%Y%m%d-%H%M%S)"
  fi
else
  printf '{}\n' > "$tmp.base"
fi

jq --arg command "bash $statusline_script" '
  .statusLine = {
    "type": "command",
    "command": $command
  }
' "$tmp.base" > "$tmp"

if (( dry_run )); then
  cat "$tmp"
  exit 0
fi

mv "$tmp" "$settings_file"
trap - EXIT
rm -f "$tmp.base"

echo "Installed Claude Code statusline:"
echo "  settings: $settings_file"
echo "  command:  bash $statusline_script"
echo
echo "Restart Claude Code or trigger a statusline refresh to pick it up."
