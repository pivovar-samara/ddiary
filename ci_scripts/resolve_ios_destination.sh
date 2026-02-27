#!/bin/bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <xcodebuild args for -showdestinations>" >&2
  exit 2
fi

showdestinations_output="$(xcodebuild -showdestinations "$@" 2>&1 || true)"
normalized_output="$(printf '%s\n' "${showdestinations_output}" | tr -d '\r')"
require_ios_simulator="${REQUIRE_IOS_SIMULATOR:-0}"

if printf '%s\n' "${normalized_output}" | grep -qi "Xcode doesn"; then
  echo "Xcode/runner mismatch detected while resolving destinations." >&2
  echo "The selected Xcode does not support the runner macOS version." >&2
  echo "Use a newer macOS runner label (for example, macos-26) or a compatible Xcode." >&2
  printf '%s\n' "${normalized_output}" >&2
  exit 1
fi

destination_line="$(
  printf '%s\n' "${normalized_output}" \
    | awk '/platform:iOS Simulator/ && /id:/ && /name:iPhone/ && $0 !~ /placeholder/ { print; exit }'
)"

if [ -z "${destination_line}" ]; then
  destination_line="$(
    printf '%s\n' "${normalized_output}" \
      | awk '/platform:iOS Simulator/ && /id:/ && $0 !~ /placeholder/ { print; exit }'
  )"
fi

if [ -z "${destination_line}" ]; then
  if [ "${require_ios_simulator}" = "1" ]; then
    echo "No concrete iOS Simulator destination found." >&2
    printf '%s\n' "${normalized_output}" >&2
    exit 1
  else
    destination_line="$(
      printf '%s\n' "${normalized_output}" \
        | awk '/platform:macOS/ && /id:/ && /Designed for \[iPad, ?iPhone\]/ { print; exit }'
    )"

    if [ -n "${destination_line}" ]; then
      echo "No concrete iOS Simulator destination found; falling back to macOS \"Designed for iPad/iPhone\" destination." >&2
    fi
  fi
fi

if [ -z "${destination_line}" ]; then
  echo "Unable to resolve a concrete destination (iOS Simulator or compatible macOS fallback)." >&2
  printf '%s\n' "${normalized_output}" >&2
  exit 1
fi

destination_id="$(printf '%s\n' "${destination_line}" | sed -E 's/.*id:([^,} ]+).*/\1/')"

if [ -z "${destination_id}" ] || [ "${destination_id}" = "${destination_line}" ]; then
  echo "Unable to parse destination id from:" >&2
  printf '%s\n' "${destination_line}" >&2
  exit 1
fi

printf 'id=%s\n' "${destination_id}"
