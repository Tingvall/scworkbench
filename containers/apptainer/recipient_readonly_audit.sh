#!/usr/bin/env bash
set -euo pipefail
image=${1:?usage: recipient_readonly_audit.sh IMAGE BUNDLE_DIR}
bundle=${2:?usage: recipient_readonly_audit.sh IMAGE BUNDLE_DIR}
singularity exec --cleanenv --bind "${bundle}:/audit_bundle:ro" "${image}" Rscript -e '
  library(scworkbench)
  b <- wb_open_bundle("/audit_bundle", read_only=TRUE, validate=TRUE)
  on.exit(wb_close_bundle(b), add=TRUE)
  stopifnot(isTRUE(wb_recipient_readiness("/audit_bundle")$ready))
  wb_manifest(b); wb_matrices(b); wb_spaces(b); wb_art_list(b); wb_list_trajectory_models(b)
  wb_prov_list_heads(b); wb_prov_bundle_dag(b); wb_kg_provenance_graph(b)
  for (a in wb_art_list(b)$artifact_id) wb_art_birth_certificate(b, a)
  for (a in wb_art_list(b)$artifact_id) try(wb_art_load(b, a), silent=TRUE)
  for (r in unique(wb_prov_source_inputs(b)$run_id)) wb_prov_run_details(b, r)
  stopifnot(inherits(try(wb_session_run_op(wb_session_new(), b, "hvg_select", inputs=list(matrix="RNA_counts", n_features=2L)), silent=TRUE), "try-error"))
'
