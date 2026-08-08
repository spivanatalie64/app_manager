# gitw command: status — repository state + PR context (ace-git style).
gitw_usage_status() { printf 'status -f text|json -c N --no-pr'; }

gitw_cmd_status() {
  gitw_require_repo

  local no_pr=0 format="text" commits_override=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-pr) no_pr=1 ;;
      -f|--format) format="${2:-text}"; shift ;;
      -c|--commits) commits_override="${2:-}"; shift ;;
      -h|--help) gitw_usage_status; printf '\n'; return 0 ;;
      *) gitw_warn "status: unknown option: $1"; return 2 ;;
    esac
    shift
  done

  case "$format" in
    text|json) ;;
    *) gitw_warn "status: unknown format: $format"; return 2 ;;
  esac

  local branch upstream ahead behind
  branch="$(gitw_current_branch 2>/dev/null || echo '?')"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  ahead=0; behind=0
  if [ -n "$upstream" ]; then
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    behind="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
  fi

  local counts staged unstaged untracked rest
  counts="$(git status --porcelain 2>/dev/null | awk '
    { x = substr($0,1,1); y = substr($0,2,1) }
    x == "?" { untracked++ }
    x != " " && x != "?" { staged++ }
    y != " " && y != "?" { unstaged++ }
    END { printf "%d %d %d", staged, unstaged, untracked }')"
  staged="${counts%% *}"; rest="${counts#* }"
  unstaged="${rest%% *}"; untracked="${rest##* }"

  if [ "$format" = json ]; then
    printf '{\n'
    printf '  "branch": "%s",\n'    "$(gitw_json_escape "$branch")"
    printf '  "upstream": "%s",\n'  "$(gitw_json_escape "$upstream")"
    printf '  "ahead": %d,\n'       "$ahead"
    printf '  "behind": %d,\n'      "$behind"
    printf '  "staged": %d,\n'      "$staged"
    printf '  "unstaged": %d,\n'    "$unstaged"
    printf '  "untracked": %d\n'    "$untracked"
    printf '}\n'
    return 0
  fi

  local limit
  if [ -n "$commits_override" ]; then
    limit="$commits_override"
  else
    limit="$(gitw_config_get status.commits_limit 2>/dev/null || echo 3)"
  fi
  case "$limit" in
    ''|*[!0-9]*) limit=3 ;;
  esac

  gitw_msg "$(gitw_bold "branch:")   $(gitw_cyan "$branch")${upstream:+ -> $upstream}"
  if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
    gitw_msg "  $(gitw_green "ahead $ahead") / $(gitw_red "behind $behind")"
  fi
  gitw_msg "  staged: $(gitw_green "$staged")  unstaged: $(gitw_red "$unstaged")  untracked: $(gitw_yellow "$untracked")"

  if [ "$limit" -gt 0 ] 2>/dev/null; then
    local commits
    # NOTE: git log --pretty=format emits no trailing newline, and this bash
    # build drops the final unterminated line in a `while read` loop. Normalize
    # through command substitution + printf to guarantee a trailing newline.
    commits="$(git log -n "$limit" --pretty=format:'  %h %s' 2>/dev/null || true)"
    gitw_msg ""
    gitw_msg "$(gitw_bold "recent commits:")"
    [ -n "$commits" ] && printf '%s\n' "$commits" | while IFS= read -r line; do
      gitw_msg "$line"
    done
  fi

  if [ "$no_pr" = 0 ] && [ "$(gitw_config_get status.pr 2>/dev/null || echo yes)" = yes ] \
     && command -v gh >/dev/null 2>&1; then
    local pr
    if pr="$(gh pr view --json number,title,state \
              --jq '"#" + (.number|tostring) + " " + .state + " " + .title' 2>/dev/null)"; then
      gitw_msg ""
      gitw_msg "$(gitw_bold "pr:")       $pr"
    fi
  fi
}
