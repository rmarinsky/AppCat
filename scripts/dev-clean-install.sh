#!/bin/bash

# Clean AppCat DEV build/install artifacts, then run the normal fast dev install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$PROJECT_DIR/build/dev-install"
INSTALL_PATH="/Applications/appcat-dev.app"
TARGET_PRODUCT_NAME="AppCat DEV"

echo "=== AppCat DEV clean install ==="

echo "Killing running $TARGET_PRODUCT_NAME process if any..."
if pkill -x "$TARGET_PRODUCT_NAME" 2>/dev/null; then
    sleep 1
fi

echo "Removing build artifacts at $BUILD_DIR ..."
rm -rf "$BUILD_DIR"

if [ -d "$INSTALL_PATH" ]; then
    echo "Removing existing install at $INSTALL_PATH ..."
    rm -rf "$INSTALL_PATH"
fi
echo ""
"$SCRIPT_DIR/dev-install.sh"
