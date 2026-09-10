#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: check_container_source_hygiene.sh SOURCE_ROOT [...]" >&2
  exit 2
fi

for source_root in "$@"; do
  if [[ ! -d "${source_root}" ]]; then
    echo "Container source root is not a directory: ${source_root}" >&2
    exit 1
  fi

  git_entry="$(find -P "${source_root}" -name .git -print -quit)"
  if [[ -n "${git_entry}" ]]; then
    echo "Container source tree contains prohibited Git metadata: ${git_entry}" >&2
    exit 1
  fi
done

echo "Container source hygiene: OK"
