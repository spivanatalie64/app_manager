#!/bin/bash
set -e

# --- CONFIGURATION ---
# Resolves the absolute path of the parent directory (app_manager root)
PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVO_DIR="$PARENT_DIR/servo_src/servo"

# Servo's "production" cargo profile builds into target/production/, and the
# desktop binary is named `servoshell` (not `servo`) in current Servo.
BUILD_PROFILE="production"
TARGET_BINARY="target/$BUILD_PROFILE/servoshell"

DIST_DIR="dist"
ARCHIVE_NAME="servo-minimal-desktop.tar.gz"
ARCHIVE_OUT="$PARENT_DIR/$ARCHIVE_NAME"
OS_TYPE="$(uname -s)"
# ---------------------

# --- PRECHECKS ---
[ -d "$SERVO_DIR" ] || { echo "[ERROR] $SERVO_DIR not found. Run scripts/servo_clone.sh first." >&2; exit 1; }
if command -v strip >/dev/null 2>&1; then
    STRIP_CMD="strip"
else
    echo "[WARN] strip not found; skipping symbol stripping."
    STRIP_CMD="true"
fi
# -----------------

# This script must run from the Servo source tree root.
cd "$SERVO_DIR"

echo "====================================================="
echo "  SERVO MINIMAL PRODUCTION PACKAGER SYSTEM          "
echo "====================================================="

# 1. Clean previous developer configurations
echo "[-] Purging developer footprints and compilation caches..."
./mach clean

# 2. Build with extreme optimization profile flags
# --profile=production enforces O3 speed and drops web-platform test tools
echo "[-] Compiling highly stripped web rendering engine..."
./mach build --profile=$BUILD_PROFILE

# 3. Handle binary stripping and artifact packaging based on host OS
mkdir -p "$DIST_DIR"

if [ "$OS_TYPE" = "Linux" ]; then
    if [ -f "$TARGET_BINARY" ]; then
        echo "[-] Stripping native Linux debug symbols..."
        "$STRIP_CMD" "$TARGET_BINARY"

        echo "[-] Bundling binary into distribution directory..."
        cp "$TARGET_BINARY" "$DIST_DIR/servoshell"

        echo "[-] Creating minimal compressed distribution archive..."
        tar -czf "$ARCHIVE_OUT" -C "$DIST_DIR" servoshell
        rm -rf "$DIST_DIR"
    else
        echo "[ERROR] Linux production binary not found at $TARGET_BINARY" >&2
        exit 1
    fi

elif [ "$OS_TYPE" = "Darwin" ]; then
    if [ -f "$TARGET_BINARY" ]; then
        echo "[-] Stripping native macOS binary symbols..."
        "$STRIP_CMD" "$TARGET_BINARY"

        echo "[-] Copying binary into distribution layout..."
        cp "$TARGET_BINARY" "$DIST_DIR/servoshell"

        echo "[-] Compressing final macOS package..."
        tar -czf "$ARCHIVE_OUT" -C "$DIST_DIR" servoshell
        rm -rf "$DIST_DIR"
    else
        echo "[ERROR] macOS production binary not found at $TARGET_BINARY" >&2
        exit 1
    fi
else
    echo "[ERROR] Unsupported deployment platform framework." >&2
    exit 1
fi

echo "====================================================="
echo "              DISTRIBUTION SUMMARY                   "
echo "====================================================="
echo "[SUCCESS] Process Complete!"
echo "Your end-user archive is located at: $ARCHIVE_OUT"
echo "-----------------------------------------------------"
echo "Archive File Details:"
ls -lh "$ARCHIVE_OUT"
echo "====================================================="
