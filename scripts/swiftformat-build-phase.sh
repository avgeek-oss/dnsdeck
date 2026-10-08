#!/bin/bash

set -o pipefail

if command -v swiftformat >/dev/null; then
    config="${SRCROOT}/.swiftformat"
    if ! swiftformat --config "${config}" --lint "${SRCROOT}/DNSDeck"; then
        echo "SwiftFormat failed. Run 'make format' in ${SRCROOT}."
        exit 1
    fi
else
    echo "SwiftFormat is not installed; skipping the build-phase check."
fi
