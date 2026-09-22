#!/bin/bash
set -euo pipefail

# Upload Crashlytics dSYMs from an Xcode Cloud archive.
#
# The in-build "Upload Crashlytics dSYMs" phase is not enough here: Crashlytics/run ends with
#   eval $COMMAND_PATH$UPLOAD_ARGUMENTS > /dev/null 2>&1 &
# so the upload is backgrounded with its output discarded, and Xcode Cloud tears the container
# down as soon as the action finishes — killing it mid-flight with nothing in the logs.
# This runs the uploader synchronously instead. Duplicate uploads are harmless: Crashlytics
# deduplicates by dSYM UUID.

if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
  echo "No CI_ARCHIVE_PATH (not an archive action); skipping Crashlytics dSYM upload."
  exit 0
fi

UPLOAD_SYMBOLS="${CI_DERIVED_DATA_PATH}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
GSP="${CI_PRIMARY_REPOSITORY_PATH}/DDiary/Resources/GoogleService-Info.plist"

if [ ! -x "${UPLOAD_SYMBOLS}" ]; then
  echo "warning: upload-symbols not found at ${UPLOAD_SYMBOLS}; skipping."
  exit 0
fi

if [ ! -f "${GSP}" ]; then
  echo "warning: GoogleService-Info.plist not found at ${GSP}; skipping."
  exit 0
fi

"${UPLOAD_SYMBOLS}" -gsp "${GSP}" -p ios "${CI_ARCHIVE_PATH}/dSYMs"
