#!/usr/bin/env bash
set -euo pipefail

test_workflow=".github/workflows/tests.yml"
release_workflow=".github/workflows/release.yml"

grep -Fq 'SWIFTPM_PACKAGES_PATH: ${{ github.workspace }}/.ci/SourcePackages' "$test_workflow"
grep -Fq "actions/cache@v4" "$test_workflow"
grep -Fq "AppCat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" "$test_workflow"
test -f AppCat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
grep -Fq -- "-clonedSourcePackagesDirPath \"\$SWIFTPM_PACKAGES_PATH\"" "$test_workflow"
grep -Fq "xcodebuild build-for-testing" "$test_workflow"
grep -Fq "xcodebuild test-without-building" "$test_workflow"

grep -Fq 'SWIFTPM_PACKAGES_PATH: ${{ github.workspace }}/.ci/SourcePackages' "$release_workflow"
grep -Fq "actions/cache@v4" "$release_workflow"
grep -Fq -- "-clonedSourcePackagesDirPath \"\$SWIFTPM_PACKAGES_PATH\"" "$release_workflow"

if grep -A8 "actions/cache@v4" "$test_workflow" | grep -Eq "DerivedData|xcarchive|certificate"; then
  echo "CI cache must contain only resolved Swift package sources" >&2
  exit 1
fi
