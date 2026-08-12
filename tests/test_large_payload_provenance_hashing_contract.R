.large_hash_repo <- function() normalizePath(getwd(), winslash = "/", mustWork = TRUE)

.large_hash_pending_paths <- function(root) {
  paths <- c(
    file.path(root, "provenance", ".pending"),
    file.path(root, ".pending"),
    file.path(root, ".staging")
  )
  paths[vapply(paths, dir.exists, logical(1)) &
          vapply(paths, function(path) length(list.files(path, all.files=TRUE, no..=TRUE, recursive=TRUE)) > 0L, logical(1))]
}

test_large_payload_native_sha256_contract <- function() {
  old_warn <- getOption("warn")
  on.exit(options(warn=old_warn),add=TRUE)
  options(warn=2)
  n <- 9L * 1024L * 1024L + 17L
  raw_payload <- rep(as.raw(0:250), length.out=n)
  text_payload <- strrep("A", n)
  before <- scworkbench:::.wb_validation_process_memory()$peak_rss_mb
  t0 <- proc.time()[["elapsed"]]
  raw_a <- scworkbench:::.wb_hash_text(raw_payload)
  raw_b <- scworkbench:::.wb_hash_text(raw_payload)
  text_a <- scworkbench:::.wb_hash_text(text_payload)
  text_b <- scworkbench:::.wb_hash_text(enc2utf8(text_payload))
  elapsed <- proc.time()[["elapsed"]] - t0
  raw_changed <- raw_payload
  raw_changed[[length(raw_changed)]] <- as.raw((as.integer(raw_changed[[length(raw_changed)]]) + 1L) %% 256L)
  text_changed <- paste0(substr(text_payload,1L,n-1L),"B")
  stopifnot(
    grepl("^[0-9a-f]{64}$",raw_a),grepl("^[0-9a-f]{64}$",text_a),
    identical(raw_a,raw_b),identical(text_a,text_b),
    !identical(raw_a,scworkbench:::.wb_hash_text(raw_changed)),
    !identical(text_a,scworkbench:::.wb_hash_text(text_changed)),
    elapsed < 15
  )
  after <- scworkbench:::.wb_validation_process_memory()$peak_rss_mb
  if (is.finite(before) && is.finite(after)) stopifnot(after - before < 768)

  payload_file <- tempfile("scwb_hash_payload_",fileext=".bin")
  writeBin(raw_payload,payload_file)
  on.exit(unlink(payload_file,force=TRUE),add=TRUE)
  rq <- function(x) encodeString(x,quote='"')
  expr <- paste0(
    "devtools::load_all(",rq(.large_hash_repo()),",quiet=TRUE);",
    "x<-readBin(",rq(payload_file),",what='raw',n=file.info(",rq(payload_file),")$size);",
    "cat(scworkbench:::.wb_hash_text(x))"
  )
  cross <- system2(file.path(R.home("bin"),"Rscript"),c("-e",shQuote(expr)),stdout=TRUE,stderr=TRUE)
  stopifnot(is.null(attr(cross,"status")),identical(as.character(cross[[length(cross)]]),raw_a))

  r_files <- list.files(file.path(.large_hash_repo(),"R"),pattern="[.]R$",full.names=TRUE)
  production <- unlist(lapply(r_files,readLines,warn=FALSE),use.names=FALSE)
  production <- production[!grepl("^[[:space:]]*#",production)]
  generic_calls <- grep("[.]wb_hash_text\\(",production,value=TRUE)
  stopifnot(length(generic_calls)==0L)
  legacy_calls <- grep("[.]wb_hash_text_legacy_v1\\(",production,value=TRUE)
  stopifnot(length(legacy_calls)==3L)
  new_bodies <- c(
    deparse(body(scworkbench:::.wb_hash_text)),
    deparse(body(scworkbench:::.wb_prov_run_hash)),
    deparse(body(scworkbench:::.wb_prov_contract_hash)),
    deparse(body(scworkbench:::.wb_prov_materialization_hash))
  )
  stopifnot(!any(grepl("for \\(",new_bodies)),!any(grepl("\\[\\[i\\]\\].*\\*.*i",new_bodies)))
  TRUE
}

