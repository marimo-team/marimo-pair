#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" != 1 || "$1" == -h || "$1" == --help ]]; then
  printf 'Usage: %s <patch|minor|major|X.Y.Z>\n' "$0" >&2
  exit 2
fi
if [[ ! "$1" =~ ^(patch|minor|major|(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$ ]]; then
  printf 'Expected patch, minor, major, or a stable X.Y.Z version.\n' >&2
  exit 2
fi
exec gh workflow run release-pr.yml --repo marimo-team/marimo-pair --ref main -f "version=$1"
