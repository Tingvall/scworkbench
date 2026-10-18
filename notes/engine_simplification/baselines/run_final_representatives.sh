#!/usr/bin/env bash
# Explicit invocation only. Does not detach itself or start background jobs.
# The coordinating supervisor invokes this once after focused tests pass.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo 'usage: bash run_final_representatives.sh FROZEN_CORE_LIBRARY NEW_RESULT_ROOT' >&2
  exit 64
fi
candidate_library=$(realpath -- "$1")
result_root=$2
script_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "$script_root/../../.." && pwd)
if [[ ! -f "$candidate_library/scworkbench/DESCRIPTION" || -e "$result_root" ]]; then
  echo 'Require installed candidate core and a fresh result root.' >&2
  exit 73
fi
mkdir -p -- "$result_root/logs" "$result_root/time" "$result_root/temporary"
result_root=$(realpath -- "$result_root")
export TMPDIR="$result_root/temporary"
cd -- "$repository_root"
git rev-parse HEAD > "$result_root/source_commit.txt"
git status --short > "$result_root/source_status.txt"
sha256sum "$candidate_library/scworkbench/DESCRIPTION" \
  "$candidate_library/scworkbench/R/scworkbench.rdb" \
  "$candidate_library/scworkbench/R/scworkbench.rdx" > "$result_root/installed_core.sha256"
sha256sum "$script_root/table_identity.R" "$script_root/representative.R" \
  "$script_root/mixed_publication.R" "$script_root/profile_synthetic_import.R" \
  "$script_root/../profile_descriptor.R" "$script_root/../profile_canonical.R" \
  "$script_root/../profile_owned_block.R" \
  tests/fixtures/engine_descriptor_repaired_oracle.R \
  tests/fixtures/engine_canonical_repaired_oracle.R \
  > "$result_root/measurement_scripts.sha256"
for measurement in table_identity representative mixed_publication profile_synthetic_import; do
  # The gate helper atomically publishes its numeric exit sidecar. A timeout is
  # a failed measurement, never a pass; stop before subsequent measurements.
  inst/ci/run_logged_gate "$result_root/logs/$measurement.log" \
    "$result_root/logs/$measurement.exit" -- \
    /usr/bin/time -v -o "$result_root/time/$measurement.txt" \
    timeout --signal=TERM --kill-after=30s 900s \
    Rscript "$script_root/$measurement.R" "$candidate_library" \
      "$result_root/$measurement"
done
for probe in descriptor canonical_baseline canonical_candidate owned; do
  case "$probe" in
    descriptor) command=(Rscript "$script_root/../profile_descriptor.R"
      "$candidate_library" "$result_root/descriptor") ;;
    canonical_baseline) command=(Rscript "$script_root/../profile_canonical.R"
      "$candidate_library" "$result_root/canonical_baseline" baseline) ;;
    canonical_candidate) command=(Rscript "$script_root/../profile_canonical.R"
      "$candidate_library" "$result_root/canonical_candidate" candidate) ;;
    owned) command=(Rscript "$script_root/../profile_owned_block.R" "$candidate_library") ;;
  esac
  inst/ci/run_logged_gate "$result_root/logs/$probe.log" \
    "$result_root/logs/$probe.exit" -- \
    /usr/bin/time -v -o "$result_root/time/$probe.txt" \
    timeout --signal=TERM --kill-after=30s 900s "${command[@]}"
done
inst/ci/run_logged_gate "$result_root/logs/identity_comparison.log" \
  "$result_root/logs/identity_comparison.exit" -- Rscript -e '
args <- commandArgs(TRUE)
table <- read.csv(file.path(args[1], "table_identity", "table_identity.csv"))
before <- read.csv(args[2])
stopifnot(identical(table[c("case", "n", "sha256")], before[c("case", "n", "sha256")]))
old <- read.csv(file.path(args[1], "canonical_baseline", "measurements.csv"))
new <- read.csv(file.path(args[1], "canonical_candidate", "measurements.csv"))
stopifnot(identical(old[c("case", "bytes", "sha256")], new[c("case", "bytes", "sha256")]))
cat("TABLE_AND_CANONICAL_FROZEN_IDENTITIES_EXACT_OK\n")
' "$result_root" "$script_root/evidence/table_before.csv"
sha256sum -c "$result_root/installed_core.sha256"
sha256sum -c "$result_root/measurement_scripts.sha256"
# Preserve these results as raw timings. Root interprets the predeclared budgets
# and digest equality; no source-wide qualification is claimed by this script.
printf 'REPRESENTATIVE_AND_COMPONENT_MEASUREMENTS_COMPLETE\n'
