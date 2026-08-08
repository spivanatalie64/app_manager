# gitw command: tree — status of managed engine trees.
# The app_manager value-add: keeps an eye on the vendored source trees that
# the clone/build scripts are supposed to manage.
#
# Which trees are watched comes from config key `managed_repos`
# (space-separated paths, relative to GITW_APP_ROOT).
gitw_usage_tree() { printf 'status of managed engine trees (servo/chromium/depot_tools)'; }

gitw_cmd_tree() {
  local root="$GITW_APP_ROOT"
  local repos
  repos="$(gitw_config_get managed_repos 2>/dev/null || true)"
  [ -n "$repos" ] || repos="servo_src/servo chromium_src/src depot_tools"

  gitw_msg "$(gitw_bold "managed trees")  (root: $root)"
  local r dir branch head dirty
  for r in $repos; do
    dir="$root/$r"
    if [ -d "$dir/.git" ]; then
      branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
      if [ "$branch" = "HEAD" ]; then
        branch="detached@$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
      fi
      branch="${branch:-?}"
      head="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
      dirty="$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      dirty="${dirty:-0}"
      printf '  %-34s %-16s %s' "$r" "$branch" "$head"
      [ "$dirty" -gt 0 ] 2>/dev/null && printf '  (%s dirty)' "$dirty"
      printf '\n'
    else
      printf '  %-34s %s\n' "$r" "$(gitw_yellow "missing ($dir)")"
    fi
  done
}
