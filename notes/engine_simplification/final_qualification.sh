#!/usr/bin/env bash
# Explicitly launched detached by Forge after the pair is frozen.
set -euo pipefail
[[ $# == 3 ]] || exit 64
pin=$1
library=$(realpath "$2")
evidence=$3
core=$(pwd)
peer=/home/dirk/Projects/.pybench-worktrees/engine-simplification-quill-20261018
task_root=/tmp/scwb-engine-simplification-forge-20261018
[[ $(git rev-parse HEAD) == "$pin" && -z $(git status --porcelain) ]]
[[ $(git -C "$peer" rev-parse HEAD) == 0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e ]]
[[ -z $(git -C "$peer" status --porcelain) && ! -e "$evidence" ]]
mkdir -p "$evidence/logs" "$evidence/time" "$evidence/temporary"
evidence=$(realpath "$evidence")
export TMPDIR="$evidence/temporary" R_LIBS="$library"
export SCWORKBENCH_SOURCE_ROOT="$core" SCWB_CONTRACT_INSTALLED_LIBRARY="$library"
export SCWORKBENCH_SCWBRNA_ROOT=/home/dirk/Projects/operation_packs/scwbRNA
export SCWORKBENCH_PYBENCH_PYTHON=/tmp/quill-engine-simplification-venv/bin/python
site=/tmp/quill-engine-simplification-venv/lib/python3.11/site-packages
export SCWORKBENCH_PYTHON_PACK_MANIFEST="$site/scwbpython/operation-pack.json"
export SCWORKBENCH_GRAPH_PYTHON="$SCWORKBENCH_PYBENCH_PYTHON"
export SCWORKBENCH_GRAPH_PYTHON_MANIFEST="$site/scwbgraphfixture/operation-pack.json"
unset SCWORKBENCH_PHASE3B_PYBENCH_ROOT SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST
export SCWB_FROZEN_CORE_COMMIT="$pin"
state() { printf '%s\n' "$1" > "$evidence/status.next"; mv "$evidence/status.next" "$evidence/status"; }
trap 'state "FAILED line=$LINENO"' ERR
gate() {
  local name=$1; shift
  state "RUNNING $name"
  inst/ci/run_logged_gate "$evidence/logs/$name.log" "$evidence/logs/$name.exit" -- \
    /usr/bin/time -v -o "$evidence/time/$name.txt" "$@"
}
git rev-parse HEAD > "$evidence/core_commit.txt"
git -C "$peer" rev-parse HEAD > "$evidence/python_commit.txt"
sha256sum "$library/scworkbench/R/scworkbench.rdb" \
  "$library/scworkbench/R/scworkbench.rdx" "$library/scworkbench/libs/scworkbench.so" \
  > "$evidence/installed_core.sha256"
gate environment bash -c 'uname -a; lscpu; free -b; findmnt -T "$1"; df -B1 "$1"; rg "Cpus_allowed_list|Mems_allowed_list" /proc/self/status' bash "$evidence"
gate 00_protocol python3 notes/engine_simplification/final_protocol.py "$core" "$peer"
gate 01_canonical Rscript inst/tests/run_contract_tests.R
gate 02_live_mixed Rscript /tmp/quill-mixed-broker-probe/run_after_core_freeze.R
gate 03_current_python_lifecycle env SCWORKBENCH_PHASE3B_PYBENCH_ROOT="$peer" \
  SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST="$site/scwbpyv3reference/operation-pack.json" \
  Rscript -e 'devtools::load_all(".",quiet=TRUE);source("tests/test_operation_pack_v3_python_composite_contract.R");stopifnot(test_operation_pack_v3_python_composite_lifecycle_contract());cat("CURRENT_PAIR_V3_LIFECYCLE_PASS\n")'
gate 04_generated_docs Rscript --vanilla inst/dev/regenerate_public_docs.R --check
gate 05_documentation_package Rscript inst/tests/check_documentation_contracts.R
gate 06_diff git diff --check
state "WAITING Quill final Python sidecar (no overlapping performance jobs)"
while [[ ! -f "$task_root/python_final.exit" ]]; do sleep 5; done
[[ $(<"$task_root/python_final.exit") == 0 ]]
gate 07_representatives bash notes/engine_simplification/baselines/run_final_representatives.sh \
  "$library" "$evidence/representatives"
export TMPDIR="$evidence/temporary"
# Time includes the sampler's <=5-second final wait. It reports lower-bound
# sampled disk peaks; GNU time is authoritative for the R child's peak RSS.
gate 08_xenopus bash -c '
  set -u
  Rscript notes/engine_simplification/full_engine_xenopus.R "$1" "$2" "$3" "$4" &
  workflow_pid=$!
  while [[ ! -d "$2" ]] && kill -0 "$workflow_pid" 2>/dev/null; do sleep 0.1; done
  sampler_pid=
  if [[ -d "$2" ]] && kill -0 "$workflow_pid" 2>/dev/null; then
    python3 notes/engine_simplification/sample_workflow_resources.py \
      "$workflow_pid" "$2" "$5" "$TMPDIR" &
    sampler_pid=$!
  fi
  wait "$workflow_pid"; result=$?
  if [[ -n "$sampler_pid" ]]; then wait "$sampler_pid" || exit 74; fi
  exit "$result"
' bash "$library" "$evidence/xenopus" "$task_root/direct-xenopus-v3" \
  /tmp/scwb-matrix-streaming-forge-20261018/verified-library "$evidence/xenopus_resources.csv"
gate 09_install_unchanged sha256sum -c "$evidence/installed_core.sha256"
gate 10_final_diff git diff --check
state "COMPLETE — numeric results and budget interpretation require retained-log review"
