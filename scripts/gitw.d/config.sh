# gitw command: config — show the resolved config cascade.
# precedence: project (.gitw/config) > user (~/.config/gitw/config) > defaults
gitw_usage_config() { printf 'show resolved config cascade (project > user > defaults)'; }

gitw_cmd_config() {
  local key
  if [ $# -gt 0 ]; then
    if key="$(gitw_config_get "$1")"; then
      printf '%s = %s\n' "$1" "$key"
    else
      gitw_warn "config: no value for '$1'"
      return 1
    fi
    return 0
  fi

  local k
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    printf '%s = %s\n' "$k" "$(gitw_config_get "$k")"
  done < <(gitw_config_list)
}
