#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:-scworkbench-fullstack:cpu}"
PROJECT_DIR="${2:-${HOME}/scworkbench-projects}"
CONTAINER_NAME="${SCWORKBENCH_CONTAINER_NAME:-scworkbench-local}"

mkdir -p "${PROJECT_DIR}"

exec docker run --rm -it \
  --name "${CONTAINER_NAME}" \
  --volume "${PROJECT_DIR}:/work" \
  --workdir /work \
  "${IMAGE_REF}"
