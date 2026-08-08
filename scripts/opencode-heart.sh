#!/usr/bin/env bash
#
# opencode-heart.sh — give OpenCode a beating-heart loading animation
#
# OpenCode's loading spinner frames are hardcoded in the binary as
# fixed-width "\uXXXX" escape sequences. We swap in a 6-frame beating
# heart (⠉⠉ ⠛⠛ ⠿⠿ ⢿⡿ ⠿⠿ ⠛⠛) which is byte-for-byte the same
# length as the original 10-frame braille dot spinner, so the binary
# doesn't need to be rebuilt — just patched in place.
#
# Usage:
#   ./opencode-heart.sh patch    # apply the heart animation
#   ./opencode-heart.sh restore  # restore the original spinner
#   ./opencode-heart.sh status   # show current state
#
# Note: `opencode upgrade` will overwrite the patch. Re-run `patch`
# after upgrading.

set -euo pipefail

BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
BACKUP="$BIN.orig-heart"

# Original 10-frame braille dot spinner
ORIGINAL='["\u280B","\u2819","\u2839","\u2838","\u283C","\u2834","\u2826","\u2827","\u2807","\u280F"]'

# Beating heart: ⠉⠉ ⠛⠛ ⠿⠿ ⢿⡿ ⠿⠿ ⠛⠛  (same byte length, 91)
HEART='["\u2809\u2809","\u281B\u281B","\u283F\u283F","\u28BF\u287F","\u283F\u283F","\u281B\u281B"]'

if [[ ! -f "$BIN" ]]; then
  echo "error: $BIN not found. Set OPENCODE_BIN to point at your opencode binary." >&2
  exit 1
fi

needle_original=$(python3 -c 'import sys; sys.stdout.buffer.write(sys.argv[1].encode())' "$ORIGINAL")
needle_heart=$(python3 -c 'import sys; sys.stdout.buffer.write(sys.argv[1].encode())' "$HEART")

# Safety: byte lengths must match exactly
len_o=${#needle_original}
len_h=${#needle_heart}
if (( len_o != len_h )); then
  echo "error: replacement length mismatch ($len_o vs $len_h bytes) — aborting." >&2
  exit 1
fi

count_hits() {
  python3 - "$1" "$BIN" <<'PYEOF'
import sys
needle = sys.argv[1].encode()
data = open(sys.argv[2], 'rb').read()
print(data.count(needle))
PYEOF
}

patch() {
  if [[ -f "$BACKUP" ]]; then
    echo "  backup already exists: $BACKUP"
  else
    echo "  backing up original to $BACKUP"
    cp -p "$BIN" "$BACKUP"
  fi

  local ocount hcount
  ocount=$(count_hits "$ORIGINAL" "$BIN")
  hcount=$(count_hits "$HEART" "$BIN")

  if (( hcount >= 1 && ocount == 0 )); then
    echo "  already patched — nothing to do."
    return 0
  fi

  if (( ocount == 0 )); then
    echo "error: original spinner frames not found ($ocount hits)." >&2
    echo "       This opencode build may differ; refusing to touch it." >&2
    exit 1
  fi

  echo "  found $ocount copy/copies of the original spinner — patching..."
  local tmp
  tmp="$(mktemp "$BIN.XXXXXX")"
  python3 - "$BIN" "$ORIGINAL" "$HEART" "$tmp" <<'PYEOF'
import sys, os
path, old, new, out = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode(), sys.argv[4]
with open(path, 'rb') as f:
    data = f.read()
assert len(old) == len(new), "length mismatch!"
count = data.count(old)
if count == 0:
    print("  (no occurrences — already patched?)")
    sys.exit(0)
data = data.replace(old, new)
with open(out, 'wb') as f:
    f.write(data)
os.chmod(out, os.stat(path).st_mode)
print(f"  patched {count} copy/copies in {path}")
PYEOF
  # mv (rename) works even while the binary is running; the old inode
  # stays alive for the running process.
  chmod +x "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$BIN"
  echo "  done! Restart opencode to see the beating heart. <3"
}

restore() {
  if [[ ! -f "$BACKUP" ]]; then
    echo "  no backup found at $BACKUP — nothing to restore."
    return 0
  fi

  local ocount
  ocount=$(count_hits "$ORIGINAL" "$BIN")
  if (( ocount >= 1 )); then
    echo "  original already restored — cleaning up backup."
    rm -f "$BACKUP"
    return 0
  fi

  echo "  restoring original binary from backup..."
  cp -p "$BACKUP" "$BIN"
  rm -f "$BACKUP"
  echo "  restored. Spinner is back to boring dots."
}

status() {
  local ocount hcount
  ocount=$(count_hits "$ORIGINAL" "$BIN")
  hcount=$(count_hits "$HEART" "$BIN")
  if (( hcount >= 1 && ocount == 0 )); then
    echo "  status: HEART spinner is active <3"
  elif (( ocount >= 1 && hcount == 0 )); then
    echo "  status: original dot spinner (unpatched)"
  elif (( ocount >= 1 && hcount >= 1 )); then
    echo "  status: MIXED (some spinners patched, some not)"
  else
    echo "  status: unknown — neither pattern found in this build"
  fi
  if [[ -f "$BACKUP" ]]; then
    echo "  backup: $BACKUP"
  fi
}

case "${1:-patch}" in
  patch)   patch ;;
  restore) restore ;;
  status)  status ;;
  *) echo "usage: $0 {patch|restore|status}"; exit 1 ;;
esac
