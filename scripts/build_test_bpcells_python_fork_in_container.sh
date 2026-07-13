#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SIF_PATH="${1:-${REPO_ROOT}/containers/scworkbench_fullstack_full.sif}"
BUNDLE_PATH="${2:-${REPO_ROOT}/../demo}"
MATRIX_ID="${3:-ATAC_counts}"
WORK_DIR="${4:-/tmp/BPCells_python_fork_build}"

PREP_SCRIPT="${REPO_ROOT}/scripts/prepare_bpcells_python_fork.sh"
CHECK_SCRIPT="${REPO_ROOT}/scripts/check_bpcells_python_matrix_read.py"

if [[ ! -f "${SIF_PATH}" ]]; then
  echo "Missing SIF: ${SIF_PATH}" >&2
  exit 1
fi

if [[ ! -d "${BUNDLE_PATH}" ]]; then
  echo "Missing bundle dir: ${BUNDLE_PATH}" >&2
  exit 1
fi

if [[ ! -x "${PREP_SCRIPT}" ]]; then
  echo "Prepare script is not executable: ${PREP_SCRIPT}" >&2
  echo "Run: chmod +x ${PREP_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${CHECK_SCRIPT}" ]]; then
  echo "Missing check script: ${CHECK_SCRIPT}" >&2
  exit 1
fi

echo "SIF: ${SIF_PATH}"
echo "Bundle: ${BUNDLE_PATH}"
echo "Matrix: ${MATRIX_ID}"
echo "Work dir: ${WORK_DIR}"
echo
echo "This requires a container rebuilt from the updated definition with:"
echo "  - libhwy-dev"
echo "  - pybind11"
echo "  - setuptools-scm"
echo

singularity exec \
  --bind /home/dirk/Projects:/home/dirk/Projects \
  "${SIF_PATH}" \
  bash -lc "
    set -euo pipefail
    export PYTHONPATH=
    export PYTHONHOME=
    export PYTHONUSERBASE=
    export R_LIBS=
    export R_LIBS_USER=
    export R_LIBS_SITE=
    export CPATH=/usr/include/eigen3:/usr/include/hdf5/serial:/usr/include
    export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/hdf5/serial:/usr/lib/x86_64-linux-gnu

    rm -rf '${WORK_DIR}'
    '${PREP_SCRIPT}' '${WORK_DIR}'

    PYTHON_BIN=python3 '${REPO_ROOT}/scripts/probe_bpcells_python_fork_build.sh' '${WORK_DIR}'

    '${WORK_DIR}/clean-venv/bin/python' '${CHECK_SCRIPT}' --bundle '${BUNDLE_PATH}' --matrix-id '${MATRIX_ID}'
  "
