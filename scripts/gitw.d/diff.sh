# gitw command: diff — filtered, formatted diff output.
# Bare ranges route here automatically (see gitw_is_range in the main script).
#
# Flags (ported from ace-git diff):
#   -f, --format  diff|summary|grouped-stats
#   -s, --since   WHEN        changes since date/duration (e.g. '7d', 'yesterday')
#   -p, --pattern GLOB        include paths (native git pathspec, repeatable)
#   -e, --exclude GLOB        exclude paths (glob->regex filtered, repeatable)
#   -o, --output  FILE        write to file (validated); '-' means stdout
#   --raw                     ignore configured exclude_patterns
gitw_usage_diff() { printf 'diff -f diff|summary|grouped-stats -s SINCE -p PAT -e GLOB -o FILE --raw'; }

# Shared awk library: glob -> regex + exclusion matcher (ace PatternFilter port).
GITW_AWK_GLOB='function glob_to_regex(pattern,   r, i, c) {
      r = ""
      for (i = 1; i <= length(pattern); i++) {
        c = substr(pattern, i, 1)
        if (c == "*") {
          if (substr(pattern, i + 1, 1) == "*") {
            if (substr(pattern, i + 2, 1) == "/") { r = r ".*"; i += 2 }
            else { r = r ".*"; i += 1 }
          } else r = r "[^/]*"
        } else if (c == "?") r = r "."
        else if (c ~ /[][{}()|+^$.\/]/) r = r "\\" c
        else r = r c
      }
      return "^" r
    }
    function compile_patterns() {
      n = split(ENVIRON["GITW_EXCLUDE_PATTERNS"], plist, "\n")
      for (i = 1; i <= n; i++) if (plist[i] != "") { npat++; pats[npat] = glob_to_regex(plist[i]) }
    }
    function path_excluded(p,   j) {
      if (p == "") return 0
      for (j = 1; j <= npat; j++) if (p ~ pats[j]) return 1
      return 0
    }'

# Filter a unified diff by path (skips whole file hunks that match excludes).
gitw_exclude_diff() { # stdin = diff text, $1 = newline-joined exclude patterns
  GITW_EXCLUDE_PATTERNS="$1" awk "$GITW_AWK_GLOB"$'\n''
    BEGIN { compile_patterns() }
    function is_header(l) {
      return l ~ /^diff --git / || l ~ /^index [0-9a-f]/ || l ~ /^--- / || l ~ /^\+\+\+ /
    }
    function extract_path(l,   m) {
      if (match(l, /^\+\+\+ b\/(.*)$/, m)) return m[1]
      if (match(l, /^diff --git a\/[^ ]* b\/(.*)$/, m)) return m[1]
      if (match(l, /^--- a\/(.*)$/, m)) return m[1]
      return ""
    }
    {
      if (is_header($0)) {
        if (path_excluded(extract_path($0))) skip = 1
        else { skip = 0; print }
      } else if (!skip) print
    }'
}

# Filter numstat lines by path.
gitw_exclude_numstat() { # stdin = numstat, $1 = newline-joined exclude patterns
  GITW_EXCLUDE_PATTERNS="$1" awk "$GITW_AWK_GLOB"$'\n''
    BEGIN { compile_patterns() }
    NF == 3 { if (!path_excluded($3)) print; next }
    { print }'
}

# Aggregate numstat per top-level directory.
gitw_aggregate_summary() { # stdin = (filtered) numstat
  local body
  body="$(awk '
    NF == 3 {
      add += $1; del += $2; files++
      dir = $3; sub(/\/[^/]*$/, "", dir); if (dir == "") dir = "(root)"
      adds[dir] += $1; dels[dir] += $2; fcount[dir]++
    }
    END {
      if (files == 0) { print "(no changes)"; exit }
      for (d in adds) printf "%-28s %4d files  +%d  -%d\n", d, fcount[d], adds[d], dels[d]
      printf "TOTAL: %d files  +%d  -%d\n", files, add, del
    }')"
  if [ -z "$body" ] || [ "$body" = "(no changes)" ]; then
    printf '(no changes)\n'
    return 0
  fi
  printf '%s\n' "$body" | grep -v '^TOTAL:' | sort
  printf '%s\n' "$body" | grep '^TOTAL:'
}

