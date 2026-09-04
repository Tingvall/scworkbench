#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="${SCWORKBENCH_DOCKER_CONTEXT:-/tmp/scworkbench_fullstack_docker_context}"
IMAGE_REF="scworkbench-fullstack:cpu-dev"
PLATFORMS="linux/amd64,linux/arm64"
MODE=""
BUILD_NCPUS="${SCWORKBENCH_DOCKER_BUILD_NCPUS:-2}"

usage() {
  echo "usage: $0 [--tag IMAGE] [--platform PLATFORM[,PLATFORM]] [--jobs N] (--load|--push)" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) IMAGE_REF="${2:?missing image tag}"; shift 2 ;;
    --platform) PLATFORMS="${2:?missing platform}"; shift 2 ;;
    --jobs) BUILD_NCPUS="${2:?missing job count}"; shift 2 ;;
    --load|--push) MODE="$1"; shift ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -z "${MODE}" ]]; then
  usage
  exit 2
fi
if [[ ! "${BUILD_NCPUS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--jobs must be a positive integer" >&2
  exit 2
fi
if [[ "${MODE}" == "--load" && "${PLATFORMS}" == *,* ]]; then
  echo "--load accepts one platform; use --push for a multi-platform image" >&2
  exit 2
fi

"${SCRIPT_DIR}/prepare_build_context.sh" "${CONTEXT}"

docker buildx build \
  --file "${CONTEXT}/Dockerfile" \
  --platform "${PLATFORMS}" \
  --tag "${IMAGE_REF}" \
  --build-arg "BUILD_NCPUS=${BUILD_NCPUS}" \
  --label "org.opencontainers.image.revision=$(git -C "${SCRIPT_DIR}/../.." rev-parse HEAD)" \
  "${MODE}" \
  "${CONTEXT}"

echo "Docker build complete: ${IMAGE_REF} (${PLATFORMS})"
