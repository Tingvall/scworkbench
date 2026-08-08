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

.deep_validation_refresh_manifest <- function(path) {
  bundle <- wb_open_bundle(path)
  on.exit(wb_close_bundle(bundle), add = TRUE)
  scworkbench:::.wb_with_mutation_context(
    bundle, route = "ingestion", code = wb_refresh_manifest(bundle)
  )
  invisible(TRUE)
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
  source_path <- file.path(root,"source.raw"); writeBin(as.raw(1:64),source_path)
  source_identity <- list(inputs=list(wb_source_input(path=source_path,uri="https://example.org/GSEFIX/source.raw",source_id="deep_fixture_source",accession="GSEFIX",role="counts",format="raw",scope="external_file",accession_derived=TRUE)))
  scworkbench:::.wb_record_declared_ingestion(b,"deep_fixture_source",matrix_ids="RNA_counts",source="test",source_identity=source_identity)
  wb_attach_space(b, "pca", data.frame(cell_id = cells, x = seq_along(cells), y = rev(seq_along(cells))))
  wb_attach_space(b, "fixture_model", data.frame(cell_id = cells, x = seq_along(cells), y = rev(seq_along(cells))))

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

  expect <- function(code, codes) {
    if (!code %in% codes) stop("Expected diagnostic ",code,"; observed: ",paste(sort(unique(codes)),collapse=", "),call.=FALSE)
    invisible(TRUE)
  }
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
  altered_model_report <- wb_bundle_validation_report(file.path(root,"altered_model"), level="content")
  stopifnot(isFALSE(altered_model_report$path_contract$unsafe_payloads_loaded))
  stopifnot(!"MODEL_PAYLOAD_UNREADABLE" %in% altered_model_report$diagnostics$code)

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
    con<-DBI::dbConnect(RSQLite::SQLite(),file.path(p,"db","app.sqlite")); row<-DBI::dbGetQuery(con,"SELECT snapshot_id,run_id,source_id,source_json FROM prov_source_inputs LIMIT 1;"); x<-jsonlite::fromJSON(row$source_json[1],simplifyVector=FALSE); x$checksum_algorithm<-"sha256"; x$checksum<-"bad"; x$sha256<-"bad"; DBI::dbExecute(con,"UPDATE prov_source_inputs SET source_json=? WHERE snapshot_id=? AND run_id=? AND source_id=?;",params=list(jsonlite::toJSON(x,auto_unbox=TRUE),row$snapshot_id[1],row$run_id[1],row$source_id[1])); DBI::dbDisconnect(con)
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

.deep_validation_fingerprint <- function(path) {
  files <- sort(list.files(path, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  files <- files[!dir.exists(files)]
  rel <- substring(files, nchar(path) + 2L)
  hashes <- vapply(files, digest::digest, character(1), file = TRUE, algo = "sha256")
  digest::digest(list(path = rel, sha256 = hashes), algo = "sha256", serialize = TRUE)
}

.deep_validation_rehash_run <- function(con, row, symbolic_inputs_json = row$symbolic_inputs_json,
                                        execution_inputs_json = row$execution_inputs_json) {
  scworkbench:::.wb_prov_run_hash(
    row$op_name, row$params_json, row$inputs_json,
    symbolic_inputs_json, execution_inputs_json
  )
}

test_deep_bundle_integrity_validation_closure_contract <- function() {
  root <- tempfile("scwb_deep_validation_closure_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  base <- file.path(root, "valid.bundle")
  b <- wb_init_bundle(base, overwrite = TRUE)
  cells <- paste0("cell_", 1:6)
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, dataset_id = "pbmc", cluster = rep(c("a", "b"), each = 3L),
    lane = rep(c("one", "two"), 3L), stringsAsFactors = FALSE
  ), dataset_id = "pbmc")
  counts <- Matrix::Matrix(matrix(
    c(1,0,2,0,3,0, 0,2,0,2,0,2, 4,0,1,0,1,0, 0,3,0,1,0,4),
    nrow = 4L, byrow = TRUE, dimnames = list(paste0("gene_", 1:4), cells)
  ), sparse = TRUE)
  wb_attach_matrix(b, "RNA_counts", counts, feature_type = "gene")
  wb_attach_space(b, "pca", data.frame(cell_id = cells, x = seq_along(cells), y = rev(seq_along(cells))))
  wb_attach_space(b, "fixture_model", data.frame(cell_id = cells, x = seq_along(cells), y = rev(seq_along(cells))))

  dir.create(file.path(base, "models"), recursive = TRUE)
  saveRDS(list(engine = "fixture", coefficients = c(1, 2)), file.path(base, "models", "fixture.rds"))
  scworkbench:::.wb_ensure_space_models_table(b$con)
  DBI::dbExecute(b$con, "INSERT INTO space_models(space_id,model_type,source_space_id,dims_json,cell_set,uwot_args_json,seed,model_path,created_at,provenance_json) VALUES('fixture_model','rds_fixture','pca','[1,2]','core','{}',1,'models/fixture.rds','2026-08-04T00:00:00+0200','{}');")
  scworkbench:::.wb_record_declared_ingestion(
    b, "fixture_model_ingestion", source = "fixture",
    additional_outputs = list(model = wb_prim_model_ref("fixture_model", "pca", engine = "rds_fixture"))
  )

  session <- wb_session_new()
  a <- wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "cluster", vector_name = "cluster", value_type = "categorical",
    missing_policy = "error", cell_set = "all", min_cells = 1L
  )); session <- a$session
  lane <- wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "lane", vector_name = "lane", value_type = "categorical",
    missing_policy = "error", cell_set = "all", min_cells = 1L
  )); session <- lane$session
  assoc <- wb_session_run_op(session, b, "cell_vector_association", inputs = list(
    a = wb_ref_run(a$run$run_id, "vector"), b = wb_ref_run(lane$run$run_id, "vector"),
    cell_set = "all", min_cells = 1L, min_n_per_group = 1L, method = "auto"
  )); session <- assoc$session
  wb_session_promote_current(
    b, session,
    outputs = list(wb_ref_run(assoc$run$run_id, "summary"), wb_ref_run(assoc$run$run_id, "detail")),
    created_by = "deep-validation-closure"
  )

  promote_set <- function(target) {
    executed <- wb_session_run_op(wb_session_new(), b, "cell_set_derive", inputs = list(
      cell_set = "core", target_cell_set = target, role = "analysis_universe",
      status = "accepted", overwrite = TRUE, min_cells = 1L,
      created_by = "deep-validation-closure"
    ))
    wb_session_promote_current(
      b, executed$session, outputs = "manifest",
      name_prefix = sub("^set:", "", target), created_by = "deep-validation-closure"
    )
  }
  promote_set("set:retract_me")
  promote_set("set:reject_me")
  scworkbench:::.wb_with_mutation_context(b, route = "ingestion", code = wb_refresh_manifest(b))
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)
  b <- NULL

  reports <- lapply(c("structural", "content", "recipient"), function(level) {
    wb_bundle_validation_report(base, level)
  })
  repeated_content <- wb_bundle_validation_report(base, "content")
  stopifnot(all(vapply(reports, function(report) isTRUE(report$ok), logical(1))))
  stopifnot(identical(reports[[2]]$diagnostics, repeated_content$diagnostics))
  coverage <- reports[[2]]$content_coverage
  owned <- coverage$entity_kind %in% c("matrix", "space", "model", "artifact", "cell_set", "feature_set")
  stopifnot(nrow(coverage) > 0L, all(coverage$verification_status[owned] == "content_verified"))
  stopifnot(!any(reports[[2]]$diagnostics$code %in% c(
    "DURABLE_CONTENT_IDENTITY_MISSING", "DURABLE_CONTENT_IDENTITY_LEGACY_UNVERIFIABLE"
  )))

  expect <- function(code, codes) {
    if (!code %in% codes) stop("Expected diagnostic ",code,"; observed: ",paste(sort(unique(codes)),collapse=", "),call.=FALSE)
    invisible(TRUE)
  }
  run_mutant <- function(label, mutate) .deep_validation_mutant(base, root, label, mutate)

  expect("RUN_HASH_MISMATCH", run_mutant("params_tamper", function(path) {
    .deep_validation_db(path, "UPDATE prov_runs SET params_json=? WHERE rowid=(SELECT rowid FROM prov_runs LIMIT 1);", params = list('{"route":"tampered"}'))
  }))
  expect("RUN_INPUTS_JSON_MALFORMED", run_mutant("malformed_inputs", function(path) {
    .deep_validation_db(path, "UPDATE prov_runs SET inputs_json='[' WHERE rowid=(SELECT rowid FROM prov_runs LIMIT 1);")
  }))
  expect("RUN_HASH_MISMATCH", run_mutant("execution_tamper", function(path) {
    .deep_validation_db(path, "UPDATE prov_runs SET execution_inputs_json=? WHERE rowid=(SELECT rowid FROM prov_runs LIMIT 1);", params = list('{"effective_n":999,"resolved":{}}'))
  }))
  expect("RUN_HASH_MISMATCH", run_mutant("symbolic_tamper", function(path) {
    .deep_validation_db(path, "UPDATE prov_runs SET symbolic_inputs_json=? WHERE rowid=(SELECT rowid FROM prov_runs LIMIT 1);", params = list('{"changed":true}'))
  }))
  expect("INTEGRITY_DIGEST_SCHEME_CONTRADICTION", run_mutant("stale_run_hash", function(path) {
    .deep_validation_db(path, "UPDATE prov_runs SET run_hash='stale' WHERE rowid=(SELECT rowid FROM prov_runs LIMIT 1);")
  }))
  expect("INTEGRITY_DIGEST_SCHEME_CONTRADICTION", run_mutant("stale_contract_hash", function(path) {
    .deep_validation_db(path, "UPDATE prov_runs SET contract_hash='stale' WHERE rowid=(SELECT rowid FROM prov_runs LIMIT 1);")
  }))
  expect("RUN_TYPED_INPUT_BINDING_MISSING", run_mutant("dangling_typed_input", function(path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite")); on.exit(DBI::dbDisconnect(con), add = TRUE)
    row <- DBI::dbGetQuery(con, "SELECT rowid,* FROM prov_runs LIMIT 1;")
    execution <- jsonlite::toJSON(list(effective_n = 1L, resolved = list(query = list(kind = "space", space_id = "missing_space"))), auto_unbox = TRUE)
    hash <- .deep_validation_rehash_run(con, row, execution_inputs_json = execution)
    DBI::dbExecute(con, "UPDATE prov_runs SET execution_inputs_json=?,run_hash=? WHERE rowid=?;", params = list(execution, hash, row$rowid[1]))
  }))
  expect("RUN_SYMBOLIC_INPUT_ANCESTRY_MISSING", run_mutant("dangling_symbolic_input", function(path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite")); on.exit(DBI::dbDisconnect(con), add = TRUE)
    row <- DBI::dbGetQuery(con, "SELECT rowid,* FROM prov_runs LIMIT 1;")
    symbolic <- jsonlite::toJSON(list(ref_type = "run", run_id = "missing_parent", output = "missing_output"), auto_unbox = TRUE)
    hash <- .deep_validation_rehash_run(con, row, symbolic_inputs_json = symbolic)
    DBI::dbExecute(con, "UPDATE prov_runs SET symbolic_inputs_json=?,run_hash=? WHERE rowid=?;", params = list(symbolic, hash, row$rowid[1]))
  }))

  expect("SOURCE_IDENTITY_MALFORMED", run_mutant("source_identity_malformed", function(path) {
    .deep_validation_db(path, "UPDATE prov_source_identities SET source_identity_json=? WHERE rowid=(SELECT rowid FROM prov_source_identities LIMIT 1);", params = list('{"inputs":[{}]}'))
  }))
  dangling_source_codes <- run_mutant("source_identity_dangling", function(path) {
    .deep_validation_db(path, "UPDATE prov_source_identities SET run_id='missing_run',matrix_id='missing_matrix' WHERE rowid=(SELECT rowid FROM prov_source_identities LIMIT 1);")
  })
  expect("SOURCE_IDENTITY_DANGLING_RUN", dangling_source_codes)
  expect("SOURCE_IDENTITY_DANGLING_MATRIX", dangling_source_codes)

  expect("ARTIFACT_DANGLING_ANCESTRY", run_mutant("artifact_ancestry", function(path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite")); on.exit(DBI::dbDisconnect(con), add = TRUE)
    row <- DBI::dbGetQuery(con, "SELECT artifact_id,provenance_json FROM artifacts LIMIT 1;")
    provenance <- jsonlite::fromJSON(row$provenance_json[1], simplifyVector = FALSE)
    provenance$parent_artifacts <- list("missing_artifact_parent")
    DBI::dbExecute(con, "UPDATE artifacts SET provenance_json=? WHERE artifact_id=?;", params = list(jsonlite::toJSON(provenance, auto_unbox = TRUE, null = "null"), row$artifact_id[1]))
  }))

  for (state in c("retracted", "rejected")) {
    codes <- run_mutant(paste0(state, "_payload_deleted"), function(path) {
      bundle <- wb_open_bundle(path)
      if (identical(state, "retracted")) wb_entity_retract(bundle, "cell_set", "set:retract_me", reason = "closure fixture")
      else wb_entity_reject(bundle, "cell_set", "set:reject_me", reason = "closure fixture")
      wb_close_bundle(bundle)
      id <- if (identical(state, "retracted")) "set:retract_me" else "set:reject_me"
      .deep_validation_db(path, "DELETE FROM cell_set_membership WHERE cell_set=?;", params = list(id))
    })
    expect("ILLEGAL_HISTORICAL_ENTITY_DELETION", codes)
  }

  legacy_path <- file.path(root, "legacy_identity")
  .deep_validation_copy(base, legacy_path)
  .deep_validation_db(legacy_path, "UPDATE prov_run_outputs SET content_identity_scheme=NULL WHERE primitive_kind='matrix';")
  .deep_validation_db(legacy_path, "UPDATE prov_run_entity_bindings SET content_identity_scheme=NULL WHERE entity_kind='matrix';")
  .deep_validation_db(legacy_path, "UPDATE entity_lifecycle SET identity_scheme=NULL WHERE entity_kind='matrix';")
  .deep_validation_refresh_manifest(legacy_path)
  legacy <- wb_bundle_validation_report(legacy_path, "content")
  stopifnot(isTRUE(legacy$ok), identical(legacy$status, "ok_with_warnings"))
  expect("CONTENT_IDENTITY_SCHEME_LEGACY_UNVERIFIABLE", legacy$diagnostics$code)
  expect("DURABLE_CONTENT_IDENTITY_LEGACY_UNVERIFIABLE", legacy$diagnostics$code)
  stopifnot(!"DURABLE_CONTENT_IDENTITY_MISMATCH" %in% legacy$diagnostics$code)

  missing_baseline <- run_mutant("missing_matrix_baseline", function(path) {
    .deep_validation_db(path, "UPDATE prov_run_outputs SET content_sha256=NULL,content_identity_scheme=NULL WHERE primitive_kind='matrix';")
    .deep_validation_db(path, "UPDATE prov_run_entity_bindings SET content_hash=NULL,content_identity_scheme=NULL WHERE entity_kind='matrix';")
    .deep_validation_db(path, "UPDATE entity_lifecycle SET identity_hash=NULL,identity_scheme=NULL WHERE entity_kind='matrix';")
  })
  expect("DURABLE_CONTENT_IDENTITY_MISSING", missing_baseline)

  changed_matrix <- run_mutant("valid_matrix_value_tamper", function(path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite")); rel <- DBI::dbGetQuery(con, "SELECT path FROM matrices WHERE matrix_id='RNA_counts';")$path[1]; DBI::dbDisconnect(con)
    target <- file.path(path, rel); replacement <- paste0(target, ".replacement")
    mat <- as.matrix(BPCells::open_matrix_dir(target)); mat[1, 1] <- mat[1, 1] + 1
    BPCells::write_matrix_dir(Matrix::Matrix(mat, sparse = TRUE), replacement)
    unlink(target, recursive = TRUE, force = TRUE); stopifnot(file.rename(replacement, target))
  })
  expect("MATRIX_CONTENT_IDENTITY_MISMATCH", changed_matrix)

  changed_model <- run_mutant("valid_model_tamper", function(path) {
    saveRDS(list(engine = "fixture", coefficients = c(9, 8)), file.path(path, "models", "fixture.rds"))
  })
  expect("MODEL_CONTENT_IDENTITY_MISMATCH", changed_model)

  changed_artifact <- run_mutant("valid_artifact_tamper", function(path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite")); on.exit(DBI::dbDisconnect(con), add = TRUE)
    row <- DBI::dbGetQuery(con, "SELECT artifact_id,row_json FROM artifact_table_rows LIMIT 1;")
    value <- jsonlite::fromJSON(row$row_json[1], simplifyVector = FALSE); value$valid_tamper <- TRUE
    DBI::dbExecute(con, "UPDATE artifact_table_rows SET row_json=? WHERE artifact_id=? AND row_idx=1;", params = list(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"), row$artifact_id[1]))
  })
  expect("ARTIFACT_CONTENT_IDENTITY_MISMATCH", changed_artifact)

  wal_path <- file.path(root, "active_wal.bundle")
  .deep_validation_copy(base, wal_path)
  wal_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(wal_path, "db", "app.sqlite"))
  on.exit(try(DBI::dbDisconnect(wal_con), silent = TRUE), add = TRUE)
  DBI::dbExecute(wal_con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(wal_con, "PRAGMA wal_autocheckpoint=0;")
  DBI::dbExecute(wal_con, "CREATE TABLE request01a_wal_probe(value TEXT);")
  DBI::dbExecute(wal_con, "INSERT INTO request01a_wal_probe VALUES('active');")
  before <- .deep_validation_fingerprint(wal_path)
  wal_content <- wb_bundle_validation_report(wal_path, "content")
  after_content <- .deep_validation_fingerprint(wal_path)
  wal_recipient <- wb_bundle_validation_report(wal_path, "recipient")
  after_recipient <- .deep_validation_fingerprint(wal_path)
  stopifnot(
    !isTRUE(wal_content$ok), !isTRUE(wal_recipient$ok),
    "SQLITE_ACTIVE_WAL_SNAPSHOT_REQUIRED" %in% wal_content$diagnostics$code,
    "SQLITE_ACTIVE_WAL_SNAPSHOT_REQUIRED" %in% wal_recipient$diagnostics$code,
    identical(before, after_content), identical(before, after_recipient)
  )
  DBI::dbDisconnect(wal_con)
  wal_con <- NULL
  TRUE
}
