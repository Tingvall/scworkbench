#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEF_FILE="${SCRIPT_DIR}/scworkbench_fullstack.def"
PYBENCH_ROOT="${REPO_ROOT}/../../pybench"

SANDBOX_PATH="${1:-/tmp/scworkbench_fullstack_sandbox}"
SIF_PATH="${2:-/tmp/scworkbench_fullstack_full.sif}"
BUILD_CONTEXT="${3:-${SANDBOX_PATH}.context}"

if [[ ! -d "${REPO_ROOT}/../scworkbenchShiny" ]]; then
  echo "Expected sibling repo at ${REPO_ROOT}/../scworkbenchShiny" >&2
  exit 1
fi

if [[ ! -d "${PYBENCH_ROOT}" ]]; then
  echo "Expected sibling repo at ${PYBENCH_ROOT}" >&2
  exit 1
fi

EXPECTED_PYBENCH_COMMIT="$(sed -n 's/^PyBenchCommit:[[:space:]]*//p' "${REPO_ROOT}/inst/release/composite_release.dcf")"
OBSERVED_PYBENCH_COMMIT="$(git -C "${PYBENCH_ROOT}" rev-parse HEAD)"
if [[ "${OBSERVED_PYBENCH_COMMIT}" != "${EXPECTED_PYBENCH_COMMIT}" ]]; then
  echo "PyBench checkout does not match composite release metadata: expected ${EXPECTED_PYBENCH_COMMIT}, observed ${OBSERVED_PYBENCH_COMMIT}" >&2
  exit 1
fi

echo "Repo root: ${REPO_ROOT}"
echo "Definition: ${DEF_FILE}"
echo "Sandbox: ${SANDBOX_PATH}"
echo "SIF: ${SIF_PATH}"
echo "Build context: ${BUILD_CONTEXT}"

mkdir -p "$(dirname "${SANDBOX_PATH}")" "$(dirname "${SIF_PATH}")" "$(dirname "${BUILD_CONTEXT}")"
rm -rf "${SANDBOX_PATH}"
rm -f "${SIF_PATH}"
rm -rf "${BUILD_CONTEXT}"

# %files cannot exclude payloads after it starts copying. Build from a compact
# sibling context so local reports, old SIFs, and IDE state never inflate a
# release image build or exhaust temporary storage.
mkdir -p "${BUILD_CONTEXT}/scworkbench" "${BUILD_CONTEXT}/scworkbenchShiny" "${BUILD_CONTEXT}/pybench"
rsync -a \
  --exclude '.git/' \
  --exclude '.Rproj.user/' \
  --exclude '.agents/' \
  --exclude '.codex/' \
  --exclude 'reports/' \
  --exclude 'scworkbench.Rcheck/' \
  --exclude 'containers/*.sif' \
  --exclude '*.tar.gz' \
  "${REPO_ROOT}/" "${BUILD_CONTEXT}/scworkbench/"
rsync -a --exclude '.git/' --exclude '.Rproj.user/' --exclude '.agents/' --exclude '.codex/' \
  "${REPO_ROOT}/../scworkbenchShiny/" "${BUILD_CONTEXT}/scworkbenchShiny/"
for required in pyproject.toml README.md CITATION.cff LICENSE CHANGELOG.md; do
  if [[ ! -f "${PYBENCH_ROOT}/${required}" ]]; then
    echo "Missing required pybench packaging input: ${PYBENCH_ROOT}/${required}" >&2
    exit 1
  fi
done
if [[ ! -d "${PYBENCH_ROOT}/src/pybench" ]]; then
  echo "Missing required pybench package source: ${PYBENCH_ROOT}/src/pybench" >&2
  exit 1
fi

rsync -a --exclude '.git/' --exclude '.venv/' --exclude '.deps/' --exclude '__pycache__/' \
  "${PYBENCH_ROOT}/pyproject.toml" "${PYBENCH_ROOT}/README.md" \
  "${PYBENCH_ROOT}/CITATION.cff" "${PYBENCH_ROOT}/LICENSE" \
  "${PYBENCH_ROOT}/CHANGELOG.md" "${BUILD_CONTEXT}/pybench/"
rsync -a --exclude '__pycache__/' "${PYBENCH_ROOT}/src/" "${BUILD_CONTEXT}/pybench/src/"

for required in pyproject.toml README.md CITATION.cff LICENSE CHANGELOG.md src/pybench; do
  if [[ ! -e "${BUILD_CONTEXT}/pybench/${required}" ]]; then
    echo "Compact context missing required pybench packaging input: ${required}" >&2
    exit 1
  fi
done

cd "${BUILD_CONTEXT}/scworkbench"

echo "==> Building sandbox"
singularity build --fakeroot --sandbox "${SANDBOX_PATH}" "${DEF_FILE}"

chmod +x "${SANDBOX_PATH}/usr/local/bin/run-scworkbench-shiny"

echo "==> Packing SIF"
singularity build --fakeroot "${SIF_PATH}" "${SANDBOX_PATH}"

echo "==> Smoke check"
singularity exec "${SIF_PATH}" bash -lc \
  'R --version | head -n 1 && /opt/pyenv/bin/python --version && /opt/pyenv/bin/python -c "import pybench, scvi, torch; print(\"pybench\", getattr(pybench, \"__file__\", \"loaded\")); print(\"scvi\", scvi.__version__); print(\"torch\", torch.__version__, \"cuda\", torch.version.cuda)" && test -x /usr/local/bin/run-scworkbench-shiny && echo launcher-ok'

echo "Build complete: ${SIF_PATH}"

if [[ "${KEEP_BUILD_CONTEXT:-0}" != "1" ]]; then
  rm -rf "${BUILD_CONTEXT}"
fi