# Aggregate numstat grouped by first path segment, collapsing small groups.
gitw_aggregate_grouped() { # stdin = numstat, $1 = collapse threshold (changes)
  local collapse="${1:-5}" body
  body="$(awk -v c="$collapse" '
    NF == 3 {
      add += $1; del += $2; files++
      dir = $3; sub(/\/.*$/, "", dir); if (dir == "") dir = "(root)"
      adds[dir] += $1; dels[dir] += $2; fcount[dir]++; chg[dir] += $1 + $2
    }
    END {
      if (files == 0) { print "(no changes)"; exit }
      for (d in adds) {
        if (chg[d] <= c) { oa += adds[d]; od += dels[d]; of += fcount[d] }
        else printf "%-20s %4d files  +%d  -%d\n", d, fcount[d], adds[d], dels[d]
      }
      if (of > 0) printf "%-20s %4d files  +%d  -%d\n", "(other)", of, oa, od
      printf "TOTAL: %d files  +%d  -%d\n", files, add, del
    }')"
  if [ -z "$body" ] || [ "$body" = "(no changes)" ]; then
    printf '(no changes)\n'
    return 0
  fi
  printf '%s\n' "$body" | grep -v '^TOTAL:' | sort
  printf '%s\n' "$body" | grep '^TOTAL:'
}

gitw_cmd_diff() {
  gitw_require_repo

  local format="" since="" output="" raw=0
  local pattern=() excludes=() passthrough=()
  format="$(gitw_config_get diff.format 2>/dev/null || echo diff)"

  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--format) format="${2:-diff}"; shift ;;
      -s|--since)  since="${2:-}"; shift ;;
      -p|--pattern) pattern+=("${2:-}"); shift ;;
      -e|--exclude) excludes+=("${2:-}"); shift ;;
      -o|--output) output="${2:-}"; shift ;;
      --raw) raw=1 ;;
      -h|--help) gitw_usage_diff; printf '\n'; return 0 ;;
      *) passthrough+=("$1") ;;
    esac
    shift
  done

  case "$format" in
    diff|normal) format=diff ;;
    summary|grouped-stats) ;;
    *) gitw_warn "diff: unknown format: $format"; return 2 ;;
  esac

  local conf_exclude
  if [ "$raw" = 0 ]; then
    conf_exclude="$(gitw_config_get diff.exclude_patterns 2>/dev/null || true)"
    if [ -n "$conf_exclude" ]; then
      # shellcheck disable=SC2206
      excludes+=($conf_exclude)
    fi
  fi

  local since_ref=""
  if [ -n "$since" ]; then
    since_ref="$(command git rev-list -1 --before="$since" HEAD 2>/dev/null || true)"
    [ -n "$since_ref" ] || gitw_warn "diff: --since '$since' did not resolve; ignoring"
  fi

  local args=()
  [ -n "$since_ref" ] && args+=("$since_ref")
  args+=("${passthrough[@]}")

  local content="" numstat=""
  if [ "$format" = diff ]; then
    content="$(gitw_git diff "${args[@]}")"
    if [ ${#pattern[@]} -gt 0 ]; then
      content="$(gitw_git diff "${args[@]}" -- "${pattern[@]}")"
    fi
    if [ "$raw" = 0 ] && [ ${#excludes[@]} -gt 0 ]; then
      content="$(printf '%s\n' "$content" | gitw_exclude_diff "$(printf '%s\n' "${excludes[@]}")")"
    fi
  else
    numstat="$(gitw_git diff --numstat "${args[@]}" 2>/dev/null)"
    if [ "$raw" = 0 ] && [ ${#excludes[@]} -gt 0 ]; then
      numstat="$(printf '%s\n' "$numstat" | gitw_exclude_numstat "$(printf '%s\n' "${excludes[@]}")")"
    fi
    if [ "$format" = summary ]; then
      content="$(printf '%s\n' "$numstat" | gitw_aggregate_summary)"
    else
      local collapse
      collapse="$(gitw_config_get diff.grouped_stats_collapse_above 2>/dev/null || echo 5)"
      content="$(printf '%s\n' "$numstat" | gitw_aggregate_grouped "$collapse")"
    fi
  fi

  [ -z "$content" ] && content="(no changes)"

  if [ -n "$output" ] && [ "$output" != "-" ]; then
    gitw_validate_output_path "$output" || return 1
    mkdir -p "$(dirname "$output")" 2>/dev/null || true
    printf '%s\n' "$content" > "$output"
    gitw_warn "diff written to: $output"
  else
    printf '%s\n' "$content"
  fi
  return 0
}
