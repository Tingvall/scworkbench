test_targeted_reproduction_plan_contract <- function() {
  contract_test_activate_representation_pack()
  if (!requireNamespace("uwot", quietly = TRUE)) return(contract_test_skip("uwot is not installed."))
  root <- tempfile("scwb_target_plan_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", seq_len(12)); coords <- matrix(seq_len(48)/10, nrow=12, dimnames=list(cells,paste0("d",1:4)))
  wb_define_cells(b, cells); wb_add_space(b, "pca_source", coords, source="test", overwrite=TRUE)
  source_plan <- wb_target_reproduction_plan(b, "space:pca_source")
  stopifnot(inherits(source_plan, "wb_target_reproduction_plan"), identical(source_plan$status, "source_state"), !source_plan$reproducible)
  res <- wb_session_run_op(wb_session_new(), b, "umap_fit", inputs=list(space="pca_source", cell_set="all", min_cells=1L, dims=1:4, space_id_out="umap_target", n_neighbors=3L, min_dist=.1, metric="euclidean", nn_method="annoy", seed=1L))
  promoted <- wb_session_promote_current(b, res$session, outputs="model")
  plan <- wb_target_reproduction_plan(b, "space:umap_target")
  policy <- setNames(plan$terminal_outputs$replay_equivalence_policy, plan$terminal_outputs$output_name)
  stopifnot(identical(plan$status,"ok"), identical(plan$run_order, res$run$run_id), all(c("model","space_2d") %in% plan$terminal_outputs$output_name), all(plan$terminal_outputs$verification_level == "content"), identical(policy[["model"]], "loadable_reference"), identical(policy[["space_2d"]], "cell_aligned_embedding"))
  stopifnot(identical(plan$run_order, wb_target_reproduction_plan(b, paste0("run:", res$run$run_id))$run_order))
  model_id <- paste("uwot", "umap_target", "pca_source", sep="|")
  stopifnot(identical(wb_target_reproduction_plan(b, paste0("model:",model_id))$status,"ok"))
  script <- wb_target_emit_r_script(plan)
  emitted_symbols <- unique(all.names(parse(text = script), functions = TRUE))
  wb_symbols <- emitted_symbols[grepl("^wb_", emitted_symbols)]
  stopifnot(
    length(script) == 1L,
    grepl("wb_target_execute_plan", script, fixed = TRUE),
    !grepl(":::", script, fixed = TRUE),
    !grepl("devtools", script, fixed = TRUE),
    all(wb_symbols %in% getNamespaceExports("scworkbench"))
  )
  getter_catalog <- wb_getter_catalog_semantic()
  mutation_catalog <- wb_mutation_catalog_semantic()
  stopifnot(
    !any(vapply(
      getter_catalog$getters,
      function(entry) identical(entry$function_name, "wb_target_execute_plan"),
      logical(1)
    )),
    any(vapply(
      mutation_catalog$records,
      function(entry) identical(entry$function_name, "wb_target_execute_plan"),
      logical(1)
    ))
  )
  stopifnot(nrow(promoted$promoted) >= 1L,
            !"wb_target_reproduction_branch_template" %in% getNamespaceExports("scworkbench"))
  TRUE
}

