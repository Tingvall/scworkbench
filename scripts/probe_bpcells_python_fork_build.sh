#!/usr/bin/env bash
set -euo pipefail

# Focused source-layout, wheel, and import probe for the pinned Python fork.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${1:-/tmp/scworkbench_bpcells_python_probe}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Match the fullstack native build environment. Callers may override these for
# a non-Debian toolchain, but a bare probe should work in the image.
export CPATH="${CPATH:-/usr/include/eigen3:/usr/include/hdf5/serial:/usr/include}"
export LIBRARY_PATH="${LIBRARY_PATH:-/usr/lib/x86_64-linux-gnu/hdf5/serial:/usr/lib/x86_64-linux-gnu}"
# BPCells registers setuptools parallel compilation. Keep the qualification
# probe bounded; high core-count builders otherwise spawn many C++ compilers.
export BPCELLS_NUM_BUILD_JOBS="${BPCELLS_NUM_BUILD_JOBS:-1}"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
"${PYTHON_BIN}" -m venv "${WORK_DIR}/venv"
PY="${WORK_DIR}/venv/bin/python"

"${PY}" -m pip install --upgrade pip setuptools wheel pybind11 setuptools-scm numpy pandas scipy
"${REPO_ROOT}/scripts/prepare_bpcells_python_fork.sh" "${WORK_DIR}/source" \
  "${BPCELLS_PYTHON_UPSTREAM_URL:-https://github.com/bnprks/BPCells.git}" \
  "${BPCELLS_PYTHON_UPSTREAM_REF:-28759cdd512578b6cbe549e226e1cd52a2d2308c}"

"${PY}" -m pip wheel --no-deps --wheel-dir "${WORK_DIR}/wheel" "${WORK_DIR}/source/python"
WHEEL="$(find "${WORK_DIR}/wheel" -maxdepth 1 -name 'bpcells-*.whl' -print -quit)"
test -n "${WHEEL}"

# Install into a separate clean environment so a source-tree import cannot mask
# a broken wheel.
"${PYTHON_BIN}" -m venv "${WORK_DIR}/clean-venv"
CLEAN_PY="${WORK_DIR}/clean-venv/bin/python"
"${CLEAN_PY}" -m pip install --upgrade pip
"${CLEAN_PY}" -m pip install numpy pandas scipy "${WHEEL}"
"${CLEAN_PY}" -c 'import bpcells.experimental; print(bpcells.experimental.__file__)'

echo "BPCells Python fork probe passed"
cat "${WORK_DIR}/source/scworkbench_bpcells_python_provenance.env"
