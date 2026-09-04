#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHINY_ROOT="${REPO_ROOT}/../scworkbenchShiny"
PYBENCH_ROOT="${REPO_ROOT}/../../pybench"
CONTEXT="${1:-/tmp/scworkbench_fullstack_docker_context}"

test -d "${SHINY_ROOT}"
test -d "${PYBENCH_ROOT}"

EXPECTED_PYBENCH_COMMIT="$(sed -n 's/^PyBenchCommit:[[:space:]]*//p' "${REPO_ROOT}/inst/release/composite_release.dcf")"
OBSERVED_PYBENCH_COMMIT="$(git -C "${PYBENCH_ROOT}" rev-parse HEAD)"
if [[ "${OBSERVED_PYBENCH_COMMIT}" != "${EXPECTED_PYBENCH_COMMIT}" ]]; then
  echo "PyBench checkout mismatch: expected ${EXPECTED_PYBENCH_COMMIT}, observed ${OBSERVED_PYBENCH_COMMIT}" >&2
  exit 1
fi

rm -rf "${CONTEXT}"
mkdir -p "${CONTEXT}/scworkbench" "${CONTEXT}/scworkbenchShiny" "${CONTEXT}/pybench"

rsync -a \
  --exclude '.git/' \
  --exclude '.Rproj.user/' \
  --exclude '.agents/' \
  --exclude '.codex/' \
  --exclude 'reports/' \
  --exclude 'scworkbench.Rcheck/' \
  --exclude '*.sif' \
  --exclude '*.tar.gz' \
  "${REPO_ROOT}/" "${CONTEXT}/scworkbench/"

rsync -a \
  --exclude '.git/' \
  --exclude '.Rproj.user/' \
  --exclude '.agents/' \
  --exclude '.codex/' \
  "${SHINY_ROOT}/" "${CONTEXT}/scworkbenchShiny/"

for required in pyproject.toml README.md CITATION.cff LICENSE CHANGELOG.md; do
  test -f "${PYBENCH_ROOT}/${required}"
  cp "${PYBENCH_ROOT}/${required}" "${CONTEXT}/pybench/"
done
rsync -a --exclude '__pycache__/' "${PYBENCH_ROOT}/src/" "${CONTEXT}/pybench/src/"
rsync -a --exclude '__pycache__/' "${PYBENCH_ROOT}/protocol/" "${CONTEXT}/pybench/protocol/"

python3 "${SCRIPT_DIR}/derive_cpu_lock.py" \
  "${REPO_ROOT}/containers/apptainer/fullstack_python_requirements.lock" \
  "${CONTEXT}/scworkbench/containers/docker/fullstack_python_requirements.cpu.lock"

python3 "${SCRIPT_DIR}/render_install_script.py" \
  "${REPO_ROOT}/containers/apptainer/scworkbench_fullstack.def" \
  "${CONTEXT}/install_fullstack.sh"

cp "${SCRIPT_DIR}/Dockerfile" "${CONTEXT}/Dockerfile"
echo "Docker build context ready: ${CONTEXT}"
