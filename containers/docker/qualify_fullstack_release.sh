#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?usage: qualify_fullstack_release.sh IMAGE_REF [PLATFORM]}"
PLATFORM="${2:-}"
RUN=(docker run --rm)
if [[ -n "${PLATFORM}" ]]; then
  RUN+=(--platform "${PLATFORM}")
fi
RUN+=(--entrypoint /bin/bash "${IMAGE_REF}" -lc)

echo "==> Image identity"
docker image inspect "${IMAGE_REF}" --format '{{json .RepoDigests}} {{.Id}}'

echo "==> Runtime and CPU profile"
"${RUN[@]}" '
  cat /opt/scworkbench_runtime_provenance.txt
  /opt/pyenv/bin/python -c "import importlib.metadata as m, scvi, torch; runtime=dict(line.rstrip().split(\"=\", 1) for line in open(\"/opt/scworkbench_runtime_provenance.txt\", encoding=\"utf-8\")); assert runtime[\"runtime_kind\"] == \"docker\"; assert torch.version.cuda is None; assert not any(d.metadata.get(\"Name\", \"\").lower().startswith(\"nvidia-\") for d in m.distributions()); print(\"pybench\", m.version(\"pybench\")); print(\"scvi\", scvi.__version__); print(\"torch\", torch.__version__, \"cuda\", torch.version.cuda)"
  Rscript -e "library(scworkbench); cat(\"scworkbench=\", as.character(packageVersion(\"scworkbench\")), \"\\n\", sep=\"\")"
'

echo "==> Locked runtimes"
"${RUN[@]}" '
  Rscript /opt/scworkbench/inst/ci/validate_fullstack_r_dependencies.R \
    --lock /opt/scworkbench/containers/apptainer/fullstack_r_dependencies.dcf \
    --description /opt/scworkbench/DESCRIPTION
  /opt/pyenv/bin/python /opt/scworkbench/inst/ci/validate_fullstack_python_lock.py \
    --requirements /opt/scworkbench/containers/docker/fullstack_python_requirements.cpu.lock \
    --pybench /opt/pybench/pyproject.toml
'

echo "==> Product and release gates"
"${RUN[@]}" '
  test -x /usr/local/bin/run-scworkbench-shiny
  test -f /opt/scworkbench/inst/onboarding/AGENT_OPERATOR_GUIDE.md
  cd /opt/scworkbench
  inst/ci/check_release_package.sh
'

echo "Docker full-stack qualification: OK"