# Executable cross-snapshot closure: durable string/entity inputs must pull
# their producing runs into the plan, then replay into a source-only clone.
test_targeted_reproduction_execute_contract <- function() {
  contract_test_activate_rna_pack()
  contract_test_activate_representation_pack()
  required <- c("BPCells", "irlba", "uwot")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }
  root <- tempfile("scwb_target_execute_")
  cleanup <- character(0)
  b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE); if (length(cleanup)) unlink(cleanup,recursive=TRUE,force=TRUE); unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  cells <- paste0("cell_",letters[1:12]); wb_define_cells(b,cells)
  mat <- Matrix::Matrix(matrix(rep(c(10,1,0,8,2,6),each=12),nrow=6,dimnames=list(paste0("g",1:6),cells)),sparse=TRUE)
  wb_attach_matrix(b,"RNA_counts",mat,feature_type="gene")
  copy_bundle <- function(source, label) {
    parent <- tempfile(paste0("scwb_", label, "_")); dir.create(parent)
    stopifnot(isTRUE(file.copy(source, parent, recursive=TRUE)))
    cleanup <<- c(cleanup, parent)
    file.path(parent, basename(source))
  }
  installed_library <- tempfile("scwb_target_installed_library_")
  dir.create(installed_library)
  cleanup <- c(cleanup, installed_library)
  install_output <- system2(
    "R", c("CMD", "INSTALL", "-l", installed_library, normalizePath(".")),
    stdout = TRUE, stderr = TRUE
  )
  install_status <- as.integer(attr(install_output, "status") %||% 0L)
  if (install_status != 0L) stop(paste(install_output, collapse = "\n"))
  rna_library <- normalizePath(.contract_test_rna_state$library,
    winslash = "/", mustWork = TRUE)
  representation_library <- normalizePath(
    .contract_test_representation_state$library,
    winslash = "/", mustWork = TRUE)
  run_emitted <- function(script, prelude = character()) {
    path <- tempfile(fileext=".R"); wrapper <- tempfile(fileext=".R")
    writeLines(script,path)
    writeLines(c(
      paste0(".libPaths(c('", normalizePath(installed_library, winslash = "/"),
        "', '", rna_library, "', '", representation_library,
        "', .libPaths()))"),
      "library(scworkbench)",
      paste0("wb_operation_pack_load('scwbRNA', lib.loc='", rna_library,
        "')"),
      paste0("wb_operation_pack_load('scwbRepresentation', lib.loc='",
        representation_library, "')"),
      prelude, paste0("source('",path,"')")
    ),wrapper)
    out <- suppressWarnings(system2(
      file.path(R.home("bin"),"Rscript"), c("--vanilla", wrapper),
      stdout=TRUE, stderr=TRUE,
      env = paste0("R_LIBS=", paste(c(installed_library, rna_library,
        representation_library),
        collapse = .Platform$path.sep))
    ))
    list(status=as.integer(attr(out,"status") %||% 0L), output=out)
  }
  expect_failure <- function(result, pattern) {
    text <- paste(result$output, collapse = "\n")
    if (result$status == 0L || !grepl(pattern, text, fixed = TRUE)) {
      stop("Expected failure containing '", pattern, "':\n", text, call. = FALSE)
    }
    invisible(result)
  }
  # Copy only a checkpointed immutable/source boundary; copying SQLite while
  # its writer is open can omit WAL frames and is not a valid execution clone.
  wb_close_bundle(b)
  clone <- copy_bundle(root, "target_clone")
  b <- wb_open_bundle(root)
  n <- wb_session_run_op(wb_session_new(),b,"matrix_log_normalize",inputs=list(matrix="RNA_counts",cell_set="all",min_cells=1L,output_matrix_id="RNA_log_norm",overwrite=FALSE))
  wb_session_promote_current(b,n$session,outputs="summary")
  wb_close_bundle(b); b <- wb_open_bundle(root)
  h <- wb_session_run_op(wb_session_new(),b,"hvg_select",inputs=list(matrix="RNA_log_norm",cell_set="all",min_cells=1L,n_features=4L,method="vst",chunk_size=2L))
  ph <- wb_session_promote_current(b,h$session,outputs="selected_features"); aid <- as.character(ph$promoted$artifact_id[ph$promoted$output=="selected_features"][1])
  wb_close_bundle(b); b <- wb_open_bundle(root)
  p <- wb_session_run_op(wb_session_new(),b,"pca_fit",inputs=list(matrix="RNA_log_norm",features=wb_ref_artifact(aid,"selected_features"),cell_set="all",min_cells=1L,n_components=2L,center=TRUE,scale=TRUE,backend="irlba",seed=1L,space_id_out="rna_pca",overwrite=FALSE,max_dense_gb=1))
  pp <- wb_session_promote_current(b,p$session,outputs=c("loadings","variance","fit_summary"))
  wb_close_bundle(b); b <- wb_open_bundle(root)
  u <- wb_session_run_op(wb_session_new(),b,"umap_fit",inputs=list(space="rna_pca",cell_set="all",min_cells=1L,dims=1:2,space_id_out="rna_umap",n_neighbors=3L,min_dist=.1,metric="euclidean",nn_method="annoy",seed=1L))
  wb_session_promote_current(b,u$session,outputs="model")
  plan <- wb_target_reproduction_plan(b,"space:rna_umap")
  run_ids <- c(n$run$run_id,h$run$run_id,p$run$run_id,u$run$run_id)
  snapshots <- DBI::dbGetQuery(b$con,paste0("SELECT DISTINCT run_id, snapshot_id FROM prov_runs WHERE run_id IN (",paste(rep("?",4),collapse=","),")"),params=as.list(run_ids))
  stopifnot(nrow(snapshots)==4L,length(unique(snapshots$snapshot_id))==4L,identical(plan$run_order,run_ids))
  mid <- paste("uwot","rna_umap","rna_pca",sep="|")
  required_nodes <- c("matrix:RNA_counts","matrix:RNA_log_norm",paste0("artifact:",aid),"space:rna_pca","space:rna_umap",paste0("model_ref:",mid),paste0("run:",run_ids))
  stopifnot(identical(plan$status,"ok"),all(required_nodes %in% plan$subgraph$nodes$id),nrow(plan$excluded_siblings)==0L)
  has_edge <- function(from,to,type) any(plan$subgraph$edges$from==from & plan$subgraph$edges$to==to & plan$subgraph$edges$edge_type==type)
  stopifnot(
    has_edge("matrix:RNA_counts",paste0("run:",n$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",n$run$run_id),"matrix:RNA_log_norm","MATERIALIZES"),
    has_edge("matrix:RNA_log_norm",paste0("run:",h$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",h$run$run_id),paste0("artifact:",aid),"PRODUCES"),
    has_edge(paste0("artifact:",aid),paste0("run:",p$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",p$run$run_id),"space:rna_pca","MATERIALIZES"),
    has_edge("space:rna_pca",paste0("run:",u$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",u$run$run_id),"space:rna_umap","MATERIALIZES"),
    has_edge(paste0("run:",u$run$run_id),paste0("model_ref:",mid),"MATERIALIZES")
  )
  artifact_plan <- wb_target_reproduction_plan(b,paste0("artifact:",aid))
  matrix_plan <- wb_target_reproduction_plan(b,"matrix:RNA_log_norm")
  pca_plan <- wb_target_reproduction_plan(b,"space:rna_pca")
  model_plan <- wb_target_reproduction_plan(b,paste0("model:",mid))
  run_plan <- wb_target_reproduction_plan(b,paste0("run:",u$run$run_id))
  target_plans <- list(artifact=artifact_plan,matrix=matrix_plan,space=pca_plan,model=model_plan,run=run_plan)
  target_status <- vapply(target_plans,function(x) as.character(x$status),character(1))
  if (!all(target_status=="ok")) stop(paste(names(target_status),target_status,collapse="; "))
  stopifnot(identical(model_plan$run_order,run_ids),identical(run_plan$run_order,run_ids))
  policy <- setNames(plan$terminal_outputs$replay_equivalence_policy,plan$terminal_outputs$output_name)
  stopifnot(identical(policy[["space_2d"]],"cell_aligned_embedding"),identical(policy[["model"]],"loadable_reference"))
  source_umap <- wb_space(b,"rna_umap")
  emitted <- wb_target_emit_r_script(plan, clone)
  emitted_symbols <- unique(all.names(parse(text = emitted), functions = TRUE))
  emitted_wb_symbols <- emitted_symbols[grepl("^wb_", emitted_symbols)]
  stopifnot(
    !grepl(":::", emitted, fixed = TRUE),
    !grepl("devtools", emitted, fixed = TRUE),
    all(emitted_wb_symbols %in% getNamespaceExports("scworkbench")),
    identical(emitted_wb_symbols, "wb_target_execute_plan"),
    length(gregexpr(normalizePath(root, winslash = "/"), emitted, fixed = TRUE)[[1]]) == 1L
  )

  # Every preflight rejection executes the real emitted script and must fail
  # before any analytical replay begins.
  source_reject <- run_emitted(wb_target_emit_r_script(plan,root))
  nonexistent <- tempfile("scwb_target_missing_destination_")
  nonexistent_reject <- run_emitted(wb_target_emit_r_script(plan,nonexistent))
  missing_boundary <- tempfile("scwb_target_missing_boundary_"); cleanup <- c(cleanup,missing_boundary)
  mb <- wb_init_bundle(missing_boundary,overwrite=TRUE); wb_define_cells(mb,cells); wb_close_bundle(mb)
  boundary_reject <- run_emitted(wb_target_emit_r_script(plan,missing_boundary))
  wb_close_bundle(b); collision <- copy_bundle(root,"target_collision"); b <- wb_open_bundle(root)
  collision_reject <- run_emitted(wb_target_emit_r_script(plan,collision))
  expect_failure(source_reject, "Refusing to mutate")
  expect_failure(nonexistent_reject, "existing writable")
  expect_failure(boundary_reject, "Missing immutable boundary")
  expect_failure(collision_reject, "Durable output collision")

  read_only_clone <- copy_bundle(clone, "target_read_only_recipient")
  read_only_bundle <- wb_open_bundle(read_only_clone)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(read_only_bundle)$ready))
  wb_close_bundle(read_only_bundle)
  read_only_manifest <- jsonlite::read_json(
    file.path(read_only_clone, "manifest.json"), simplifyVector = TRUE
  )
  read_only_db <- file.path(
    read_only_clone, as.character(read_only_manifest$storage$sqlite$path)
  )
  Sys.chmod(read_only_db, mode = "0444")
  Sys.chmod(read_only_clone, mode = "0555")
  read_only_reject <- run_emitted(wb_target_emit_r_script(plan, read_only_clone))
  expect_failure(read_only_reject, "read-only recipient bundle")

  tampered_clone <- copy_bundle(clone, "target_tampered_output")
  tamper_hook <- paste(
    "options(scworkbench.target_reproduction_test_hook = function(event, ...) {",
    "args <- list(...);",
    "if (identical(event, 'before_terminal_verification')) {",
    "stage <- wb_session_view(args$session);",
    "unlink(file.path(stage$dir, 'models', 'umap', 'rna_umap.uwot'), force = TRUE);",
    "};",
    "args$target_result",
    "})"
  )
  tampered_reject <- run_emitted(
    wb_target_emit_r_script(plan, tampered_clone), prelude = tamper_hook
  )
  expect_failure(tampered_reject, "Missing model reference payload")
  tampered_bundle <- wb_open_bundle(tampered_clone)
  stopifnot(
    isTRUE(wb_validate_bundle(tampered_clone)),
    !"RNA_log_norm" %in% wb_matrices(tampered_bundle, include_history = TRUE)$matrix_id,
    !any(c("rna_pca", "rna_umap") %in%
           wb_spaces(tampered_bundle, include_history = TRUE)$space_id),
    nrow(wb_art_list(tampered_bundle, include_history = TRUE)) == 0L,
    !nrow(DBI::dbGetQuery(tampered_bundle$con, "
      SELECT r.run_id FROM prov_runs AS r
       WHERE NOT EXISTS (
         SELECT 1 FROM prov_heads AS h
          WHERE h.snapshot_id=r.snapshot_id AND h.name_prefix='ingestion'
       );
    "))
  )
  wb_close_bundle(tampered_bundle)

  assert_source_only_after_atomic_failure <- function(path) {
    failed_bundle <- wb_open_bundle(path)
    on.exit(wb_close_bundle(failed_bundle), add = TRUE)
    analytical_runs <- DBI::dbGetQuery(failed_bundle$con, "
      SELECT r.run_id FROM prov_runs AS r
       WHERE NOT EXISTS (
         SELECT 1 FROM prov_heads AS h
          WHERE h.snapshot_id=r.snapshot_id AND h.name_prefix='ingestion'
       );
    ")
    analytical_heads <- DBI::dbGetQuery(failed_bundle$con, "
      SELECT snapshot_id FROM prov_heads WHERE name_prefix <> 'ingestion';
    ")
    analytical_bindings <- DBI::dbGetQuery(failed_bundle$con, "
      SELECT b.run_id FROM prov_run_entity_bindings AS b
       WHERE b.snapshot_id NOT IN (
         SELECT snapshot_id FROM prov_heads WHERE name_prefix='ingestion'
       );
    ")
    pending_commits <- DBI::dbGetQuery(
      failed_bundle$con, "SELECT commit_id FROM prov_commits WHERE state <> 'complete';"
    )
    files <- list.files(path, recursive = TRUE, all.files = TRUE, no.. = TRUE)
    stopifnot(
      isTRUE(wb_validate_bundle(path)),
      !"RNA_log_norm" %in%
        wb_matrices(failed_bundle, include_history = TRUE)$matrix_id,
      !any(c("rna_pca", "rna_umap") %in%
             wb_spaces(failed_bundle, include_history = TRUE)$space_id),
      nrow(wb_art_list(failed_bundle, include_history = TRUE)) == 0L,
      !nrow(analytical_runs), !nrow(analytical_heads),
      !nrow(analytical_bindings), !nrow(pending_commits),
      DBI::dbGetQuery(
        failed_bundle$con, "SELECT COUNT(*) AS n FROM prov_materializations;"
      )$n[1] == 0L,
      DBI::dbGetQuery(
        failed_bundle$con,
        "SELECT COUNT(*) AS n FROM prov_replay_equivalence_results;"
      )$n[1] == 0L,
      !any(grepl("rna_(pca|umap)|RNA_log_norm", files, perl = TRUE))
    )
    invisible(TRUE)
  }
  assert_atomic_failure_and_retry <- function(label, prelude) {
    path <- copy_bundle(clone, paste0("target_atomic_", label))
    script <- wb_target_emit_r_script(plan, path)
    failed <- run_emitted(script, prelude = prelude)
    expect_failure(failed, paste0("forced target atomicity fault: ", label))
    assert_source_only_after_atomic_failure(path)
    retried <- run_emitted(script)
    if (retried$status != 0L) stop(paste(retried$output, collapse = "\n"))
    retried_bundle <- wb_open_bundle(path)
    on.exit(wb_close_bundle(retried_bundle), add = TRUE)
    retried_receipts <- wb_prov_replay_equivalence_results(retried_bundle)
    stopifnot(
      isTRUE(wb_validate_bundle(path)),
      "RNA_log_norm" %in% wb_matrices(retried_bundle)$matrix_id,
      all(c("rna_pca", "rna_umap") %in% wb_spaces(retried_bundle)$space_id),
      nrow(retried_receipts) == nrow(plan$terminal_outputs),
      length(unique(retried_receipts$replay_snapshot_id)) == 1L,
      all(retried_receipts$verification_status == "verified"),
      all(nzchar(retried_receipts$replay_artifact_id))
    )
    invisible(TRUE)
  }
  atomic_fault <- function(label, event, condition = "TRUE") paste(
    "options(scworkbench.target_reproduction_atomicity_test_hook = function(event, ...) {",
    "args <- list(...);",
    paste0(
      "if (identical(event, '", event, "') && (", condition,
      ")) stop('forced target atomicity fault: ", label, "', call. = FALSE)"
    ),
    "})"
  )
  assert_atomic_failure_and_retry(
    "before_first_receipt_insertion",
    atomic_fault(
      "before_first_receipt_insertion", "before_first_receipt_insertion"
    )
  )
  assert_atomic_failure_and_retry(
    "between_terminal_receipt_insertions",
    atomic_fault(
      "between_terminal_receipt_insertions",
      "between_terminal_receipt_insertions"
    )
  )
  assert_atomic_failure_and_retry(
    "after_receipt_insertion_before_sqlite_commit",
    atomic_fault(
      "after_receipt_insertion_before_sqlite_commit",
      "after_receipt_insertions_before_sqlite_commit"
    )
  )
  assert_atomic_failure_and_retry(
    "during_payload_publication",
    atomic_fault(
      "during_payload_publication", "during_payload_publication",
      "identical(as.integer(args$publication_index), 2L)"
    )
  )

  success <- run_emitted(wb_target_emit_r_script(plan,clone))
  if (success$status!=0L) stop(paste(success$output,collapse="\n"))
  cb <- wb_open_bundle(clone); on.exit(try(wb_close_bundle(cb),silent=TRUE),add=TRUE)
  eq <- wb_prov_replay_equivalence_results(cb)
  eq_policy <- setNames(eq$replay_equivalence_policy,eq$original_output_name)
  replayed_umap <- wb_space(cb,"rna_umap")
  replayed_umap_matrix <- as.matrix(replayed_umap[, c("x", "y"), drop = FALSE])
  rownames(replayed_umap_matrix) <- replayed_umap$cell_id
  source_umap_matrix <- as.matrix(source_umap[, c("x", "y"), drop = FALSE])
  rownames(source_umap_matrix) <- source_umap$cell_id
  replay_snapshot_id <- unique(as.character(eq$replay_snapshot_id))
  replay_runs <- DBI::dbGetQuery(
    cb$con,
    "SELECT run_id, op_name FROM prov_runs WHERE snapshot_id=? ORDER BY rowid;",
    params = list(replay_snapshot_id)
  )
  replay_edges <- DBI::dbGetQuery(
    cb$con,
    "SELECT parent_run_id, child_run_id, edge_type FROM prov_run_edges WHERE snapshot_id=? ORDER BY rowid;",
    params = list(replay_snapshot_id)
  )
  payload_rows <- DBI::dbGetQuery(
    cb$con,
    "SELECT p.space_id, s.storage, p.path
       FROM space_payloads AS p JOIN spaces AS s USING(space_id)
      WHERE p.space_id IN ('rna_pca','rna_umap') ORDER BY p.space_id;"
  )
  stopifnot(isTRUE(wb_validate_bundle(clone)),"rna_umap" %in% wb_spaces(cb)$space_id,
            identical(sort(rownames(replayed_umap_matrix)),sort(rownames(source_umap_matrix))),
            identical(dim(replayed_umap_matrix),dim(source_umap_matrix)),
            all(is.finite(replayed_umap_matrix)),
            all(apply(replayed_umap_matrix,2L,function(x) diff(range(x)) > 0)),nrow(eq)==2L,
            all(eq$equivalence_verified==1L),
            identical(eq_policy[["space_2d"]],"cell_aligned_embedding"),
            identical(eq_policy[["model"]],"loadable_reference"),
            identical(eq$expected_reference[eq$original_output_name=="space_2d"],
                      eq$replayed_reference[eq$original_output_name=="space_2d"]),
            all(grepl("^[0-9a-f]{64}$",eq$original_content_sha256)),
            all(grepl("^[0-9a-f]{64}$",eq$replayed_content_sha256)),
            !is.null(wb_load_space_model(cb,"rna_umap")),
            identical(as.character(replay_runs$op_name),
                      c("matrix_log_normalize", "scwbrna::hvg_select", "pca_fit", "umap_fit")),
            nrow(replay_edges) >= 3L,
            all(c("depends_on_run", "input_run_ref") %in% replay_edges$edge_type),
            identical(as.character(payload_rows$space_id), c("rna_pca", "rna_umap")),
            all(payload_rows$storage == "hdf5:dense-space:v1"),
            all(file.exists(file.path(clone, payload_rows$path))))
  model_art <- eq$replay_artifact_id[eq$original_output_name=="model"]
  model_cert <- wb_entity_certificate(cb,"artifact",model_art)
  stopifnot(identical(as.character(model_cert$identity$verification_status),"content_verified"))

  # A second producer for the same durable entity is rejected structurally and
  # cannot be emitted. This deliberately models a malformed/legacy bundle.
  wb_close_bundle(b); b <- NULL
  amb <- copy_bundle(root,"target_ambiguous"); ab <- wb_open_bundle(amb); on.exit(try(wb_close_bundle(ab),silent=TRUE),add=TRUE)
  sid <- as.character(plan$terminal_outputs$snapshot_id[plan$terminal_outputs$output_name=="space_2d"])[1]
  dup_run <- paste0(u$run$run_id,"_duplicate")
  DBI::dbExecute(ab$con,"INSERT INTO prov_runs(snapshot_id,run_id,op_name,created_at,notes,params_json,inputs_json,symbolic_inputs_json,execution_inputs_json,run_hash,op_version,runtime_fingerprint_json,contract_json,contract_hash,run_hash_scheme,contract_hash_scheme) SELECT snapshot_id, ?, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json, execution_inputs_json, run_hash, op_version, runtime_fingerprint_json, contract_json, contract_hash, run_hash_scheme, contract_hash_scheme FROM prov_runs WHERE snapshot_id=? AND run_id=?",params=list(dup_run,sid,u$run$run_id))
  DBI::dbExecute(ab$con,"INSERT INTO prov_run_outputs(snapshot_id,run_id,output_name,primitive_kind,output_hash,artifact_id,materialization_class,materialization_path,structural_fingerprint,content_sha256,verification_level,verification_status,replay_equivalence_policy,replay_equivalence_reference,replay_equivalence_status,content_identity_scheme,output_hash_scheme,structural_fingerprint_scheme) SELECT snapshot_id, ?, output_name, primitive_kind, output_hash, artifact_id, materialization_class, materialization_path, structural_fingerprint, content_sha256, verification_level, verification_status, replay_equivalence_policy, replay_equivalence_reference, replay_equivalence_status, content_identity_scheme, output_hash_scheme, structural_fingerprint_scheme FROM prov_run_outputs WHERE snapshot_id=? AND run_id=? AND output_name='space_2d'",params=list(dup_run,sid,u$run$run_id))
  DBI::dbExecute(ab$con,"INSERT INTO prov_run_entity_bindings(snapshot_id,commit_id,run_id,direction,binding_name,entity_kind,entity_id,relationship_type,path,content_hash,source,content_identity_scheme) SELECT snapshot_id, commit_id, ?, direction, binding_name, entity_kind, entity_id, relationship_type, path, content_hash, source, content_identity_scheme FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? AND direction='output' AND entity_kind='space'",params=list(dup_run,sid,u$run$run_id))
  ambiguous <- wb_target_reproduction_plan(ab,"space:rna_umap")
  stopifnot(identical(ambiguous$status,"ambiguous"),!isTRUE(ambiguous$reproducible),nrow(ambiguous$candidates)>=2L,inherits(try(wb_target_emit_r_script(ambiguous,clone),silent=TRUE),"try-error"))
  TRUE
}
