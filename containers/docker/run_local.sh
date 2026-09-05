#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:-scworkbench-fullstack:cpu}"
PROJECT_DIR="${2:-${HOME}/scworkbench-projects}"
CONTAINER_NAME="${SCWORKBENCH_CONTAINER_NAME:-scworkbench-local}"
PORT="${SCWORKBENCH_PORT:-3838}"

mkdir -p "${PROJECT_DIR}"

exec docker run --rm -it \
  --name "${CONTAINER_NAME}" \
  --publish "127.0.0.1:${PORT}:3838" \
  --volume "${PROJECT_DIR}:/work" \
  --env HOST=0.0.0.0 \
  --env PORT=3838 \
  "${IMAGE_REF}" \
  /usr/local/bin/run-scworkbench-shiny
