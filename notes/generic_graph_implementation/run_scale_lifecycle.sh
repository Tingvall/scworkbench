#!/usr/bin/env bash
set -euo pipefail
test "$#" -eq 4
fixture_record=$1
owned_output=$2
node_count=$3
scale_mode=$4
# Processes are sequential, not a still-live parent plus an inspecting child.
# Each complete process receives an independent maximum-RSS/time record.
/usr/bin/time -v Rscript --vanilla notes/generic_graph_implementation/scale_worker.R \
  "$fixture_record" "$owned_output" "$node_count" "$scale_mode"
if test "$scale_mode" != fault; then
  /usr/bin/time -v Rscript --vanilla notes/generic_graph_implementation/scale_worker.R \
    "$fixture_record" "$owned_output" "$node_count" inspect
fi
