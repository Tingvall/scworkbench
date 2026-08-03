#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GOLDEN_BUNDLE="${SCWB_GOLDEN_BUNDLE:-"$ROOT/fixtures/golden_bundle/scwb_golden"}"

echo "[fullstack] root: $ROOT"

echo "[fullstack] generating golden bundle"
Rscript "$ROOT/scworkbench/inst/golden_bundle/create_golden_bundle.R" "$GOLDEN_BUNDLE"

echo "[fullstack] scworkbench KG JSONL export"
KG_EXPORT_DIR="$(mktemp -d /tmp/scwb_kg_export.XXXXXX)"
echo "[fullstack] kg_export_dir: $KG_EXPORT_DIR"
SCWB_KG_EXPORT_DIR="$KG_EXPORT_DIR" Rscript -e "
if (!requireNamespace('devtools', quietly = TRUE) && !requireNamespace('pkgload', quietly = TRUE)) stop('devtools or pkgload required')
if (!requireNamespace('jsonlite', quietly = TRUE)) stop('jsonlite required')
if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('$ROOT/scworkbench', quiet = TRUE) else pkgload::load_all('$ROOT/scworkbench', quiet = TRUE)
b <- wb_open_bundle('$GOLDEN_BUNDLE')
on.exit(wb_close_bundle(b), add = TRUE)
out_dir <- Sys.getenv('SCWB_KG_EXPORT_DIR')
manifest <- wb_kg_export_jsonl(bundle = b, out_dir = out_dir)
stopifnot(identical(as.character(manifest\$schema_version), 'scworkbench.kg.v1'))
stopifnot(file.exists(file.path(out_dir, 'kg_nodes.jsonl')))
stopifnot(file.exists(file.path(out_dir, 'kg_edges.jsonl')))
stopifnot(file.exists(file.path(out_dir, 'kg_manifest.json')))
manifest_disk <- jsonlite::read_json(file.path(out_dir, 'kg_manifest.json'))
stopifnot(identical(as.character(manifest_disk\$schema_version), 'scworkbench.kg.v1'))
stopifnot(isTRUE(manifest_disk\$node_count > 0))
stopifnot(isTRUE(manifest_disk\$edge_count > 0))
nodes_head <- readLines(file.path(out_dir, 'kg_nodes.jsonl'), n = 1L, warn = FALSE)
edges_head <- readLines(file.path(out_dir, 'kg_edges.jsonl'), n = 1L, warn = FALSE)
stopifnot(length(nodes_head) == 1L, length(edges_head) == 1L)
stopifnot(isTRUE(jsonlite::validate(nodes_head)))
stopifnot(isTRUE(jsonlite::validate(edges_head)))
cat('scworkbench KG JSONL export ok\n')
"

echo "[fullstack] scwb-agent KG JSONL tool smokes"
(
  cd "$ROOT/scwb-agent"
  if [ -d ".venv" ]; then
    SCWB_AGENT_PY=(.venv/bin/python)
  elif [ -d ".deps" ]; then
    SCWB_AGENT_PY=(env PYTHONPATH=.deps:. python3)
  else
    SCWB_AGENT_PY=(python3)
  fi
  "${SCWB_AGENT_PY[@]}" -m harness.cli tool-smoke kg_status "{\"kg_dir\":\"$KG_EXPORT_DIR\"}"
  "${SCWB_AGENT_PY[@]}" -m harness.cli tool-smoke kg_expand "{\"kg_dir\":\"$KG_EXPORT_DIR\",\"node_id\":\"recipe:trajectory_geneset_dynamics_discovery\",\"direction\":\"out\",\"edge_types\":[\"USES\",\"PRODUCES\"],\"max_depth\":1}"
  "${SCWB_AGENT_PY[@]}" -m harness.cli tool-smoke kg_explain_path "{\"kg_dir\":\"$KG_EXPORT_DIR\",\"from_node\":\"recipe:trajectory_geneset_dynamics_discovery\",\"to_node\":\"primitive:obs_table\",\"edge_types\":[\"USES\",\"PRODUCES\",\"REQUIRES\"],\"max_depth\":3}"
)

echo "[fullstack] scworkbench engine smoke"
Rscript -e "
if (!requireNamespace('devtools', quietly = TRUE) && !requireNamespace('pkgload', quietly = TRUE)) stop('devtools or pkgload required')
if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('$ROOT/scworkbench', quiet = TRUE) else pkgload::load_all('$ROOT/scworkbench', quiet = TRUE)
b <- wb_open_bundle('$GOLDEN_BUNDLE')
on.exit(wb_close_bundle(b), add = TRUE)
stopifnot(inherits(b, 'scworkbench_bundle'))
stopifnot(nrow(wb_matrices(b)) >= 1)
stopifnot(nrow(wb_spaces(b)) >= 1)
stopifnot(length(wb_cells(b, 'core')) == 600)
stopifnot(nrow(wb_feature_sets(b, matrix_id = 'RNA_counts')) >= 2)
stopifnot('de_wilcox' %in% wb_list_ops())
iface <- wb_op_interface('de_wilcox', bundle = b)
stopifnot(is.list(iface), identical(iface\$name, 'de_wilcox') || identical(iface\$op_name, 'de_wilcox') || !is.null(iface\$inputs))
arts <- wb_art_list(b)
stopifnot(is.data.frame(arts), nrow(arts) >= 1)
golden_art <- arts[
  as.character(arts\$source_op %||% '') == 'leiden' &
    as.character(arts\$type %||% '') == 'cell_vector',
  ,
  drop = FALSE
]
stopifnot(nrow(golden_art) >= 1)
aid <- as.character(golden_art\$artifact_id[1])
prim <- wb_art_load(b, aid, expected_kind = 'cell_vector')
stopifnot(identical(as.character(prim\$kind), 'cell_vector'))
stopifnot(length(prim\$cell_id) == 600)
stopifnot(setequal(as.character(prim\$cell_id), wb_cells(b, 'core')))
stopifnot(all(c('golden_A', 'golden_B', 'golden_C') %in% unique(as.character(prim\$value))))
id <- wb_art_identity_card(b, aid)
stopifnot(is.list(id), identical(as.character(id\$core\$artifact_id), aid))
bc <- wb_art_birth_certificate(b, aid)
stopifnot(is.list(bc), identical(as.character(bc\$schema), 'artifact_birth_certificate_v1'))
stopifnot(is.data.frame(bc\$persisted_provenance\$links), nrow(bc\$persisted_provenance\$links) >= 1)
stopifnot(is.list(bc\$persisted_provenance\$run_details))
heads <- wb_prov_list_heads(b)
stopifnot(is.data.frame(heads), nrow(heads) >= 1)
cat('scworkbench smoke ok\n')
"

