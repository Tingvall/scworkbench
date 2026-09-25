test_knowledge_graph_contract <- function(bundle_dir = NULL) {
  node_cols <- c("id", "label", "node_type", "source", "source_version", "text", "payload_json")
  edge_cols <- c("id", "source_id", "target_id", "edge_type", "source", "confidence", "payload_json")

  g1 <- wb_kg_static_graph()
  g2 <- wb_kg_static_graph()
  stopifnot(identical(as.character(g1$schema_version), "scworkbench.kg.v1"))
  stopifnot(is.data.frame(g1$nodes), is.data.frame(g1$edges))
  stopifnot(all(node_cols %in% names(g1$nodes)))
  stopifnot(all(edge_cols %in% names(g1$edges)))
  stopifnot(identical(g1$nodes$id, g2$nodes$id))
  stopifnot(identical(g1$edges$id, g2$edges$id))
  stopifnot(any(g1$nodes$id == "op:slingshot_adopt"),
    !any(g1$nodes$id == "op:slingshot_fit"))
  stopifnot(any(g1$nodes$id == "recipe:trajectory_geneset_dynamics_discovery"))

  node_type <- setNames(g1$nodes$node_type, g1$nodes$id)
  edge_types <- data.frame(
    source_type = unname(node_type[g1$edges$source_id]),
    target_type = unname(node_type[g1$edges$target_id]),
    edge_type = g1$edges$edge_type,
    source_id = g1$edges$source_id,
    target_id = g1$edges$target_id,
    stringsAsFactors = FALSE
  )
  requires <- edge_types[edge_types$edge_type == "REQUIRES", , drop = FALSE]
  stopifnot(nrow(requires) > 0L)
  stopifnot(all(requires$source_type %in% c("Op", "Recipe")))
  stopifnot(!any(requires$source_type == "Primitive"))
  stopifnot(all(requires$target_type %in% c("Primitive", "ArtifactType", "Parameter")))

  produces <- edge_types[edge_types$edge_type == "PRODUCES", , drop = FALSE]
  stopifnot(nrow(produces) > 0L)
  stopifnot(all(produces$source_type %in% c("Op", "Recipe", "Run")))
  stopifnot(all(produces$target_type %in% c("Primitive", "ArtifactType", "Plot")))

  stopifnot(any(g1$edges$edge_type == "PRODUCES" &
                  g1$edges$source_id == "op:slingshot_adopt" &
                  g1$edges$target_id == "primitive:model_ref"))
  stopifnot(any(g1$edges$edge_type == "USES" &
                  g1$edges$source_id == "recipe:inspect_promoted_artifact" &
                  g1$edges$target_id == "getter:wb_art_load"))

  a0 <- wb_kg_catalog_audit()
  stopifnot(isTRUE(a0$ok))
  stopifnot(length(a0$duplicate_node_ids) == 0L)
  stopifnot(length(a0$dangling_edges) == 0L)

  tmp <- tempfile("scwb_kg_contract_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- c("c1", "c2", "c3")
  wb_define_cells(b, cells)
  mat <- Matrix::Matrix(
    matrix(
      c(5, 1, 0, 0, 4, 1, 1, 0, 3),
      nrow = 3,
      byrow = TRUE,
      dimnames = list(c("g1", "g2", "g3"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")
  coords <- data.frame(cell_id = cells, UMAP_1 = c(0, 1, 2), UMAP_2 = c(0, 1, 0), stringsAsFactors = FALSE)
  wb_attach_space(b, space_id = "umap_test", coords = coords)

  run <- wb_new_run(
    op_name = "feature_set_import",
    inputs = list(
      cell_set = "core",
      effective_n = length(cells),
      parents = character(0),
      user_inputs = list(matrix = "RNA_counts", namespace = "synthetic")
    ),
    params = list(namespace = "synthetic"),
    outputs = list(
      import_summary = wb_prim_obs_table(
        table = data.frame(
          feature_set = "metabolism",
          dynamic_score = 1.2,
          curve_class = "turns_on",
          stringsAsFactors = FALSE
        ),
        table_type = "feature_set_import_summary",
        entity_kind = "feature_set"
      )
    ),
    notes = "synthetic KG provenance test"
  )
  runs <- list()
  runs[[run$run_id]] <- run
  prom <- wb_promote_analysis(
    bundle = b,
    runs = runs,
    head_run_id = run$run_id,
    name_prefix = "KG Test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 1L)

  bg <- wb_kg_bundle_graph(b)
  stopifnot(identical(as.character(bg$schema_version), "scworkbench.kg.v1"))
  stopifnot(any(bg$nodes$node_type == "Bundle"))
  stopifnot(any(bg$nodes$node_type == "Matrix"))
  stopifnot(any(bg$nodes$node_type == "Space"))
  stopifnot(any(bg$nodes$node_type == "CellSet"))
  stopifnot(any(bg$edges$edge_type == "HAS_MATRIX"))
  stopifnot(any(bg$edges$edge_type == "HAS_SPACE"))
  stopifnot(any(bg$edges$edge_type == "HAS_CELL_SET"))

  pg <- wb_kg_provenance_graph(b)
  stopifnot(identical(as.character(pg$schema_version), "scworkbench.kg.v1"))
  stopifnot(any(pg$nodes$node_type == "Session"))
  stopifnot(any(pg$nodes$node_type == "Run"))
  stopifnot(any(pg$nodes$node_type == "Artifact"))
  stopifnot(any(pg$edges$edge_type == "PRODUCED_ARTIFACT"))
  stopifnot(any(pg$edges$edge_type == "PRODUCES"))
  stopifnot(any(pg$edges$edge_type == "BELONGS_TO_SESSION"))
  stopifnot(!any(pg$edges$edge_type == "BELONGS_TO_BUNDLE" &
                   grepl("^run:", pg$edges$source_id) &
                   grepl("^session:", pg$edges$target_id)))

  ab <- wb_kg_catalog_audit(b)
  stopifnot(isTRUE(ab$ok))
  stopifnot(length(ab$duplicate_node_ids) == 0L)
  stopifnot(length(ab$dangling_edges) == 0L)

  out_jsonl <- file.path(tempdir(), paste0("scwb_kg_jsonl_", as.integer(Sys.time())))
  man_jsonl <- wb_kg_export_jsonl(bundle = b, out_dir = out_jsonl)
  stopifnot(file.exists(file.path(out_jsonl, "kg_nodes.jsonl")))
  stopifnot(file.exists(file.path(out_jsonl, "kg_edges.jsonl")))
  stopifnot(file.exists(file.path(out_jsonl, "kg_manifest.json")))
  stopifnot(identical(as.character(man_jsonl$schema_version), "scworkbench.kg.v1"))
  stopifnot(isTRUE(jsonlite::validate(readLines(file.path(out_jsonl, "kg_nodes.jsonl"), n = 1L))))
  stopifnot(isTRUE(jsonlite::validate(readLines(file.path(out_jsonl, "kg_edges.jsonl"), n = 1L))))

  out_csv <- file.path(tempdir(), paste0("scwb_kg_csv_", as.integer(Sys.time())))
  man_csv <- wb_kg_export_neo4j_csv(bundle = b, out_dir = out_csv)
  stopifnot(file.exists(file.path(out_csv, "kg_nodes.csv")))
  stopifnot(file.exists(file.path(out_csv, "kg_edges.csv")))
  stopifnot(file.exists(file.path(out_csv, "kg_manifest.json")))
  stopifnot(identical(as.character(man_csv$schema_version), "scworkbench.kg.v1"))
  stopifnot(all(node_cols %in% names(utils::read.csv(file.path(out_csv, "kg_nodes.csv"), nrows = 1L, check.names = FALSE))))
  stopifnot(all(edge_cols %in% names(utils::read.csv(file.path(out_csv, "kg_edges.csv"), nrows = 1L, check.names = FALSE))))

  TRUE
}
