#!/bin/bash
# Standalone Foundation/XCTest checks: no NSApplication host, windows, or input events.
set -euo pipefail
cd "$(dirname "$0")/.."
picker_developer_dir=$(xcode-select -p)
picker_frameworks="$picker_developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
picker_swiftlibs="$picker_developer_dir/Platforms/MacOSX.platform/Developer/usr/lib"
mkdir -p build/picker-diagnostics-tests
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -D DEBUG -D DEV_BUILD -F "$picker_frameworks" -I "$picker_swiftlibs" \
    -L "$picker_swiftlibs" -Xlinker -rpath -Xlinker "$picker_frameworks" \
    -Xlinker -rpath -Xlinker "$picker_swiftlibs" \
    -Xlinker -rpath -Xlinker "$picker_developer_dir/../SharedFrameworks" \
    AppCat/Features/Picker/PickerDiagnosticJournal.swift AppCatTests/PickerDiagnosticsTests.swift \
    AppCat/Features/Picker/PickerMouseSelection.swift AppCatTests/PickerMouseSelectionTests.swift \
    scripts/PickerDiagnosticsTestMain.swift -o build/picker-diagnostics-tests/tests
build/picker-diagnostics-tests/tests
