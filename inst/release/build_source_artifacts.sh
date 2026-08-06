#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
PYBENCH_ROOT="${2:?usage: build_source_artifacts.sh SCWORKBENCH_ROOT PYBENCH_ROOT OUTPUT_DIR [PYTHON]}"
OUTPUT_DIR="${3:?usage: build_source_artifacts.sh SCWORKBENCH_ROOT PYBENCH_ROOT OUTPUT_DIR [PYTHON]}"
PYTHON="${4:-python3}"

REPO_ROOT="$(cd "${REPO_ROOT}" && pwd)"
PYBENCH_ROOT="$(cd "${PYBENCH_ROOT}" && pwd)"
mkdir -p "${OUTPUT_DIR}/r" "${OUTPUT_DIR}/python"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

Rscript "${REPO_ROOT}/inst/ci/validate_release_metadata.R" "${REPO_ROOT}" "${PYBENCH_ROOT}"

BUILD_DIR="$(mktemp -d -t scworkbench-release-build-XXXXXX)"
trap 'rm -rf "${BUILD_DIR}"' EXIT
(
  cd "${BUILD_DIR}"
  R CMD build "${REPO_ROOT}" --no-build-vignettes
)
R_TARBALL="$(find "${BUILD_DIR}" -maxdepth 1 -name 'scworkbench_*.tar.gz' -print -quit)"
test -n "${R_TARBALL}"
cp "${R_TARBALL}" "${OUTPUT_DIR}/r/"

"${PYTHON}" -m build --no-isolation --outdir "${OUTPUT_DIR}/python" "${PYBENCH_ROOT}"
test "$(find "${OUTPUT_DIR}/python" -maxdepth 1 -name 'pybench-*.whl' | wc -l)" -eq 1
test "$(find "${OUTPUT_DIR}/python" -maxdepth 1 -name 'pybench-*.tar.gz' | wc -l)" -eq 1

echo "source release artifacts: OK"