.large_hash_state <- function(bundle) {
  list(
    matrices=nrow(wb_matrices(bundle,include_history=TRUE)),
    spaces=nrow(wb_spaces(bundle,include_history=TRUE)),
    models=if(scworkbench:::.wb_table_exists(bundle$con,"space_models")) DBI::dbGetQuery(bundle$con,"SELECT COUNT(*) n FROM space_models;")$n[[1]] else 0L,
    artifacts=nrow(wb_art_list(bundle,include_history=TRUE)),
    heads=nrow(wb_prov_list_heads(bundle)),
    commits=if(scworkbench:::.wb_table_exists(bundle$con,"prov_commits")) DBI::dbGetQuery(bundle$con,"SELECT COUNT(*) n FROM prov_commits;")$n[[1]] else 0L,
    outputs=if(scworkbench:::.wb_table_exists(bundle$con,"prov_run_outputs")) DBI::dbGetQuery(bundle$con,"SELECT COUNT(*) n FROM prov_run_outputs;")$n[[1]] else 0L,
    bindings=if(scworkbench:::.wb_table_exists(bundle$con,"prov_run_entity_bindings")) DBI::dbGetQuery(bundle$con,"SELECT COUNT(*) n FROM prov_run_entity_bindings;")$n[[1]] else 0L,
    materializations=if(scworkbench:::.wb_table_exists(bundle$con,"prov_materializations")) DBI::dbGetQuery(bundle$con,"SELECT COUNT(*) n FROM prov_materializations;")$n[[1]] else 0L
  )
}

test_large_materialization_promotion_rollback_contract <- function() {
  root <- tempfile("scwb_large_materialization_")
  b <- wb_init_bundle(root,overwrite=TRUE)
  old_digest_hook <- getOption("scworkbench.provenance_digest_test_hook")
  old_publish_hook <- getOption("scworkbench.promotion_workspace_publish_hook")
  old_warn <- getOption("warn")
  on.exit({
    options(scworkbench.provenance_digest_test_hook=old_digest_hook,
            scworkbench.promotion_workspace_publish_hook=old_publish_hook,warn=old_warn)
    if(!is.null(b)) try(wb_close_bundle(b),silent=TRUE)
    unlink(root,recursive=TRUE,force=TRUE)
  },add=TRUE)
  options(warn=2)
  payload <- strrep("large-materialization-payload-",350000L)
  prim <- wb_prim_obs_table(data.frame(metric="payload",value=payload,stringsAsFactors=FALSE),table_type="hvg_select_summary",entity_kind="analysis_summary")
  run <- wb_new_run("hvg_select",inputs=list(parents=character(),user_inputs=list()),params=list(n_features=2000L),outputs=list(fit_summary=prim))
  s <- wb_session_new(); s$runs <- stats::setNames(list(run),run$run_id); s$head_run_id <- run$run_id
  baseline <- .large_hash_state(b)

  options(scworkbench.provenance_digest_test_hook=function(domain,n_bytes) {
    if (identical(domain,"materialization-v2")) stop("forced large materialization digest failure",call.=FALSE)
  })
  failed_digest <- try(wb_session_promote_current(b,s,outputs="fit_summary"),silent=TRUE)
  stopifnot(inherits(failed_digest,"try-error"),grepl("forced large materialization digest failure",as.character(failed_digest),fixed=TRUE),identical(.large_hash_state(b),baseline),!length(.large_hash_pending_paths(root)))
  wb_close_bundle(b); b <- NULL
  stopifnot(!isTRUE(wb_bundle_writer_lock_info(root)$locked))
  b <- wb_open_bundle(root)

  options(scworkbench.provenance_digest_test_hook=NULL,
          scworkbench.promotion_workspace_publish_hook=function(workspace,final_rel) stop("forced publication boundary failure",call.=FALSE))
  failed_publish <- try(wb_session_promote_current(b,s,outputs="fit_summary"),silent=TRUE)
  stopifnot(inherits(failed_publish,"try-error"),grepl("forced publication boundary failure",as.character(failed_publish),fixed=TRUE),identical(.large_hash_state(b),baseline),!length(.large_hash_pending_paths(root)))
  wb_close_bundle(b); b <- NULL
  stopifnot(!isTRUE(wb_bundle_writer_lock_info(root)$locked))
  b <- wb_open_bundle(root)

  options(scworkbench.promotion_workspace_publish_hook=NULL)
  promoted <- wb_session_promote_current(b,s,outputs="fit_summary")
  stopifnot(all(promoted$promoted$status=="ok"))
  mats <- DBI::dbGetQuery(b$con,"SELECT output_hash,output_hash_scheme,content_sha256 FROM prov_materializations;")
  runs <- DBI::dbGetQuery(b$con,"SELECT run_hash,run_hash_scheme,contract_hash,contract_hash_scheme FROM prov_runs;")
  outs <- DBI::dbGetQuery(b$con,"SELECT output_hash,output_hash_scheme,structural_fingerprint,structural_fingerprint_scheme FROM prov_run_outputs;")
  schemes <- scworkbench:::.wb_identity_schemes()
  stopifnot(nrow(mats)==1L,nchar(mats$output_hash)==64L,mats$output_hash_scheme==schemes[["materialization"]],
            all(nchar(runs$run_hash)==64L),all(runs$run_hash_scheme==schemes[["run"]]),all(runs$contract_hash_scheme==schemes[["contract"]]),
            all(outs$output_hash_scheme==schemes[["structural"]]),all(outs$structural_fingerprint_scheme==schemes[["structural"]]))
  content <- wb_bundle_validation_report(root,"content")
  stopifnot(isTRUE(content$ok))
  TRUE
}

