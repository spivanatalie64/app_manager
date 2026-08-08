#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION ---
# Resolves the absolute path of the parent directory
PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKING_DIR="$PARENT_DIR/chromium_src"
DEPOT_TOOLS_DIR="$PARENT_DIR/depot_tools"
DEPOT_TOOLS_URL="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
# ---------------------

# --- PRECHECKS ---
command -v git >/dev/null 2>&1 || { echo "[ERROR] git is required but not installed." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 is required (depot_tools needs it)." >&2; exit 1; }
# -----------------

echo "============================================="
echo "Starting Chromium Source Checkout Automation"
echo "Target Folder: $WORKING_DIR"
echo "============================================="

# 1. Clone depot_tools if not already present in the parent directory
if [ ! -d "$DEPOT_TOOLS_DIR" ]; then
    echo "[-] Cloning depot_tools into $DEPOT_TOOLS_DIR..."
    git clone "$DEPOT_TOOLS_URL" "$DEPOT_TOOLS_DIR"
else
    echo "[+] depot_tools already exists. Skipping clone."
fi

# 2. Export path for the current script session
echo "[-] Updating PATH environment variable..."
export PATH="$PATH:$DEPOT_TOOLS_DIR"

# 3. Handle target working directory creation
if [ ! -d "$WORKING_DIR" ]; then
    echo "[-] Target directory not found. Creating: $WORKING_DIR"
    mkdir -p "$WORKING_DIR"
else
    echo "[+] Target directory already exists."
fi

# Move into the workspace
cd "$WORKING_DIR"

# 4. Fetch the Chromium source code
if [ ! -d "src" ]; then
    echo "[-] Fetching Chromium source (this will take a while)..."
    fetch --no-history chromium
else
    echo "[+] 'src' directory already exists. Skipping fetch."
fi

# 5. Sync dependencies and run hooks
# NOTE: gclient MUST run from the directory containing .gclient (the workspace
# root). It must never run from inside src/ — running it there makes gclient
# fail to find the .gclient file. fetch() already syncs on first checkout,
# this makes the idempotent/re-run path work.
echo "[-] Syncing dependencies..."
gclient sync

echo "============================================="
echo "[SUCCESS] Chromium codebase downloaded successfully!"
echo "Your source code is located in: $WORKING_DIR/src"
echo "============================================="
