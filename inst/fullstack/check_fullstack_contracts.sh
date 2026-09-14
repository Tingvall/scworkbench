#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCWORKBENCH_ROOT="$ROOT/scworkbench"
PYBENCH_ROOT="${SCWORKBENCH_PYBENCH_ROOT:-$ROOT/../pybench}"
FULLSTACK_TMP="$(mktemp -d /tmp/scwb_fullstack.XXXXXX)"
GOLDEN_BUNDLE="${SCWB_GOLDEN_BUNDLE:-$FULLSTACK_TMP/scwb_golden}"
cleanup() {
  rm -rf -- "$FULLSTACK_TMP"
  [[ -z "${KG_EXPORT_DIR:-}" ]] || rm -rf -- "$KG_EXPORT_DIR"
}
trap cleanup EXIT

if [[ ! -d "$SCWORKBENCH_ROOT" ]]; then
  echo "Missing required scworkbench checkout: $SCWORKBENCH_ROOT" >&2
  exit 1
fi
if [[ ! -d "$PYBENCH_ROOT" ]]; then
  echo "Missing required PyBench checkout: $PYBENCH_ROOT" >&2
  exit 1
fi

echo "[fullstack] root: $ROOT"
echo "[fullstack] runtime boundary: scworkbench + PyBench"

Rscript "$SCWORKBENCH_ROOT/inst/ci/validate_release_metadata.R" \
  "$SCWORKBENCH_ROOT" "$PYBENCH_ROOT"

if [[ -n "${SCWORKBENCH_PYBENCH_PYTHON:-}" ]]; then
  if [[ "$SCWORKBENCH_PYBENCH_PYTHON" == /* ]]; then
    PYBENCH_PYTHON="$SCWORKBENCH_PYBENCH_PYTHON"
  else
    PYBENCH_PYTHON="$(command -v "$SCWORKBENCH_PYBENCH_PYTHON")"
  fi
elif [[ -x "$PYBENCH_ROOT/.venv/bin/python" ]]; then
  PYBENCH_PYTHON="$PYBENCH_ROOT/.venv/bin/python"
else
  PYBENCH_PYTHON="$(command -v python3)"
fi
if [[ ! -x "$PYBENCH_PYTHON" ]]; then
  echo "PyBench Python is not executable: $PYBENCH_PYTHON" >&2
  exit 1
fi
export SCWORKBENCH_PYBENCH_PYTHON="$PYBENCH_PYTHON"

echo "[fullstack] generating golden bundle"
Rscript "$SCWORKBENCH_ROOT/inst/golden_bundle/create_golden_bundle.R" "$GOLDEN_BUNDLE"
export PYBENCH_GOLDEN_BUNDLE="$FULLSTACK_TMP/pybench_golden"
cp -a -- "$GOLDEN_BUNDLE" "$PYBENCH_GOLDEN_BUNDLE"
GOLDEN_IDENTITY="$(
  cd "$PYBENCH_ROOT"
  PYTHONPATH=tests "$PYBENCH_PYTHON" -m external_contracts "$PYBENCH_GOLDEN_BUNDLE"
)"
case "$GOLDEN_IDENTITY" in
  pybench-external-directory-sha256-v1:*) ;;
  *) echo "Unexpected PyBench golden-bundle identity: $GOLDEN_IDENTITY" >&2; exit 1 ;;
esac
export PYBENCH_GOLDEN_BUNDLE_SHA256="${GOLDEN_IDENTITY#*:}"
export PYBENCH_SCWORKBENCH_SOURCE_DIR="$(realpath -e "$SCWORKBENCH_ROOT")"
export PYBENCH_SCWORKBENCH_PROTOCOL_DIR="$PYBENCH_SCWORKBENCH_SOURCE_DIR/inst/protocol"

echo "[fullstack] scworkbench KG JSONL export"
KG_EXPORT_DIR="$(mktemp -d /tmp/scwb_kg_export.XXXXXX)"
echo "[fullstack] kg_export_dir: $KG_EXPORT_DIR"
SCWB_KG_EXPORT_DIR="$KG_EXPORT_DIR" Rscript -e "
if (!requireNamespace('devtools', quietly = TRUE) && !requireNamespace('pkgload', quietly = TRUE)) stop('devtools or pkgload required')
if (!requireNamespace('jsonlite', quietly = TRUE)) stop('jsonlite required')
if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('$SCWORKBENCH_ROOT', quiet = TRUE) else pkgload::load_all('$SCWORKBENCH_ROOT', quiet = TRUE)
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

echo "[fullstack] scworkbench engine smoke"
Rscript -e "
if (!requireNamespace('devtools', quietly = TRUE) && !requireNamespace('pkgload', quietly = TRUE)) stop('devtools or pkgload required')
if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('$SCWORKBENCH_ROOT', quiet = TRUE) else pkgload::load_all('$SCWORKBENCH_ROOT', quiet = TRUE)
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
cert <- wb_entity_certificate(b, 'artifact', aid)
stopifnot(is.list(cert), identical(as.character(cert\$schema), 'scworkbench.provenance.entity_certificate.v1'))
stopifnot(identical(as.character(cert\$subject\$id), aid))
stopifnot(identical(as.character(cert\$producer\$status), 'available'))
heads <- wb_prov_list_heads(b)
stopifnot(is.data.frame(heads), nrow(heads) >= 1)
cat('scworkbench smoke ok\n')
"

echo "[fullstack] generated semantic catalog freshness"
(
  cd "$SCWORKBENCH_ROOT"
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
if (requireNamespace('devtools', quietly = TRUE)) devtools::load_all('$SCWORKBENCH_ROOT', quiet = TRUE) else pkgload::load_all('$SCWORKBENCH_ROOT', quiet = TRUE)
source('$SCWORKBENCH_ROOT/tests/test_pybench_payload_parity.R')
stopifnot(test_pybench_payload_parity())
cat('scworkbench pybench payload parity ok\n')
"

echo "[fullstack] pybench tests"
(cd "$PYBENCH_ROOT" && "$PYBENCH_PYTHON" -m pytest -q)

echo "[fullstack] ok"