.large_hash_make_legacy_runs <- function(bundle) {
  schemes <- scworkbench:::.wb_identity_schemes()
  rows <- DBI::dbGetQuery(bundle$con,"SELECT rowid,* FROM prov_runs;")
  for(i in seq_len(nrow(rows))) {
    run_hash <- scworkbench:::.wb_prov_run_hash(rows$op_name[i],rows$params_json[i],rows$inputs_json[i],rows$symbolic_inputs_json[i],rows$execution_inputs_json[i],scheme=schemes[["legacy"]])
    contract_hash <- if(!is.na(rows$contract_json[i]) && nzchar(rows$contract_json[i])) scworkbench:::.wb_prov_contract_hash(rows$contract_json[i],scheme=schemes[["legacy"]]) else NA_character_
    DBI::dbExecute(bundle$con,"UPDATE prov_runs SET run_hash=?,contract_hash=?,run_hash_scheme=NULL,contract_hash_scheme=NULL WHERE rowid=?;",params=list(run_hash,contract_hash,rows$rowid[i]))
  }
  DBI::dbExecute(bundle$con,"DELETE FROM bundle_schema_migrations WHERE version=6;")
  invisible(TRUE)
}

test_mixed_legacy_new_provenance_identity_contract <- function() {
  if(!requireNamespace("BPCells",quietly=TRUE)) return(contract_test_skip("BPCells is not installed."))
  root <- tempfile("scwb_mixed_hash_"); clone_parent <- tempfile("scwb_mixed_hash_mutant_")
  b <- wb_init_bundle(root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(c(root,clone_parent),recursive=TRUE,force=TRUE)},add=TRUE)
  cells <- paste0("c",1:12); features <- paste0("g",1:8)
  wb_define_cells(b,cells)
  counts <- Matrix::Matrix(matrix(as.integer(seq_len(96L)%%11L),8L,dimnames=list(features,cells)),sparse=TRUE)
  wb_attach_matrix(b,"RNA_counts",counts,feature_type="gene",source="mixed_hash_fixture")
  .large_hash_make_legacy_runs(b)
  wb_close_bundle(b); b <- NULL

  b <- wb_open_bundle(root)
  migrated <- DBI::dbGetQuery(b$con,"SELECT run_hash,run_hash_scheme,contract_hash,contract_hash_scheme FROM prov_runs;")
  legacy <- unname(scworkbench:::.wb_identity_schemes()[["legacy"]])
  stopifnot(all(nchar(migrated$run_hash)==16L),all(migrated$run_hash_scheme==legacy),all(migrated$contract_hash_scheme[!is.na(migrated$contract_hash)]==legacy))
  session <- wb_session_new()
  hvg <- wb_session_run_op(session,b,"hvg_select",inputs=list(matrix="RNA_counts",n_features=4L,min_cells=1L,method="vst"))
  promoted <- wb_session_promote_current(b,hvg$session,outputs="selected_features",created_by="mixed-hash-contract")
  sid <- as.character(promoted$provenance_snapshot_id)[1]
  artifact_id <- as.character(promoted$promoted$artifact_id[promoted$promoted$output=="selected_features"])[1]
  all_runs <- DBI::dbGetQuery(b$con,"SELECT run_hash,run_hash_scheme,contract_hash,contract_hash_scheme FROM prov_runs;")
  schemes <- scworkbench:::.wb_identity_schemes()
  stopifnot(any(all_runs$run_hash_scheme==legacy),any(all_runs$run_hash_scheme==schemes[["run"]]),all(nchar(all_runs$run_hash[all_runs$run_hash_scheme==schemes[["run"]]])==64L))
  replay <- wb_prov_validate_replay(b,snapshot_id=sid,profile="strict",strict=TRUE)
  stopifnot(isTRUE(replay$summary$valid))
  cert <- wb_entity_certificate(b,"artifact",artifact_id)
  stopifnot(identical(as.character(cert$subject$id),artifact_id))
  stopifnot(nrow(wb_prov_bundle_dag(b)$nodes)>0L,nrow(wb_kg_provenance_graph(b)$nodes)>0L)
  wb_finalize_recipient_bundle(b); wb_close_bundle(b); b <- NULL
  deep <- wb_bundle_validation_report(root,"content")
  recipient <- wb_bundle_validation_report(root,"recipient")
  stopifnot(isTRUE(deep$ok),isTRUE(recipient$ok),identical(recipient$pre_validation_fingerprint,recipient$post_validation_fingerprint))
  b <- wb_open_bundle(root,read_only=TRUE,validate=TRUE)
  stopifnot(nrow(wb_prov_list_heads(b))>=2L,nrow(wb_prov_bundle_dag(b)$nodes)>0L,nrow(wb_kg_provenance_graph(b)$nodes)>0L)
  wb_close_bundle(b); b <- NULL

  dir.create(clone_parent)
  stopifnot(file.copy(root,clone_parent,recursive=TRUE))
  mutant <- file.path(clone_parent,basename(root)); db <- file.path(mutant,"db","app.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(),db); on.exit(try(DBI::dbDisconnect(con),silent=TRUE),add=TRUE)
  original <- DBI::dbGetQuery(con,"SELECT rowid,run_hash,run_hash_scheme FROM prov_runs WHERE run_hash_scheme<>? LIMIT 1;",params=list(legacy))
  DBI::dbExecute(con,"UPDATE prov_runs SET run_hash_scheme='unknown.identity.scheme',contract_hash_scheme='unknown.identity.scheme' WHERE rowid=?;",params=list(original$rowid[1]))
  DBI::dbExecute(con,"UPDATE prov_run_outputs SET output_hash_scheme='unknown.identity.scheme',structural_fingerprint_scheme='unknown.identity.scheme' WHERE snapshot_id=?;",params=list(sid))
  DBI::dbExecute(con,"UPDATE prov_materializations SET output_hash_scheme='unknown.identity.scheme' WHERE commit_id IN (SELECT commit_id FROM prov_heads WHERE snapshot_id=?);",params=list(sid))
  DBI::dbDisconnect(con); con <- NULL
  unknown <- wb_bundle_validation_report(mutant,"content")
  stopifnot(!isTRUE(unknown$ok),sum(unknown$diagnostics$code=="INTEGRITY_IDENTITY_SCHEME_UNSUPPORTED")>=5L)
  con <- DBI::dbConnect(RSQLite::SQLite(),db)
  DBI::dbExecute(con,"UPDATE prov_runs SET run_hash=?,contract_hash=?,run_hash_scheme=?,contract_hash_scheme=? WHERE rowid=?;",params=list(strrep("a",16L),strrep("b",16L),schemes[["run"]],schemes[["contract"]],original$rowid[1]))
  DBI::dbExecute(con,"UPDATE prov_run_outputs SET output_hash=?,structural_fingerprint=?,output_hash_scheme=?,structural_fingerprint_scheme=? WHERE snapshot_id=?;",params=list(strrep("c",16L),strrep("d",16L),schemes[["structural"]],schemes[["structural"]],sid))
  DBI::dbExecute(con,"UPDATE prov_materializations SET output_hash=?,output_hash_scheme=? WHERE commit_id IN (SELECT commit_id FROM prov_heads WHERE snapshot_id=?);",params=list(strrep("e",16L),schemes[["materialization"]],sid))
  DBI::dbDisconnect(con); con <- NULL
  contradiction <- wb_bundle_validation_report(mutant,"content")
  stopifnot(!isTRUE(contradiction$ok),sum(contradiction$diagnostics$code=="INTEGRITY_DIGEST_SCHEME_CONTRADICTION")>=5L)
  TRUE
}
