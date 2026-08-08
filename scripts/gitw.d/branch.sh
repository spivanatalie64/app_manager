# gitw command: branch — current branch, upstream, divergence, last commit.
gitw_usage_branch() { printf 'show current branch, upstream, divergence, last commit'; }

gitw_cmd_branch() {
  gitw_require_repo

  local branch upstream ahead behind last
  branch="$(gitw_current_branch 2>/dev/null || echo '?')"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  ahead=0; behind=0
  if [ -n "$upstream" ]; then
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    behind="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
  fi
  last="$(git log -1 --pretty=format:'%h %s (%ar)' 2>/dev/null || true)"

  gitw_msg "$(gitw_bold "branch:")   $(gitw_cyan "$branch")"
  if [ -n "$upstream" ]; then
    gitw_msg "$(gitw_bold "upstream:") $upstream  (ahead $(gitw_green "$ahead") / behind $(gitw_red "$behind"))"
  else
    gitw_msg "$(gitw_bold "upstream:") $(gitw_yellow "none")"
  fi
  [ -n "$last" ] && gitw_msg "$(gitw_bold "last:")     $last"
}
