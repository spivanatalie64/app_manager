# gitw atoms: safe git execution + helpers.
# Port of ace-git's CommandExecutor and related pure helpers.
#
# Self-contained (no dependency on the main gitw script) so it can be sourced
# standalone for testing:
#   source /path/to/gitw.d/exec.sh

# Matches git's lock-file failure messages.
GITW_LOCK_RE='(index\.lock|\.lock): File exists|Unable to create .*\.lock|Another git process seems to be running'

# Read a config value if the full config cascade is available (sourced via gitw),
# otherwise fall back to the given default.
gitw_lock_setting() {
  local key="$1" def="$2"
  if declare -F gitw_config_get >/dev/null 2>&1; then
    local v
    if v="$(gitw_config_get "$key" 2>/dev/null)"; then
      printf '%s' "$v"
      return 0
    fi
  fi
  printf '%s' "$def"
}

# gitw_git — run git with lock-retry + stale-lock cleanup (ace CommandExecutor port).
#   - retries on .git/index.lock errors with progressive delays (1s, 2s, 3s, ...)
#   - reaps orphaned (dead PID) or stale (> threshold seconds) locks between retries
#   - stdout passes through untouched; stderr is captured and replayed only on failure
# Configure via lock_retry.enabled / lock_retry.max_retries / lock_retry.stale_threshold_seconds
gitw_git() {
  local tmp err attempt=0 max_retries threshold

  if [ "$(gitw_lock_setting lock_retry.enabled yes)" != "yes" ]; then
    command git "$@"
    return $?
  fi

  max_retries="$(gitw_lock_setting lock_retry.max_retries 4)"
  case "$max_retries" in ''|*[!0-9]*) max_retries=4 ;; esac
  threshold="$(gitw_lock_setting lock_retry.stale_threshold_seconds 10)"
  case "$threshold" in ''|*[!0-9]*) threshold=10 ;; esac

  tmp="$(mktemp)"
  while :; do
    if command git "$@" 2>"$tmp"; then
      rm -f "$tmp"
      return 0
    fi
    err=$?

    # Not a lock error: replay stderr and propagate the exit code.
    if ! grep -qE "$GITW_LOCK_RE" "$tmp" 2>/dev/null; then
      cat "$tmp" >&2
      rm -f "$tmp"
      return "$err"
    fi

    if [ "$attempt" -ge "$max_retries" ]; then
      cat "$tmp" >&2
      rm -f "$tmp"
      printf 'gitw: git index locked after %s retries\n' "$max_retries" >&2
      return "$err"
    fi

    gitw_clean_stale_locks "$threshold"
    rm -f "$tmp"
    tmp="$(mktemp)"
    printf 'gitw: lock detected, retrying in %ss\n' "$((attempt + 1))" >&2
    sleep "$((attempt + 1))"
    attempt=$((attempt + 1))
  done
}

# gitw_clean_stale_locks — remove .git/index.lock if held by a dead PID
# or older than the threshold. Uses plain `command git` (no recursion).
gitw_clean_stale_locks() {
  local threshold="${1:-10}" root lock pid age now
  root="$(command git rev-parse --show-toplevel 2>/dev/null)" || return 0
  lock="$root/.git/index.lock"
  [ -e "$lock" ] || return 0

  # Orphaned PID first: git lock files start with "<pid> <hostname>".
  pid="$(head -n 1 "$lock" 2>/dev/null | awk '{print $1}')"
  case "$pid" in
    ''|*[!0-9]*) pid="" ;;
  esac
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$lock" 2>/dev/null
    printf 'gitw: removed orphaned index.lock (PID %s)\n' "$pid" >&2
    return 0
  fi

  # Age check: lock older than threshold is stale.
  now="$(date +%s 2>/dev/null || echo 0)"
  age="$(stat -c %Y "$lock" 2>/dev/null)"
  if [ -n "$age" ] && [ -n "$now" ] && [ $((now - age)) -gt "$threshold" ] 2>/dev/null; then
    rm -f "$lock" 2>/dev/null
    printf 'gitw: removed stale index.lock (age %ss)\n' "$((now - age))" >&2
  fi
  return 0
}

# gitw_current_branch — branch name, or short SHA when HEAD is detached
# (ace CommandExecutor.current_branch behavior).
gitw_current_branch() {
  local b
  b="$(command git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  if [ "$b" = "HEAD" ]; then
    command git rev-parse --short HEAD 2>/dev/null || return 1
    return 0
  fi
  printf '%s' "$b"
}

# gitw_validate_output_path — path-traversal guard (ace diff --output port).
# Rejects ".."; output must resolve inside cwd or TMPDIR.
# (NUL-byte check intentionally omitted: bash argv/variables cannot contain NULs,
#  and a `*$'\0'*` case pattern truncates at the NUL and matches everything.)
gitw_validate_output_path() {
  local path="$1" cwd tmp abs
  case "$path" in
    *".."*)
      printf 'gitw: invalid output path: ".." not allowed\n' >&2
      return 1 ;;
  esac
  cwd="$(pwd -P 2>/dev/null || pwd)"
  tmp="$(cd "${TMPDIR:-/tmp}" >/dev/null 2>&1 && pwd -P || printf '%s' "${TMPDIR:-/tmp}")"
  abs="$path"
  case "$abs" in
    /*) ;;
    *) abs="$cwd/$abs" ;;
  esac
  if [ -e "$abs" ]; then
    abs="$(realpath "$abs" 2>/dev/null || printf '%s' "$abs")"
  fi
  case "$abs" in
    "$cwd"|"$cwd"/*|"$tmp"|"$tmp"/*) return 0 ;;
  esac
  printf 'gitw: invalid output path: must be inside cwd or %s\n' "$tmp" >&2
  return 1
}

# gitw_json_escape — minimal JSON string escaping for hand-rolled JSON output.
gitw_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
