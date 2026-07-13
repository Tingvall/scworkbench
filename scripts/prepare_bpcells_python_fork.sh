#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_PATH="${REPO_ROOT}/third_party/patches/bpcells-python-noninteger-read.patch"

TARGET_DIR="${1:-/tmp/BPCells_python_fork}"
UPSTREAM_URL="${2:-${BPCELLS_PYTHON_UPSTREAM_URL:-https://github.com/bnprks/BPCells.git}}"
UPSTREAM_REF="${3:-${BPCELLS_PYTHON_UPSTREAM_REF:-28759cdd512578b6cbe549e226e1cd52a2d2308c}}"

if [[ ! -f "${PATCH_PATH}" ]]; then
  echo "Missing patch file: ${PATCH_PATH}" >&2
  exit 1
fi

if [[ -e "${TARGET_DIR}" ]]; then
  echo "Target already exists: ${TARGET_DIR}" >&2
  exit 1
fi

if [[ ! "${UPSTREAM_REF}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "BPCells upstream ref must be a full 40-character commit SHA: ${UPSTREAM_REF}" >&2
  exit 1
fi

git clone --no-checkout "${UPSTREAM_URL}" "${TARGET_DIR}"
git -C "${TARGET_DIR}" checkout --detach "${UPSTREAM_REF}"
CHECKED_OUT_REF="$(git -C "${TARGET_DIR}" rev-parse HEAD)"
if [[ "${CHECKED_OUT_REF}" != "${UPSTREAM_REF}" ]]; then
  echo "BPCells checkout mismatch: expected ${UPSTREAM_REF}, got ${CHECKED_OUT_REF}" >&2
  exit 1
fi

PYTHON_DIR="${TARGET_DIR}/python"
REQUIRED_PATHS=(
  "${PYTHON_DIR}"
  "${PYTHON_DIR}/src/matrix.cpp"
  "${PYTHON_DIR}/src/bpcells/experimental/matrix.py"
)
for required_path in "${REQUIRED_PATHS[@]}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "BPCells source layout mismatch at ${CHECKED_OUT_REF}: missing ${required_path}" >&2
    exit 1
  fi
done
if [[ ! -f "${PYTHON_DIR}/pyproject.toml" && ! -f "${PYTHON_DIR}/setup.py" ]]; then
  echo "BPCells source layout mismatch at ${CHECKED_OUT_REF}: python packaging metadata missing" >&2
  exit 1
fi

PATCH_SHA256="$(sha256sum "${PATCH_PATH}" | awk '{print $1}')"
if ! git -C "${TARGET_DIR}" apply --check "${PATCH_PATH}"; then
  echo "BPCells patch context mismatch: ${PATCH_PATH} does not apply to upstream ${CHECKED_OUT_REF}" >&2
  exit 1
fi
git -C "${TARGET_DIR}" apply "${PATCH_PATH}"
python3 - <<'PY' "${TARGET_DIR}/python/src/matrix.cpp"
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '#include "bpcells-cpp/matrixIterators/ImportMatrixHDF5.h"'
new = '#include "bpcells-cpp/matrixIterators/ImportMatrixAnnDataHDF5.h"'
if old not in text:
    raise SystemExit(f"expected include not found in {path}")
text = text.replace(old, new, 1)

old_ctor = """    auto mat_float = std::make_unique<StoredMatrix<float>>(openAnnDataMatrix<float>(
        h5ad_path,
        group,
        16384L, // Just provide a default buffer size matching what R uses
        std::move(row_names),
        std::move(col_names)
    ));
"""
new_ctor = """    auto mat_float = openAnnDataMatrix<float>(
        h5ad_path,
        group,
        16384L, // Just provide a default buffer size matching what R uses
        std::move(row_names),
        std::move(col_names)
    );
"""
if old_ctor not in text:
    raise SystemExit(f"expected AnnData loader block not found in {path}")
text = text.replace(old_ctor, new_ctor, 1)
path.write_text(text)
PY

python3 - <<'PY' "${TARGET_DIR}/python/src/bpcells/experimental/matrix.py"
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

marker = """def _dtype_suffix(dtype):
    if dtype == np.uint32:
        return "uint32"
    if dtype == np.float32:
        return "float"
    if dtype == np.float64:
        return "double"
    raise RuntimeError(f"Unsupported BPCells dtype: {dtype}")
"""
helper = marker + """


_READ_BATCH_COLS = 100


def _load_subset_batched(fn, source, row, col, threads):
    if len(col) <= _READ_BATCH_COLS:
        return scipy.sparse.hstack(fn(source, row, col, threads))

    parts = []
    for start in range(0, len(col), _READ_BATCH_COLS):
        part_cols = col[start : start + _READ_BATCH_COLS]
        parts.extend(fn(source, row, part_cols, threads))
    return scipy.sparse.hstack(parts)
"""
if "_READ_BATCH_COLS = 100" not in text:
    if marker not in text:
        raise SystemExit(f"expected dtype helper block not found in {path}")
    text = text.replace(marker, helper, 1)

old_dir = """        fn = getattr(bpcells.cpp, f"load_matrix_dir_subset_{_dtype_suffix(self.dtype)}")
        res = scipy.sparse.hstack(fn(self.dir, row, col, self.threads))
"""
new_dir = """        fn = getattr(bpcells.cpp, f"load_matrix_dir_subset_{_dtype_suffix(self.dtype)}")
        res = _load_subset_batched(fn, self.dir, row, col, self.threads)
"""
if old_dir not in text:
    raise SystemExit(f"expected DirMatrix loader block not found in {path}")
text = text.replace(old_dir, new_dir, 1)

old_mem = """        fn = getattr(bpcells.cpp, f"load_matrix_memory_subset_{_dtype_suffix(self.dtype)}")
        res = scipy.sparse.hstack(fn(self._data, row, col, self.threads))
"""
new_mem = """        fn = getattr(bpcells.cpp, f"load_matrix_memory_subset_{_dtype_suffix(self.dtype)}")
        res = _load_subset_batched(fn, self._data, row, col, self.threads)
"""
if old_mem not in text:
    raise SystemExit(f"expected MemMatrix loader block not found in {path}")
text = text.replace(old_mem, new_mem, 1)

path.write_text(text)
PY

cat >"${TARGET_DIR}/scworkbench_bpcells_python_provenance.env" <<EOF
BPCELLS_PYTHON_UPSTREAM_URL=${UPSTREAM_URL}
BPCELLS_PYTHON_UPSTREAM_REF=${CHECKED_OUT_REF}
BPCELLS_PYTHON_PATCH_SHA256=${PATCH_SHA256}
EOF

cat <<EOF
Prepared fork at:
  ${TARGET_DIR}

Pinned upstream commit:
  ${CHECKED_OUT_REF}

Patch identity:
  ${PATCH_SHA256}  ${PATCH_PATH}

Suggested next steps:
  1. python -m pip wheel --no-deps --wheel-dir /tmp/bpcells-wheel ${PYTHON_DIR}
  2. python -m pip install /tmp/bpcells-wheel/bpcells-*.whl
  3. python -c 'import bpcells.experimental'
EOF
