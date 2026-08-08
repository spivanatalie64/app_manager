# gitw command: log — recent commits with color.
# Usage: gitw log [N] [git log args...]
gitw_usage_log() { printf 'show recent commits (gitw log [N] [args...])'; }

gitw_cmd_log() {
  gitw_require_repo

  local n=15 extra=() out
  if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    n="$1"; shift
  fi
  extra=("$@")

  # Normalize through $() so the output always ends with a newline.
  out="$(git log --oneline --decorate -n "$n" "${extra[@]}" \
    --pretty=format:'%C(yellow)%h%Creset %s' 2>/dev/null || true)"
  printf '%s\n' "$out"
}
