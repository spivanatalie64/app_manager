#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION ---
PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKING_DIR="$PARENT_DIR/servo_src"
SERVO_DIR="$WORKING_DIR/servo"
SERVO_REPO="https://github.com/servo/servo.git"
USERSCRIPTS_DIR="$WORKING_DIR/userscripts"
PLUGIN_FILE="$USERSCRIPTS_DIR/custom_plugin.js"
PATCHES_DIR="$PARENT_DIR/scripts/patches"
RUST_PATCH="$PATCHES_DIR/001-servo-runtime-trace.patch"
TARGET_RUST_FILE="components/script/script_runtime.rs"
# ---------------------

# --- PRECHECKS ---
command -v git >/dev/null 2>&1 || { echo "[ERROR] git is required but not installed." >&2; exit 1; }
# -----------------

echo "============================================="
echo "  SERVO ALL-IN-ONE AUTOMATION SYSTEM         "
echo "============================================="

# 1. SETUP TARGET FOLDER & CLONE SOURCE ENGINE
if [ ! -d "$WORKING_DIR" ]; then
    echo "[-] Creating target workspace: $WORKING_DIR"
    mkdir -p "$WORKING_DIR"
fi
cd "$WORKING_DIR"

if [ ! -d "servo" ]; then
    echo "[-] Cloning Servo master repository from GitHub..."
    git clone "$SERVO_REPO"
fi
cd servo

# 2. GENERATE THE RUNTIME JAVASCRIPT USERSCRIPT
# servoshell loads userscripts from a DIRECTORY via --userscripts (plural).
# The old `--user-script <file>` flag no longer exists in Servo.
echo "[-] Creating userscript directory: $USERSCRIPTS_DIR"
mkdir -p "$USERSCRIPTS_DIR"
cat << 'EOF' > "$PLUGIN_FILE"
// custom_plugin.js - injected via servoshell --userscripts
(function () {
  function apply() {
    console.log("=========================================");
    console.log("[PLUGIN SUCCESS] Custom Plugin Loaded!");
    console.log("=========================================");
    if (document.body) {
      document.body.style.border = "10px solid #5f3dc4";
      document.body.style.backgroundColor = "#f3f0ff";
    }
  }
  // The document may not have a <body> yet when the userscript runs.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply);
  } else {
    apply();
  }
})();
EOF
echo "[+] User script written to: $PLUGIN_FILE"

# 3. APPLY THE RUST ENGINE PATCH (real patch file, applied honestly)
# Anchored on Runtime::new_with_parent (the current init entry point).
# If the tree has drifted, this FAILS LOUDLY instead of claiming success.
if [ -f "$RUST_PATCH" ]; then
    if ! grep -q "ENGINE ROOT HACKED" "$TARGET_RUST_FILE"; then
        echo "[-] Applying engine patch: $RUST_PATCH"
        if git apply --check "$RUST_PATCH" 2>/dev/null; then
            git apply "$RUST_PATCH"
            echo "[+] Engine patch applied successfully!"
        else
            echo "[ERROR] $RUST_PATCH does not apply to the current tree." >&2
            echo "        The upstream tree has drifted. Resolve the conflict" >&2
            echo "        manually, then rerun this script. Nothing was changed." >&2
            exit 1
        fi
    else
        echo "[+] Engine already patched previously."
    fi
else
    echo "[WARN] No patch file at $RUST_PATCH; skipping engine modification." >&2
fi

echo "============================================="
echo "              AUTOMATION SUMMARY             "
echo "============================================="
echo "1. Code Base Location:  $SERVO_DIR"
echo "2. User Scripts Dir:    $USERSCRIPTS_DIR"
echo "3. Engine Modification: $SERVO_DIR/$TARGET_RUST_FILE"
echo "---------------------------------------------"
echo "TO RUN:"
echo "  cd $SERVO_DIR && ./mach bootstrap && ./mach build"
echo "  ./target/debug/servoshell --userscripts $USERSCRIPTS_DIR https://example.com"
echo "============================================="
