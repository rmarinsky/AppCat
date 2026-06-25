#!/bin/bash

# Reset AppCat DEV privacy grants used during local permission testing.

set -euo pipefail

BUNDLE_ID="ua.com.rmarinsky.appcat.dev"

reset_service() {
    local service="$1"
    local output

    if output="$(tccutil reset "$service" "$BUNDLE_ID" 2>&1)"; then
        echo "Reset $service for $BUNDLE_ID."
    else
        echo "Warning: failed to reset $service for $BUNDLE_ID." >&2
        echo "$output" >&2
    fi
}

echo "=== AppCat DEV TCC reset ==="
reset_service Accessibility
reset_service ListenEvent
echo "TCC reset done."