echo "[fullstack] generated semantic catalog freshness"
(
  cd "$ROOT/scworkbench"
  TMP_DOCS="$(mktemp -d)"
  trap 'rm -rf "$TMP_DOCS"' EXIT
  SCWB_TMP_DOCS="$TMP_DOCS" Rscript -e "
  if (!requireNamespace('devtools', quietly = TRUE) && !requireNamespace('pkgload', quietly = TRUE)) stop('devtools or pkgload required')
  if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('.', quiet = TRUE) else pkgload::load_all('.', quiet = TRUE)
  wb_refresh_semantic_catalogs(docs_dir = Sys.getenv('SCWB_TMP_DOCS'), write_graph_views = FALSE)
  "
  for path in \
    op_catalog_reference.md op_catalog_semantic.json \
    getter_catalog_reference.md getter_catalog_semantic.json \
    plot_catalog_reference.md plot_catalog_semantic.json \
    wrangler_catalog_reference.md wrangler_catalog_semantic.json \
    primitive_catalog_reference.md primitive_catalog_semantic.json \
    artifact_type_catalog_reference.md artifact_type_catalog_semantic.json \
    mutation_catalog_reference.md mutation_catalog_semantic.json \
    parameter_semantics_reference.md parameter_semantics_catalog.json \
    recipe_semantics_reference.md recipe_semantics_catalog.json \
    semantic_catalog_reference.md semantic_catalog.json \
    semantic_compatibility_graph.json semantic_catalog_audit.json
  do
    diff -u -B -I 'generated_at' -I 'Generated at:' "docs/$path" "$TMP_DOCS/$path" >/tmp/scwb_semantic_diff.txt || {
      cat /tmp/scwb_semantic_diff.txt
      echo "Semantic catalog content is stale: $path" >&2
      exit 1
    }
  done
)

echo "[fullstack] scworkbench pybench payload parity"
Rscript -e "
if (!requireNamespace('devtools', quietly = TRUE) && !requireNamespace('pkgload', quietly = TRUE)) stop('devtools or pkgload required')
if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('$ROOT/scworkbench', quiet = TRUE) else pkgload::load_all('$ROOT/scworkbench', quiet = TRUE)
source('$ROOT/scworkbench/tests/test_pybench_payload_parity.R')
stopifnot(test_pybench_payload_parity())
cat('scworkbench pybench payload parity ok\n')
"

echo "[fullstack] Shiny thin-client tripwire"
(
  cd "$ROOT"
  rg -n 'dbGetQuery|dbExecute|dbWriteTable|SELECT |INSERT |UPDATE |DELETE ' scworkbenchShiny/R | sort > /tmp/scwb_shiny_sql_current.txt || true
  sort scworkbench/inst/fullstack/shiny_sql_allowlist.txt > /tmp/scwb_shiny_sql_allowlist.txt
  if ! diff -u /tmp/scwb_shiny_sql_allowlist.txt /tmp/scwb_shiny_sql_current.txt; then
    echo "Shiny direct storage/SQL access changed. Move semantics behind scworkbench APIs or update scworkbench/inst/fullstack/shiny_sql_allowlist.txt deliberately." >&2
    exit 1
  fi
)

echo "[fullstack] pybench tests"
if [ -d "$ROOT/../pybench/.venv" ]; then
  (cd "$ROOT/../pybench" && .venv/bin/python -m pytest -q)
else
  (cd "$ROOT/../pybench" && python3 -m pytest -q)
fi

echo "[fullstack] scwb-agent tests"
if [ -d "$ROOT/scwb-agent/.venv" ]; then
  (cd "$ROOT/scwb-agent" && .venv/bin/python -m pytest -q)
elif [ -d "$ROOT/scwb-agent/.deps" ]; then
  (cd "$ROOT/scwb-agent" && PYTHONPATH=.deps:. python3 -m pytest -q)
else
  (cd "$ROOT/scwb-agent" && python3 -m pytest -q)
fi

echo "[fullstack] agent tool smoke on golden bundle"
(
  cd "$ROOT/scwb-agent"
  if [ -d ".venv" ]; then
    .venv/bin/python -m harness.cli tool-smoke summarize_bundle "{\"bundle_dir\":\"$GOLDEN_BUNDLE\",\"include_cell_set_counts\":false}"
  elif [ -d ".deps" ]; then
    PYTHONPATH=.deps:. python3 -m harness.cli tool-smoke summarize_bundle "{\"bundle_dir\":\"$GOLDEN_BUNDLE\",\"include_cell_set_counts\":false}"
  else
    python3 -m harness.cli tool-smoke summarize_bundle "{\"bundle_dir\":\"$GOLDEN_BUNDLE\",\"include_cell_set_counts\":false}"
  fi
)

echo "[fullstack] ok"
