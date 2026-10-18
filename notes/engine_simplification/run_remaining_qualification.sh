#!/usr/bin/env bash
# Explicit coordinator invocation after the combined candidate is frozen.
# Retain the one original whole-suite run and every focused correction separately.
set -Eeuo pipefail
[[ $# == 3 ]] || exit 64
pin=$1
library=$(realpath "$2")
evidence=$3
core=$(git rev-parse --show-toplevel)
peer=/home/dirk/Projects/.pybench-worktrees/engine-simplification-quill-20261018
task_root=/tmp/scwb-engine-simplification-forge-20261018
original=$task_root/final-qualification-fff5051
cd "$core"
[[ $(git rev-parse HEAD) == "$pin" && -z $(git status --porcelain) ]]
[[ -f "$original/logs/01_canonical.exit" && $(<"$original/logs/01_canonical.exit") == 1 ]]
[[ $(git -C "$peer" rev-parse HEAD) == 0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e ]]
[[ -z $(git -C "$peer" status --porcelain) && ! -e "$evidence" ]]
git diff --exit-code fff50517c9838481ff2a49bb1ebd8f5f20ead8dd HEAD -- inst/protocol inst/release DESCRIPTION NAMESPACE
mkdir -p "$evidence/logs" "$evidence/time" "$evidence/temporary"
export TMPDIR="$evidence/temporary" R_LIBS="$library" SCWORKBENCH_SOURCE_ROOT="$core"
unset SCWB_CONTRACT_INSTALLED_LIBRARY SCWORKBENCH_TEST_INSTALLED
export SCWORKBENCH_TEST_PYBENCH_COMMIT=0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e
export SCWORKBENCH_SCWBRNA_ROOT=/home/dirk/Projects/operation_packs/scwbRNA
export SCWORKBENCH_PYBENCH_PYTHON=/tmp/quill-engine-simplification-venv/bin/python
export PYBENCH_PYTHON="$SCWORKBENCH_PYBENCH_PYTHON"
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
df -B1 "$evidence" > "$evidence/capacity_before.txt"
sha256sum -c "$original/installed_core.sha256"
sha256sum "$library/scworkbench/R/scworkbench.rdb" \
  "$library/scworkbench/R/scworkbench.rdx" "$library/scworkbench/libs/scworkbench.so" \
  > "$evidence/installed_core.sha256"
gate 00_protocol python3 notes/engine_simplification/final_protocol.py "$core" "$peer"
gate 00b_generator Rscript scripts/generate_phase5_derived_fitted_axis_protocol.R
git diff --exit-code -- inst/protocol
gate 00c_environment Rscript --vanilla -e '
  .libPaths(c(commandArgs(TRUE),.libPaths()))
  library(scworkbench)
  print(sessionInfo()); print(Sys.info()); print(.libPaths())
  print(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"),unset="<unset>"))
  for(p in c("BPCells","Matrix","rhdf5","irlba","uwot","rnndescent"))
    cat(p,as.character(packageVersion(p)),normalizePath(find.package(p)),"\n")
  if(file.exists("/proc/self/status"))cat(grep("Cpus_allowed_list:",readLines("/proc/self/status"),value=TRUE),"\n")
' "$library" /tmp/scwb-matrix-streaming-forge-20261018/verified-library
gate 01_fixture_setup Rscript inst/golden_bundle/create_golden_bundle.R "$evidence/golden.bundle"
gate 01c_installed_affected Rscript notes/engine_simplification/run_final_affected.R \
  "$library" "$evidence/golden.bundle"
# Quill must repin this external actual-installed driver before invocation.
gate 02_live_mixed Rscript /tmp/quill-mixed-broker-probe/run_after_core_freeze.R
gate 03_current_python_lifecycle env SCWORKBENCH_PHASE3B_PYBENCH_ROOT="$peer" \
  SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST="$site/scwbpyv3reference/operation-pack.json" \
  Rscript -e 'library(scworkbench);source("inst/tests/contract_test_runner.R");source("tests/test_operation_pack_v3_python_composite_contract.R");stopifnot(test_operation_pack_v3_python_composite_lifecycle_contract());cat("CURRENT_PAIR_V3_LIFECYCLE_PASS\n")'
gate 03b_current_python_model env SCWORKBENCH_PHASE3B_PYBENCH_ROOT="$peer" \
  SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST="$site/scwbpyv3reference/operation-pack.json" \
  Rscript -e 'library(scworkbench);source("inst/tests/contract_test_runner.R");source("tests/test_operation_pack_v3_python_composite_contract.R");stopifnot(test_operation_pack_v3_python_phase5_model_lifecycle_contract());cat("CURRENT_PAIR_V3_MODEL_LIFECYCLE_PASS\n")'
gate 04_generated_docs Rscript --vanilla inst/dev/regenerate_public_docs.R --check
gate 05_documentation_package Rscript inst/tests/check_documentation_contracts.R
gate 06_diff git diff --check
[[ -f "$task_root/python_final.exit" && $(<"$task_root/python_final.exit") == 0 ]]
gate 07_representatives bash notes/engine_simplification/baselines/run_final_representatives.sh \
  "$library" "$evidence/representatives"
export TMPDIR="$evidence/temporary"
for kind in base csc; do
  for mode in paired baseline candidate; do
    gate "07_writer_${kind}_${mode}" env SCWB_MM_PROFILE_CLASS="$kind" \
      SCWB_MM_PROFILE_MODE="$mode" SCWB_MM_SOURCE_REPO="$core" \
      Rscript "$task_root/profile_matrix_market_final.R" "$library" \
      "$evidence/writer-${kind}-${mode}"
  done
done
gate 07a_pager Rscript notes/engine_simplification/profile_graph_pager.R "$library" "$evidence/pager"
gate 07a_publication_before Rscript notes/engine_simplification/profile_publication_resources.R \
  "$task_root/library_frozen" "$evidence/publication-before" baseline
gate 07a_publication_after Rscript notes/engine_simplification/profile_publication_resources.R \
  "$library" "$evidence/publication-after" candidate
gate 07a_publication_exact Rscript -e \
  'a<-commandArgs(TRUE);stopifnot(identical(readRDS(a[1]),readRDS(a[2])));cat("SNAPSHOT_IDENTITY_EXACT\n")' \
  "$evidence/publication-before/snapshot.rds" "$evidence/publication-after/snapshot.rds"
for kind in realistic wide; do
  gate "07a_space_${kind}_engine" env SCWB_SPACE_SOURCE_ROOT="$core" \
    SCWB_SPACE_BENCH_CASE="$kind" SCWB_SPACE_BENCH_MODE=engine \
    Rscript "$task_root/profile_typed_space_final.R" "$library" "$evidence/space-${kind}-engine"
  gate "07a_space_${kind}_oracle" env SCWB_SPACE_SOURCE_ROOT="$core" \
    SCWB_SPACE_BENCH_CASE="$kind" SCWB_SPACE_BENCH_MODE=oracle \
    SCWB_SPACE_BENCH_BUNDLE="$evidence/space-${kind}-engine/bundle" \
    Rscript "$task_root/profile_typed_space_final.R" "$library" "$evidence/space-${kind}-oracle"
done
for kind in graph remaining_families; do
  case "$kind" in graph) script=representative_graph_storage.R;; remaining_families) script=representative_remaining_families.R;; esac
  gate "07a_${kind}_before" Rscript "$task_root/$script" \
    /tmp/scwb-matrix-streaming-forge-20261018/verified-library "$evidence/${kind}-before"
  gate "07a_${kind}_after" Rscript "$task_root/$script" "$library" "$evidence/${kind}-after"
done
gate 07b_efficient_direct Rscript "$task_root/direct_xenopus_efficient.R" \
  /tmp/scwb-matrix-streaming-forge-20261018/verified-library \
  "$evidence/direct-xenopus-efficient" "$task_root/direct-xenopus-v3"
gate 07c_transport_matched_direct Rscript "$task_root/direct_xenopus_transport_matched.R" \
  /tmp/scwb-matrix-streaming-forge-20261018/verified-library \
  "$evidence/direct-xenopus-transport-matched" "$task_root/direct-xenopus-v3"
sha256sum "$evidence/direct-xenopus-transport-matched/scientific_reference.rds" \
  > "$evidence/matched_reference_before_engine.sha256"
export SCWB_DIRECT_REFERENCE_SHA256
SCWB_DIRECT_REFERENCE_SHA256=$(cut -d' ' -f1 "$evidence/matched_reference_before_engine.sha256")
gate 08_xenopus bash -c '
  set -u
  Rscript notes/engine_simplification/full_engine_xenopus.R "$1" "$2" "$3" "$4" "$6" &
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
' bash "$library" "$evidence/xenopus" "$evidence/direct-xenopus-transport-matched" \
  /tmp/scwb-matrix-streaming-forge-20261018/verified-library "$evidence/xenopus_resources.csv" \
  "$task_root/direct-xenopus-v3"
gate 08b_raw_alignment Rscript "$task_root/final_raw_alignment.R" "$library" \
  "$evidence/xenopus/xenopus.bundle" "$evidence/raw_alignment"
gate 09_install_unchanged sha256sum -c "$evidence/installed_core.sha256"
gate 10_final_diff git diff --check
df -B1 "$evidence" > "$evidence/capacity_after.txt"
state 'COMPLETE — original whole-suite and focused descendant evidence remain separate'
