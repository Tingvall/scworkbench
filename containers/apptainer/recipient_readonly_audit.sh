#!/usr/bin/env bash
set -euo pipefail
image=${1:?usage: recipient_readonly_audit.sh IMAGE BUNDLE_DIR}
bundle=${2:?usage: recipient_readonly_audit.sh IMAGE BUNDLE_DIR}
singularity exec --cleanenv --bind "${bundle}:/audit_bundle:ro" "${image}" Rscript -e '
  library(scworkbench)
  b <- wb_open_bundle("/audit_bundle", read_only=TRUE, validate=TRUE)
  on.exit(wb_close_bundle(b), add=TRUE)
  stopifnot(isTRUE(wb_recipient_readiness("/audit_bundle")$ready))
  invisible(wb_manifest(b)); invisible(wb_matrices(b)); invisible(wb_spaces(b)); invisible(wb_art_list(b)); invisible(wb_list_trajectory_models(b))
  invisible(wb_prov_list_heads(b)); invisible(wb_prov_bundle_dag(b)); invisible(wb_kg_provenance_graph(b))
  for (a in wb_art_list(b)$artifact_id) invisible(wb_entity_certificate(b, "artifact", a))
  for (a in wb_art_list(b)$artifact_id) try(wb_art_load(b, a), silent=TRUE)
  source_runs <- unique(wb_prov_source_inputs(b)[c("snapshot_id", "run_id")])
  if (nrow(source_runs)) for (i in seq_len(nrow(source_runs))) {
    invisible(wb_prov_run_details(b, source_runs$run_id[[i]], source_runs$snapshot_id[[i]]))
  }
  stopifnot(inherits(try(wb_session_run_op(wb_session_new(), b, "hvg_select", inputs=list(matrix="RNA_counts", n_features=2L)), silent=TRUE), "try-error"))
'
