.deep_validation_copy <- function(from, to) {
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  entries <- list.files(from, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  rel <- substring(entries, nchar(from) + 2L)
  dirs <- entries[dir.exists(entries)]
  if (length(dirs)) for (path in dirs) dir.create(file.path(to, substring(path, nchar(from) + 2L)), recursive = TRUE, showWarnings = FALSE)
  files <- entries[!dir.exists(entries)]
  if (length(files)) {
    for (i in seq_along(files)) {
      target <- file.path(to, substring(files[i], nchar(from) + 2L))
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(files[i], target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE))
    }
  }
  invisible(to)
}

.deep_validation_db <- function(path, sql, params = NULL) {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (is.null(params)) DBI::dbExecute(con, sql) else DBI::dbExecute(con, sql, params = params)
}

.deep_validation_codes <- function(path, level = "content") {
  as.character(wb_bundle_validation_report(path, level = level)$diagnostics$code)
}

.deep_validation_mutant <- function(base, root, label, mutate, level = "content") {
  path <- file.path(root, label)
  .deep_validation_copy(base, path)
  force(mutate(path))
  .deep_validation_codes(path, level = level)
}

test_deep_bundle_integrity_validation_contract <- function() {
  root <- tempfile("scwb_deep_validation_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  base <- file.path(root, "valid.bundle")
  b <- wb_init_bundle(base, overwrite = TRUE)
  cells <- paste0("pbmc_cell_", 1:6)
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, dataset_id = "pbmc", cluster = rep(c("naive", "activated"), each = 3),
    lane = rep(c("L1", "L2"), 3), stringsAsFactors = FALSE
  ), dataset_id = "pbmc")
  counts <- Matrix::Matrix(matrix(
    c(1,0,2,0,3,0, 0,2,0,2,0,2, 4,0,1,0,1,0, 0,3,0,1,0,4),
    nrow = 4, byrow = TRUE, dimnames = list(paste0("gene_", 1:4), cells)
  ), sparse = TRUE)
  wb_attach_matrix(b, "RNA_counts", counts, feature_type = "gene")
  wb_attach_space(b, "pca", data.frame(cell_id = cells, x = seq_along(cells), y = rev(seq_along(cells))))

  # A durable model registry payload supplies model/path validation without a
  # heavyweight fitting dependency.
  dir.create(file.path(base, "models"), recursive = TRUE)
  saveRDS(list(engine = "fixture", coefficients = c(1, 2)), file.path(base, "models", "fixture.rds"))
  scworkbench:::.wb_ensure_space_models_table(b$con)
  DBI::dbExecute(b$con, "INSERT INTO space_models(space_id,model_type,source_space_id,dims_json,cell_set,uwot_args_json,seed,model_path,created_at,provenance_json) VALUES('fixture_model','rds_fixture','pca','[1,2]','core','{}',1,'models/fixture.rds','2026-08-03T00:00:00+0200','{}');")

  # Promote a small multi-run PBMC analysis so artifact payload identities and
  # the provenance DAG are both exercised.
  s <- wb_session_new()
  a <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "cluster", vector_name = "cluster", value_type = "categorical", missing_policy = "error", cell_set = "all", min_cells = 1L)); s <- a$session
  l <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "lane", vector_name = "lane", value_type = "categorical", missing_policy = "error", cell_set = "all", min_cells = 1L)); s <- l$session
  assoc <- wb_session_run_op(s, b, "cell_vector_association", inputs = list(a = wb_ref_run(a$run$run_id, "vector"), b = wb_ref_run(l$run$run_id, "vector"), cell_set = "all", min_cells = 1L, min_n_per_group = 1L, method = "auto")); s <- assoc$session
  wb_session_promote_current(b, s, outputs = list(wb_ref_run(assoc$run$run_id, "summary"), wb_ref_run(assoc$run$run_id, "detail")), created_by = "deep-validation-test")
  scworkbench:::.wb_with_mutation_context(b, route = "ingestion", code = wb_refresh_manifest(b))
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)

  structural <- wb_bundle_validation_report(base, "structural")
  content <- wb_bundle_validation_report(base, "content")
  recipient <- wb_bundle_validation_report(base, "recipient")
  if (!isTRUE(content$ok)) print(content$diagnostics)
  if (!isTRUE(recipient$ok)) print(recipient$diagnostics)
  stopifnot(isTRUE(structural$ok), isTRUE(content$ok), isTRUE(recipient$ok),
            identical(structural$completed_levels, "structural"),
            identical(content$completed_levels, c("structural", "content")),
            identical(recipient$completed_levels, c("structural", "content", "recipient")),
            nrow(structural$skipped_checks) >= 1L,
            all(c("code","severity","check_class","entity_kind","entity_id","path","table","expected","observed","message") %in% names(content$diagnostics)),
            all(c("check_class","elapsed_seconds") %in% names(content$elapsed_by_check_class)),
            identical(recipient$pre_validation_fingerprint, recipient$post_validation_fingerprint),
            isTRUE(wb_validate_bundle(base, read_only = TRUE)))

  expect <- function(code, codes) stopifnot(code %in% codes)
  manifest_codes <- .deep_validation_mutant(base, root, "manifest_mismatch", function(p) {
    man <- jsonlite::read_json(file.path(p, "manifest.json"), simplifyVector = FALSE)
    man$counts$n_cells <- as.integer(man$counts$n_cells) + 1L
    jsonlite::write_json(man, file.path(p, "manifest.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  })
  expect("MANIFEST_REGISTRY_MISMATCH", manifest_codes)

  duplicate_cells <- .deep_validation_mutant(base, root, "duplicate_cells", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); on.exit(DBI::dbDisconnect(con), add=TRUE)
    row <- DBI::dbGetQuery(con,"SELECT fragment_id,cell_ids_json FROM matrix_fragments LIMIT 1;")
    ids <- jsonlite::fromJSON(row$cell_ids_json[1]); ids[2] <- ids[1]
    DBI::dbExecute(con,"UPDATE matrix_fragments SET cell_ids_json=? WHERE fragment_id=?;",params=list(jsonlite::toJSON(ids,auto_unbox=TRUE),row$fragment_id[1]))
  })
  expect("MATRIX_CELL_IDENTITY_DUPLICATE", duplicate_cells)

  duplicate_features <- .deep_validation_mutant(base, root, "duplicate_features", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); on.exit(DBI::dbDisconnect(con), add=TRUE)
    row <- DBI::dbGetQuery(con,"SELECT fragment_id,feature_ids_json FROM matrix_fragments LIMIT 1;")
    ids <- jsonlite::fromJSON(row$feature_ids_json[1]); ids[2] <- ids[1]
    DBI::dbExecute(con,"UPDATE matrix_fragments SET feature_ids_json=? WHERE fragment_id=?;",params=list(jsonlite::toJSON(ids,auto_unbox=TRUE),row$fragment_id[1]))
  })
  expect("MATRIX_FEATURE_IDENTITY_DUPLICATE", duplicate_features)

  reordered <- .deep_validation_mutant(base, root, "fragment_order", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); on.exit(DBI::dbDisconnect(con), add=TRUE)
    row <- DBI::dbGetQuery(con,"SELECT fragment_id,cell_ids_json FROM matrix_fragments LIMIT 1;")
    ids <- rev(jsonlite::fromJSON(row$cell_ids_json[1]))
    DBI::dbExecute(con,"UPDATE matrix_fragments SET cell_ids_json=? WHERE fragment_id=?;",params=list(jsonlite::toJSON(ids,auto_unbox=TRUE),row$fragment_id[1]))
  })
  expect("MATRIX_PAYLOAD_CELL_ORDER_MISMATCH", reordered)
  expect("MATRIX_FRAGMENT_CELL_ORDER_MISMATCH", reordered)

  gap <- .deep_validation_mutant(base, root, "fragment_gap", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); on.exit(DBI::dbDisconnect(con), add=TRUE)
    row <- DBI::dbGetQuery(con,"SELECT fragment_id,cell_ids_json FROM matrix_fragments LIMIT 1;")
    ids <- jsonlite::fromJSON(row$cell_ids_json[1]); ids <- ids[-length(ids)]
    DBI::dbExecute(con,"UPDATE matrix_fragments SET cell_ids_json=?,n_cells=? WHERE fragment_id=?;",params=list(jsonlite::toJSON(ids,auto_unbox=TRUE),length(ids),row$fragment_id[1]))
  })
  expect("MATRIX_FRAGMENT_CELL_COVERAGE_GAP", gap)

  overlap <- .deep_validation_mutant(base, root, "fragment_overlap", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); on.exit(DBI::dbDisconnect(con), add=TRUE)
    row <- DBI::dbGetQuery(con,"SELECT * FROM matrix_fragments LIMIT 1;")
    DBI::dbExecute(con,"INSERT INTO matrix_fragments(fragment_id,matrix_id,storage,path,n_features,n_cells,feature_ids_json,cell_ids_json,source,created_at,description) VALUES(?,?,?,?,?,?,?,?,?,?,?);",params=list("overlap_fragment",row$matrix_id[1],row$storage[1],row$path[1],row$n_features[1],row$n_cells[1],row$feature_ids_json[1],row$cell_ids_json[1],"corruption","2026-08-03T01:00:00+0200","corruption"))
  })
  expect("MATRIX_FRAGMENT_CELL_OVERLAP", overlap)

  missing_matrix <- .deep_validation_mutant(base, root, "missing_matrix", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); rel <- DBI::dbGetQuery(con,"SELECT path FROM matrices LIMIT 1;")$path[1]; DBI::dbDisconnect(con)
    file.rename(file.path(p,rel),paste0(file.path(p,rel),".removed"))
  })
  expect("PAYLOAD_MISSING", missing_matrix)

  altered_matrix <- .deep_validation_mutant(base, root, "altered_matrix", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); rel <- DBI::dbGetQuery(con,"SELECT path FROM matrices LIMIT 1;")$path[1]; DBI::dbDisconnect(con)
    f <- file.path(p,rel,"row_names"); writeLines(rev(readLines(f,warn=FALSE)),f,useBytes=TRUE)
  })
  stopifnot(any(c("MATRIX_PAYLOAD_FEATURE_ORDER_MISMATCH","MATRIX_PAYLOAD_UNREADABLE","MATRIX_CONTENT_IDENTITY_MISMATCH") %in% altered_matrix))

  altered_space <- .deep_validation_mutant(base, root, "altered_space", function(p) .deep_validation_db(p,"UPDATE space_2d SET x=x+100 WHERE space_id='pca' AND cell_id='pbmc_cell_1';"))
  expect("SPACE_CONTENT_IDENTITY_MISMATCH", altered_space)
  missing_space <- .deep_validation_mutant(base, root, "missing_space", function(p) .deep_validation_db(p,"DELETE FROM space_2d WHERE space_id='pca';"))
  expect("SPACE_PAYLOAD_INVALID", missing_space)

  missing_model <- .deep_validation_mutant(base, root, "missing_model", function(p) file.rename(file.path(p,"models","fixture.rds"),file.path(p,"models","fixture.removed")))
  expect("PAYLOAD_MISSING", missing_model)
  altered_model <- .deep_validation_mutant(base, root, "altered_model", function(p) writeLines("not an RDS",file.path(p,"models","fixture.rds")))
  expect("MODEL_PAYLOAD_UNREADABLE", altered_model)

  altered_artifact <- .deep_validation_mutant(base, root, "altered_artifact", function(p) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(p,"db","app.sqlite")); row <- DBI::dbGetQuery(con,"SELECT artifact_id,row_json FROM artifact_table_rows LIMIT 1;")
    x <- jsonlite::fromJSON(row$row_json[1],simplifyVector=FALSE); x$corruption_marker <- "changed"
    DBI::dbExecute(con,"UPDATE artifact_table_rows SET row_json=? WHERE artifact_id=? AND row_idx=1;",params=list(jsonlite::toJSON(x,auto_unbox=TRUE,null="null"),row$artifact_id[1])); DBI::dbDisconnect(con)
  })
  expect("ARTIFACT_CONTENT_IDENTITY_MISMATCH", altered_artifact)
  missing_artifact <- .deep_validation_mutant(base, root, "missing_artifact", function(p) {
    .deep_validation_db(p,"DELETE FROM artifact_tables WHERE artifact_id=(SELECT artifact_id FROM artifacts WHERE type IN ('feature_table','obs_table') LIMIT 1);")
  })
  expect("ARTIFACT_PAYLOAD_MISSING", missing_artifact)

  bad_source <- .deep_validation_mutant(base, root, "malformed_source", function(p) {
    con<-DBI::dbConnect(RSQLite::SQLite(),file.path(p,"db","app.sqlite")); row<-DBI::dbGetQuery(con,"SELECT snapshot_id,run_id,source_id,source_json FROM prov_source_inputs LIMIT 1;"); x<-jsonlite::fromJSON(row$source_json[1],simplifyVector=FALSE); x$checksum_algorithm<-"sha256"; x$checksum<-"bad"; DBI::dbExecute(con,"UPDATE prov_source_inputs SET source_json=? WHERE snapshot_id=? AND run_id=? AND source_id=?;",params=list(jsonlite::toJSON(x,auto_unbox=TRUE),row$snapshot_id[1],row$run_id[1],row$source_id[1])); DBI::dbDisconnect(con)
  })
  expect("SOURCE_CHECKSUM_MALFORMED", bad_source)

  dangling <- .deep_validation_mutant(base, root, "dangling_provenance", function(p) {
    con<-DBI::dbConnect(RSQLite::SQLite(),file.path(p,"db","app.sqlite")); sid<-DBI::dbGetQuery(con,"SELECT snapshot_id FROM prov_heads LIMIT 1;")$snapshot_id[1]
    DBI::dbExecute(con,"INSERT INTO prov_run_edges(snapshot_id,parent_run_id,child_run_id,edge_type,edge_label) VALUES(?, 'missing_parent','missing_child','depends','corrupt');",params=list(sid))
    DBI::dbExecute(con,"INSERT INTO prov_run_outputs(snapshot_id,run_id,output_name,primitive_kind,output_hash,artifact_id) VALUES(?,'missing_run','missing_output','obs_table','bad','missing_artifact');",params=list(sid))
    DBI::dbExecute(con,"INSERT INTO prov_source_inputs(snapshot_id,run_id,source_id,source_json,checksum_status) VALUES(?,'missing_run','missing_source','{}','declared');",params=list(sid))
    DBI::dbExecute(con,"INSERT INTO prov_run_entity_bindings(snapshot_id,commit_id,run_id,direction,binding_name,entity_kind,entity_id,relationship_type,path,content_hash,source) VALUES(?,NULL,'missing_run','output','missing','space','missing_space','MATERIALIZES',NULL,NULL,'corrupt');",params=list(sid)); DBI::dbDisconnect(con)
  })
  for (code in c("PROVENANCE_DANGLING_DAG_EDGE","PROVENANCE_DANGLING_OUTPUT_RUN","PROVENANCE_DANGLING_OUTPUT_ARTIFACT","PROVENANCE_DANGLING_ENTITY_BINDING_RUN","PROVENANCE_DANGLING_ENTITY_BINDING","SOURCE_INPUT_DANGLING_RUN")) expect(code,dangling)

  incomplete <- .deep_validation_mutant(base, root, "incomplete", function(p) .deep_validation_db(p,"INSERT INTO prov_commits(commit_id,created_at,state,selected_outputs_json,runtime_fingerprint_json) VALUES('pending_commit','2026-08-03','pending','[]','{}');"))
  expect("INCOMPLETE_COMMIT", incomplete)
  materialization <- .deep_validation_mutant(base, root, "materialization", function(p) {
    .deep_validation_db(p,"INSERT INTO prov_commits(commit_id,created_at,state,selected_outputs_json,runtime_fingerprint_json) VALUES('material_commit','2026-08-03','complete','[]','{}');")
    .deep_validation_db(p,"INSERT INTO prov_materializations(commit_id,run_id,output_name,primitive_kind,path,output_hash,content_sha256) VALUES('material_commit','missing_run','out','obs_table','provenance/materializations/missing.rds','hash',NULL);")
  })
  expect("PAYLOAD_MISSING", materialization)
  expect("MATERIALIZATION_DANGLING_RUN", materialization)

  illegal_history <- .deep_validation_mutant(base, root, "illegal_history", function(p) .deep_validation_db(p,"INSERT INTO entity_lifecycle(entity_kind,entity_id,lifecycle_state,identity_hash,provenance_bound,created_at,updated_at) VALUES('artifact','deleted_history','superseded',NULL,1,'2026-08-03','2026-08-03');"))
  expect("ILLEGAL_HISTORICAL_ENTITY_DELETION", illegal_history)
  path_escape <- .deep_validation_mutant(base, root, "path_escape", function(p) .deep_validation_db(p,"UPDATE space_models SET model_path='../outside.rds' WHERE space_id='fixture_model';"))
  expect("PATH_ESCAPE", path_escape)
  pending <- .deep_validation_mutant(base, root, "pending_residue", function(p) {
    dir.create(file.path(p,"provenance",".pending","orphan"),recursive=TRUE)
    file.create(file.path(p,"provenance",".pending","orphan","payload"))
  }, level="recipient")
  expect("PENDING_WORKSPACE_RESIDUE", pending)

  active_path <- file.path(root,"active_writer"); .deep_validation_copy(base,active_path)
  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(active_path,operation="validation contention fixture")
  active <- .deep_validation_codes(active_path,"recipient")
  scworkbench:::.wb_bundle_writer_lock_release(lock)
  expect("ACTIVE_BUNDLE_WRITER",active)

  wal <- .deep_validation_mutant(base, root, "unresolved_wal", function(p) file.create(paste0(file.path(p,"db","app.sqlite"),"-wal")), level="recipient")
  expect("SQLITE_UNRESOLVED_JOURNAL_STATE",wal)
  TRUE
}
