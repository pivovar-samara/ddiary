#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,OS=26.0.1,name=iPhone 16e}"

echo "Running unit tests on destination: ${DESTINATION}"
xcodebuild test \
  -project DDiary.xcodeproj \
  -scheme DDiaryTests \
  -destination "${DESTINATION}" \
  -destination-timeout 180 \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1
