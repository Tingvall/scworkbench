test_engine_space_model_metadata_snapshot_contract <- function() {
  root <- tempfile("space_metadata_"); b <- wb_init_bundle(root)
  on.exit({wb_close_bundle(b); unlink(root,recursive=TRUE)},add=TRUE)
  cells <- c("c3","c1","c2"); wb_define_cells(b,cells)
  values <- matrix(seq_len(9L),3L,dimnames=list(cells,c("z","a","q")))
  wb_add_space(b,"source",values,source="contract")
  source <- wb_prim_space("source")
  hydrated <- source; hydrated$values <- .wb_as_coord_matrix(wb_space(b,"source"))
  hydrated$cell_id <- rownames(hydrated$values)
  hydrated$dimensions <- as.integer(dim(hydrated$values))
  dimensions <- .wb_operation_pack_v3_selected_dimensions(hydrated,list(dims=c(3L,1L)),"dims")
  old_observation <- .wb_prov_payload_identity(b,hydrated)
  old_content <- list(scheme=old_observation$content_identity_scheme,
    sha256=old_observation$content_sha256)
  # Snapshot preparation must need no coordinate getter or extrema scan.
  trace("wb_space",where=asNamespace("scworkbench"),tracer=quote(stop("unexpected full hydration")),print=FALSE)
  on.exit(untrace("wb_space",where=asNamespace("scworkbench")),add=TRUE)
  parent <- .wb_operation_pack_v3_dfa_parent_snapshot(b,source,dimensions)
  stopifnot(identical(parent$full_content_identity,old_content),
    identical(parent$selected_dimension_ids,as.list(c("q","z"))),
    identical(parent$full_cell_count,3L),
    identical(.wb_operation_pack_v3_dfa_parent_assert_current(b,parent),cells))
  plan <- .wb_space_payload_reader(b,"source")
  available <- plan$block_elements()
  release <- plan$hold_memory(65536)
  stopifnot(plan$block_elements()<available)
  release();release()
  stopifnot(identical(plan$block_elements(),available),
    inherits(try(plan$hold_memory(Inf),silent=TRUE),"try-error"))
  plan$close()
  # A byte mutation remains independently rejected before metadata reuse.
  registry <- .wb_space_payload_registry_row(b,"source")
  path <- .wb_space_payload_path(b,registry)
  con <- file(path,"ab"); writeBin(as.raw(1L),con); close(con)
  stopifnot(inherits(try(.wb_operation_pack_v3_dfa_parent_assert_current(b,parent),silent=TRUE),"try-error"))
  TRUE
}

test_engine_space_summary_wide_tiling_contract <- function() {
  root <- tempfile("space_summary_"); b <- wb_init_bundle(root)
  on.exit({wb_close_bundle(b); unlink(root,recursive=TRUE)},add=TRUE)
  cells <- c("c1","c2","c3"); wb_define_cells(b,cells)
  values <- matrix(seq_len(3L*4097L),3L,dimnames=list(cells,paste0("d",seq_len(4097L))))
  wb_add_space(b,"source",values,source="contract")
  observations <- new.env(parent=emptyenv()); observations$widths <- integer()
  old <- options(scworkbench.max_dense_materialize_mb=8.5,
    scworkbench.space_summary_test_observations=observations)
  on.exit(options(old),add=TRUE)
  trace("h5read",where=asNamespace("rhdf5"),print=FALSE,tracer=quote({
    if (identical(name,"coordinates") && !is.null(index)) {
      observations <- getOption("scworkbench.space_summary_test_observations")
      observations$widths <- c(observations$widths,length(index[[2L]]))
    }
  }))
  on.exit(untrace("h5read",where=asNamespace("rhdf5")),add=TRUE)
  summary <- .wb_space_payload_summary(b,"source",verify_hash=TRUE)
  stopifnot(summary$finite,summary$nondegenerate,summary$complete,
    identical(summary$cells,cells),length(observations$widths)>1L,
    max(observations$widths)<ncol(values))
  path <- .wb_space_payload_path(b,summary$registry)
  .wb_space_payload_validate_file(path,summary$registry,validate_values=TRUE)
  stopifnot(max(observations$widths)<ncol(values))
  rhdf5::h5write(NA_real_,path,"coordinates",index=list(1L,4097L))
  changed <- .wb_space_payload_summary(b,"source",verify_hash=FALSE)
  stopifnot(!changed$finite,is.na(changed$nondegenerate))
  error <- tryCatch(.wb_space_payload_validate_file(path,summary$registry,
    validate_values=TRUE),error=identity)
  stopifnot(inherits(error,"error"),grepl("SPACE_PAYLOAD_VALUES_INVALID",conditionMessage(error)))
  TRUE
}

test_engine_space_legacy_template_extent_guard_contract <- function() {
  path <- tempfile("space_template_")
  on.exit(unlink(path),add=TRUE)
  value <- list(values=matrix(0,100L,100L),meta=list(label="retained"))
  saveRDS(value,path,compress=TRUE)
  stopifnot(file.info(path)$size < 10000)
  saved <- options(scworkbench.max_dense_materialize_mb=.1)
  on.exit(options(saved),add=TRUE)
  stopifnot(inherits(try(.wb_operation_pack_v3_admit_legacy_template(path,list()),silent=TRUE),"try-error"))
  options(scworkbench.max_dense_materialize_mb=1)
  stopifnot(.wb_operation_pack_v3_admit_legacy_template(path,list()) > file.info(path)$size)
  saveRDS(value,path,compress=FALSE)
  stopifnot(identical(as.numeric(.wb_operation_pack_v3_admit_legacy_template(path,list())),
    as.numeric(file.info(path)$size)))
  TRUE
}

