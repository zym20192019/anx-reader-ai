#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "macos" ]]; then
  printf 'usage: %s macos\n' "$0"
  exit 1
fi

flutter build macos --release
app_path="$(find build/macos/Build/Products/Release -maxdepth 1 -type d -name '*.app' -print -quit)"
test -n "$app_path"
printf 'Built unsigned/local-signing handoff: %s\n' "$app_path"
