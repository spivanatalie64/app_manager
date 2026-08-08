# gitw command: pr — pull request info for the current branch (needs gh).
gitw_usage_pr() { printf 'show PR for current branch (requires gh + network)'; }

gitw_cmd_pr() {
  gitw_require_repo

  if ! command -v gh >/dev/null 2>&1; then
    gitw_die "gh CLI not found — install it, or use 'gitw status --no-pr'"
  fi
  gh pr view "$@"
}
