#!/bin/bash

# Build and install AppCat DEV to /Applications for fast permission/feature testing.
# Default behavior:
# - kills the running DEV app only
# - builds Debug incrementally with DEV bundle id
# - installs app as /Applications/appcat-dev.app
#
# Usage:
#   ./scripts/dev-install.sh
#   ./scripts/dev-install.sh --build-only
#   ./scripts/dev-install.sh --install-name appcat-dev-local
#   ./scripts/dev-install.sh --help
#
# Related:
#   ./scripts/dev-clean-install.sh
#   ./scripts/dev-reset-tcc.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT_NAME="AppCat"
PROJECT_FILE="${PROJECT_NAME}.xcodeproj"
SCHEME="AppCat DEV"
CONFIG="Debug"

APP_DISPLAY_NAME="AppCat DEV"
TARGET_PRODUCT_NAME="AppCat DEV"
INSTALL_APP_NAME="appcat-dev"
BUNDLE_ID="ua.com.rmarinsky.appcat.dev"

BUILD_DIR="$PROJECT_DIR/build/dev-install"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
CONFIG_BUILD_DIR="$BUILD_DIR/$CONFIG"
APP_PATH="$CONFIG_BUILD_DIR/${TARGET_PRODUCT_NAME}.app"
INSTALL_PATH="/Applications/${INSTALL_APP_NAME}.app"
DESTINATION="platform=macOS,arch=$(uname -m)"
LOG_PATH="$BUILD_DIR/xcodebuild.log"

BUILD_ONLY=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --build-only   Build only, skip install to /Applications.
  --install-name Override installed app folder name (default: appcat-dev).
  --help         Show this help.

Related commands:
  ./scripts/dev-clean-install.sh   Clean build artifacts, then run dev install.
  ./scripts/dev-reset-tcc.sh       Reset DEV Accessibility/Input Monitoring grants.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --install-name)
            if [[ $# -lt 2 ]]; then
                echo "--install-name requires a value"
                exit 1
            fi
            if [[ -z "${2//[[:space:]]/}" ]]; then
                echo "--install-name requires a non-empty value"
                exit 1
            fi
            if [[ "$2" == */* || "$2" == *..* ]]; then
                echo "--install-name must be a simple name (no path separators or traversal patterns)"
                exit 1
            fi
            INSTALL_APP_NAME="$2"
            INSTALL_PATH="/Applications/${INSTALL_APP_NAME}.app"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo "=== AppCat DEV build/install ==="
echo "Project:      $PROJECT_FILE"
echo "Scheme:       $SCHEME"
echo "Configuration:$CONFIG"
echo "Build product:$TARGET_PRODUCT_NAME.app"
echo "Display name: $APP_DISPLAY_NAME"
echo "Install name: $INSTALL_APP_NAME.app"
echo "Bundle id:    $BUNDLE_ID"
echo ""

if [ "$BUILD_ONLY" = false ]; then
    echo "Killing running $TARGET_PRODUCT_NAME process if any..."
fi
if [ "$BUILD_ONLY" = false ] && pkill -x "$TARGET_PRODUCT_NAME" 2>/dev/null; then
    sleep 1
fi

if [ "$BUILD_ONLY" = false ] && [ -d "$INSTALL_PATH" ]; then
    echo "Removing existing install at $INSTALL_PATH ..."
    rm -rf "$INSTALL_PATH"
fi

PBXPROJ_PATH="$PROJECT_DIR/$PROJECT_FILE/project.pbxproj"
PROJECT_SPEC="$PROJECT_DIR/project.yml"

if [ -f "$PROJECT_SPEC" ] && { [ ! -f "$PBXPROJ_PATH" ] || [ "$PROJECT_SPEC" -nt "$PBXPROJ_PATH" ]; }; then
    echo "Regenerating Xcode project from project.yml..."
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "xcodegen is required (brew install xcodegen)."
        exit 1
    fi
    xcodegen generate --quiet --spec "$PROJECT_SPEC"
elif [ ! -f "$PBXPROJ_PATH" ]; then
    echo "Xcode project not found: $PROJECT_DIR/$PROJECT_FILE"
    exit 1
fi

mkdir -p "$BUILD_DIR"

echo ""
echo "Building $APP_DISPLAY_NAME ..."
set +e
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CONFIGURATION_BUILD_DIR="$CONFIG_BUILD_DIR" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    build \
    2>&1 | tee "$LOG_PATH" \
    | grep -E "^(Build|Compile|Compiling|Ld|Linking|error:|warning:|\\*\\*)"
XCODEBUILD_STATUS=${PIPESTATUS[0]}
set -e
if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
    echo "xcodebuild failed (exit $XCODEBUILD_STATUS). See full log: $LOG_PATH"
    exit "$XCODEBUILD_STATUS"
fi

if [ ! -d "$APP_PATH" ]; then
    echo ""
    echo "Build failed. App not found at: $APP_PATH"
    echo "See full log: $LOG_PATH"
    exit 1
fi

echo ""
echo "Build successful: $APP_PATH"

if [ "$BUILD_ONLY" = true ]; then
    echo "Build-only mode enabled. Skipping install."
    exit 0
fi

echo "Installing to $INSTALL_PATH ..."
cp -R "$APP_PATH" "$INSTALL_PATH"

# Clear quarantine attributes to avoid Gatekeeper noise on local testing.
xattr -cr "$INSTALL_PATH"

echo ""
echo "=== Done ==="
echo "Installed: $INSTALL_PATH"
echo ""
echo "If permissions got stuck, run:"
echo "  ./scripts/dev-reset-tcc.sh"

echo "Launching $INSTALL_APP_NAME ..."
open "$INSTALL_PATH"
