#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

echo "Running unit tests on destination: ${DESTINATION}"
xcodebuild test -scheme DDiaryTests -destination "${DESTINATION}"
