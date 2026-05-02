#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env.json}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example.json to $ENV_FILE and fill in values." >&2
  exit 1
fi

exec flutter run --dart-define-from-file="$ENV_FILE" "$@"
