#!/bin/bash
# Build the XCTest bundle, then run without AppCatApp, UI tests, or desktop input.
set -euo pipefail
cd "$(dirname "$0")/.."
picker_developer_dir=$(xcode-select -p)
picker_test_dir="$PWD/build/headless-tests"
picker_products="$PWD/build/dev-install-test-validation"
picker_frameworks="$picker_developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
picker_swiftlibs="$picker_developer_dir/Platforms/MacOSX.platform/Developer/usr/lib"
mkdir -p "$picker_test_dir"
xcodebuild build-for-testing -project AppCat.xcodeproj -scheme 'AppCat DEV' \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/dev-install/DerivedData \
    CONFIGURATION_BUILD_DIR="$picker_products" > "$picker_test_dir/build.log" 2>&1 || {
    tail -n 80 "$picker_test_dir/build.log"
    exit 1
}
# Preserve the built application's bundle metadata for manifest/identity tests, but execute
# only the XCTest runner. No application delegate, menu bar scene, or event loop is started.
picker_runner_app="$picker_test_dir/Headless.app"
mkdir -p "$picker_runner_app/Contents/MacOS"
cp "$picker_products/AppCat DEV.app/Contents/Info.plist" "$picker_runner_app/Contents/Info.plist"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -F "$picker_frameworks" -I "$picker_swiftlibs" -L "$picker_swiftlibs" \
    -Xlinker -rpath -Xlinker "$picker_frameworks" \
    -Xlinker -rpath -Xlinker "$picker_swiftlibs" \
    -Xlinker -rpath -Xlinker "$picker_developer_dir/../SharedFrameworks" \
    scripts/AppCatHeadlessTestMain.swift -o "$picker_runner_app/Contents/MacOS/AppCat DEV"
DYLD_LIBRARY_PATH="$picker_products/AppCat DEV.app/Contents/MacOS" \
DYLD_FRAMEWORK_PATH="$picker_products/AppCat DEV.app/Contents/Frameworks" \
    "$picker_runner_app/Contents/MacOS/AppCat DEV" "$picker_products/AppCat DEV.app/Contents/PlugIns/AppCatTests.xctest"
