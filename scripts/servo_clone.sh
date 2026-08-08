#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION ---
# Resolves the absolute path of the parent directory
PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKING_DIR="$PARENT_DIR/servo_src"
SERVO_REPO="https://github.com/servo/servo.git"
# ---------------------

# --- PRECHECKS ---
command -v git >/dev/null 2>&1 || { echo "[ERROR] git is required but not installed." >&2; exit 1; }
# -----------------

echo "============================================="
echo "Starting Servo Engine Source Code Clone"
echo "Target Folder: $WORKING_DIR"
echo "============================================="

# 1. Handle target working directory creation if missing
if [ ! -d "$WORKING_DIR" ]; then
    echo "[-] Target directory not found. Creating: $WORKING_DIR"
    mkdir -p "$WORKING_DIR"
else
    echo "[+] Target directory already exists."
fi

# Move into the target workspace
cd "$WORKING_DIR"

# 2. Clone the official Servo Git repository
if [ ! -d "servo" ]; then
    echo "[-] Cloning Servo master repository from GitHub..."
    git clone "$SERVO_REPO"
    cd servo
else
    echo "[+] Servo repository directory already exists. Skipping clone."
    cd servo
    echo "[-] Pulling latest upstream modifications..."
    # Robust across branch renames: point origin/HEAD at the remote default,
    # then fast-forward from the tracking branch.
    git remote set-head origin -a >/dev/null 2>&1 || true
    git pull --ff-only
fi

echo "============================================="
echo "[SUCCESS] Source code cloned to: $WORKING_DIR/servo"
echo "============================================="
echo "[-] Initializing build environment dependencies..."
echo "============================================="

# 3. Initialize Servo's custom orchestration package manager (mach)
# This bootstraps Python, Cargo, and Rust targets implicitly
./mach bootstrap

echo "============================================="
echo "[COMPLETE] Ready for local modifications!"
echo "============================================="
echo "To compile and launch the friendly desktop shell, run:"
echo "cd $WORKING_DIR/servo && ./mach build && ./target/debug/servoshell"
echo "============================================="
