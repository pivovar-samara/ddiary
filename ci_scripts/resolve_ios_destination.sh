#!/bin/bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <xcodebuild args for -showdestinations>" >&2
  exit 2
fi

showdestinations_output="$(xcodebuild -showdestinations "$@" 2>&1 || true)"

destination_line="$(
  printf '%s\n' "${showdestinations_output}" \
    | tr -d '\r' \
    | awk '/platform:iOS Simulator/ && /id:/ && $0 !~ /placeholder/ { print; exit }'
)"

if [ -z "${destination_line}" ]; then
  echo "Unable to resolve a concrete iOS Simulator destination." >&2
  printf '%s\n' "${showdestinations_output}" >&2
  exit 1
fi

destination_id="$(printf '%s\n' "${destination_line}" | sed -E 's/.*id:([^,} ]+).*/\1/')"

if [ -z "${destination_id}" ] || [ "${destination_id}" = "${destination_line}" ]; then
  echo "Unable to parse simulator destination id from:" >&2
  printf '%s\n' "${destination_line}" >&2
  exit 1
fi

printf 'id=%s\n' "${destination_id}"
