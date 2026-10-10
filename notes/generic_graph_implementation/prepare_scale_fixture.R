# Disposable public SDK authoring/setup. Never a measured graph-memory pass.
args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(args[[2L]], .libPaths()))
library(scworkbench)
root <- normalizePath(args[[1L]], mustWork = FALSE)
stopifnot(!file.exists(root)); dir.create(root)
retained_library <- file.path(root, "library"); dir.create(retained_library)
count <- as.integer(args[[3L]])
stopifnot(count >= 3L)
cells <- vapply(seq_len(count), function(i) if (i == 1L) "cell_2" else
  if (i == 2L) "cell_10" else if (i == 3L) "cell_1" else
    paste0("cell_", i + 100L, "_", strrep("a", 192L)), character(1))
pack <- wb_operation_pack_scaffold(file.path(root, "scale-pack"),
  "scwbGraphScaleFixture", "graphscalefixt", "Fixture Author", "fixture@example.org", template = "graph")
manifest <- jsonlite::read_json(pack$manifest, simplifyVector = FALSE)
op <- manifest$operations[[3L]]
seed_op <- op
seed_op$name <- seed_op$title <- "seed_axis"
seed_op$qualified_name <- "graphscalefixt::seed_axis"; seed_op$runner <- ".seed_axis"
seed_op$inputs <- seed_op$inputs[2L]
op$name <- op$title <- "stream_graph"; op$qualified_name <- "graphscalefixt::stream_graph"
op$runner <- ".stream_graph"
op$inputs <- op$inputs[1L]; op$inputs[[1L]]$binding_policy <- "required"
op$outputs[[1L]]$axis_sources <- list(list(input_name = "source", axis_kind = "cell",
  selection_mode = "selected_graph_binding", source_binding_selector = list(
    kind = "fixed_binding_id_v1", binding_id = "annotations")))
op$outputs[[1L]]$resource_budgets <- list(max_nodes = as.character(count), max_edges = "1",
  max_incidences = as.character(count), max_attribute_fields = "3",
  max_memory_bytes = "8388608", max_collect_bytes = "4194304", max_staged_bytes = "8589934592",
  max_spill_bytes = "17179869184", max_published_bytes = "8589934592", max_wal_bytes = "8589934592",
  partition_limits = list(max_rows = "256", max_decoded_bytes = "262144"))
op$params_schema$properties <- list(nodes = list(type = "integer", minimum = 0, maximum = count),
  fault = list(type = "string", enum = list("none", "nodes", "attribute_values", "binding_mappings")))
op$params_schema$required <- list("nodes", "fault")
manifest$operations <- list(op, seed_op)
jsonlite::write_json(manifest, pack$manifest, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
stopifnot(file.copy("notes/generic_graph_implementation/scale_pack_register.R",
  file.path(pack$path, "R", "register.R"), overwrite = TRUE))
invisible(wb_operation_pack_manifest_validate(pack$manifest))
checked <- wb_operation_pack_check(pack$path, "installed", trusted = TRUE, lib.loc = args[[2L]])
stopifnot(checked$qualified)
stopifnot(file.copy(file.path(checked$library, "scwbGraphScaleFixture"),
  retained_library, recursive = TRUE))
checked$library <- retained_library
saveRDS(checked, file.path(root, "scale_pack_install.rds"))
.libPaths(c(retained_library, .libPaths()))
invisible(wb_operation_pack_load("scwbGraphScaleFixture"))

bundle <- wb_init_bundle(file.path(root, "source.bundle"))
invisible(wb_define_cells(bundle, cells))
invisible(wb_attach_matrix(bundle, "counts", Matrix::Matrix(matrix(1L, 1L, count,
  dimnames = list("fixture", cells)), sparse = TRUE)))
vector <- wb_prim_cell_vector(stats::setNames(rep("source", count), cells),
  meta = list(label = "complete retained fixture axis"))
run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"), params = list(),
  outputs = list(vector = vector))
promotion <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id), run$run_id, outputs = "vector")
source_id <- as.character(promotion$promoted$artifact_id[[1L]])
bound <- wb_session_run_op(wb_session_new(), bundle, "graphscalefixt::seed_axis",
  inputs = list(metadata = wb_ref_artifact(source_id, "vector"), min_cells = 1L))
bound_promotion <- wb_session_promote_current(bundle, bound$session, outputs = "result")
bound_id <- as.character(bound_promotion$promoted$artifact_id[bound_promotion$promoted$output == "result"][[1L]])
invisible(wb_session_discard(bound$session))
identity <- wb_art_graph_info(bundle, bound_id)
stopifnot(identity$source_authority$status == "verified")
wb_close_bundle(bundle)
saveRDS(list(schema = "scworkbench.graph.scale-fixture.v1", source_bundle = file.path(root, "source.bundle"),
  source_axis_artifact_id = source_id, seed_graph_artifact_id = bound_id, seed_descriptor = identity$descriptor_identity,
  source_axis_count = count, source_axis_utf8_bytes = sum(nchar(cells, type = "bytes")),
  pack_library = checked$library,
  pack_identity = checked$identity, core_library = args[[2L]], runtime = R.version.string),
  file.path(root, "fixture.rds"))
cat("GRAPH_SCALE_SOURCE_SETUP public_sdk=TRUE native_source_ref=retained_cell_axis complete_axis_count=", count,
  " complete_axis_utf8_bytes=", sum(nchar(cells, type = "bytes")),
  " setup_not_memory_qualification=TRUE\n", sep = "")