test_engine_space_model_callback_diagnostic_isolation_contract <- function() {
  stage <- tempfile("space_model_callback_"); dir.create(file.path(stage,"model"),recursive=TRUE)
  on.exit(unlink(stage,recursive=TRUE),add=TRUE)
  con <- file(file.path(stage,"model","model.bin"),"wb")
  writeBin(charToRaw("model"),con);close(con)
  tree <- .wb_operation_pack_v3_model_tree_manifest(file.path(stage,"model"),
    "synthetic","synthetic","model.bin")
  grant <- list(name="model_reader",input_name="model",relative_root="model",
    engine="synthetic",model_type="synthetic",tree_manifest=tree,
    payload_manifest_identity=.wb_operation_pack_v3_model_payload_identity(tree),
    reader="read_self_linked_contained_model_payload")
  fitted <- matrix(1:6,3L,dimnames=list(c("c3","c1","c2"),c("a","b")))
  attr(fitted,"scworkbench_payload_read") <- list(path="private/source.h5")
  request <- list(outputs=list(),self_linked_model_payload_grants=list(grant))
  attr(request,"operation_pack_v3_self_linked_model_read_values") <-
    list(model_reader=list(fitted_space=fitted))
  state <- new.env(parent=emptyenv());state$used<-FALSE;state$writes<-list()
  base <- list(state=state,readers=list(),writers=list())
  adapter <- .wb_operation_pack_v3_model_adapters(base,request,list(outputs=list()),stage)
  delivered <- adapter$readers$model_reader()$fitted_source_space
  stopifnot(is.null(attr(delivered,"scworkbench_payload_read")),
    identical(dim(delivered),dim(fitted)),identical(dimnames(delivered),dimnames(fitted)),
    identical(as.vector(delivered),as.vector(fitted)),
    !is.null(attr(fitted,"scworkbench_payload_read")))
  TRUE
}

test_engine_space_retained_template_preimage_oracle_contract <- function() {
  oracle_env <- new.env(parent=asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_canonical_repaired_oracle.R",oracle_env)
  oracle <- oracle_env$.engine_canonical_repaired_oracle
  values <- matrix(c(-0,1/3,-1e-307,1e308,NA,NaN),3L,
    dimnames=list(c("c3","c1","c2"),c("a","b")))
  unnamed <- values;rownames(unnamed)<-NULL
  repeated <- values;rownames(repeated)<-c("same","same","other")
  for (payload in list(values,unnamed,repeated,as.data.frame(values),values>0)) {
    primitive <- structure(list(kind="space",space_id="template",values=payload,
      cell_id=c("c3","c1","c2"),dimensions=c(3L,2L),
      meta=list(label="雪\n",nested=list(a=1L))),class="wb_primitive")
    expected <- digest::digest(oracle(unclass(primitive)),algo="sha256",serialize=FALSE)
    stopifnot(identical(.wb_operation_pack_v2_retained_space_content_sha(primitive),expected))
  }
  TRUE
}

test_engine_space_template_refund_lifetime_contract <- function() {
  fixture <- new.env(parent=environment())
  sys.source("tests/test_operation_pack_v3_matrix_model_boundary_contract.R",fixture)
  state <- fixture$.wb_phase6_matrix_fixture();fit <- NULL
  on.exit({if (!is.null(fit)) try(wb_session_discard(fit$session),silent=TRUE)
    fixture$.wb_phase6_matrix_cleanup(state)},add=TRUE)
  fit <- wb_session_run_op(wb_session_new(),state$bundle,
    "scwbv3matrixmodel::fit_matrix_model",inputs=list(matrix="ATAC",n_latent=2L,
      chunk_size=2L,cell_set="all",min_cells=1L))
  promoted <- wb_session_promote_current(state$bundle,fit$session,
    outputs=c("model","summary"),created_by="lifetime-contract")
  id <- promoted$promoted$artifact_id[promoted$promoted$output=="model"][[1L]]
  fit$session <- wb_session_discard(fit$session)
  model <- wb_art_load(state$bundle,id,expected_kind="model_ref")
  plan <- .wb_space_payload_reader(state$bundle,model$model_space_id)
  on.exit(plan$close(),add=TRUE)
  available <- plan$block_elements();observed <- 0L
  wrapper <- plan
  wrapper$hold_memory <- function(bytes) {
    restore <- plan$hold_memory(bytes)
    function() tryCatch({
      found <- FALSE
      for (frame in sys.frames()) if (exists("artifact_id",frame,inherits=FALSE) &&
          exists("matches",frame,inherits=FALSE)) {
        found <- TRUE
        stopifnot(!exists("result",frame,inherits=FALSE),
          !exists("staged",frame,inherits=FALSE))
      }
      stopifnot(found);observed <<- observed+1L
    },finally=restore())
  }
  .wb_operation_pack_v3_matrix_model_fitted_space_recheck(state$bundle,id,
    model$model_linkage,.plan=wrapper)
  stopifnot(observed==1L,identical(plan$block_elements(),available))
  TRUE
}
