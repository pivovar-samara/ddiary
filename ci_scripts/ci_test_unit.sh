#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

if [ -n "${IOS_TEST_DESTINATION:-}" ]; then
  DESTINATION="${IOS_TEST_DESTINATION}"
else
  DESTINATION="$(
    "${PROJECT_ROOT}/ci_scripts/resolve_ios_destination.sh" \
      -project DDiary.xcodeproj \
      -scheme DDiaryTests
  )"
fi

echo "Running unit tests on destination: ${DESTINATION}"
xcodebuild test \
  -project DDiary.xcodeproj \
  -scheme DDiaryTests \
  -destination "${DESTINATION}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER=""
