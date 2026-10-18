.engine_space_old_encoder <- function() {
  environment <- new.env(parent=asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_canonical_repaired_oracle.R",environment)
  environment$.engine_canonical_repaired_oracle
}

.engine_space_old_semantic <- function(values, cells) {
  preimage <- list(
      schema = "scworkbench.operation_pack.space_slice.content.v1",
      dimensions = unname(as.list(as.integer(dim(values)))),
      cell_id = unname(as.list(as.character(cells))),
      values = lapply(seq_len(nrow(values)), function(i) unname(as.list(as.numeric(values[i, ])))))
  list(scheme="scworkbench.operation_pack.space_slice.content.v1",
    sha256=digest::digest(.engine_space_old_encoder()(preimage),algo="sha256",serialize=FALSE))
}

.engine_space_memory_plan <- function(values) list(cells = rownames(values),
  dimensions = as.integer(dim(values)), read = function(cells, dims = seq_len(ncol(values)))
    values[match(cells, rownames(values)), dims, drop = FALSE])

test_engine_typed_space_dual_preimage_contract <- function() {
  saved <- options(scworkbench.max_dense_materialize_mb = .03)
  on.exit(options(saved), add = TRUE)
  cases <- list(matrix(c(-0, 1/3, -1e-307, 1e308, NA, NaN), 2L),
    matrix(17, 1L, 1L), matrix(numeric(), 0L, 3L), matrix(numeric(), 3L, 0L),
    matrix(rep(c(-1.25, 0, 7), length.out = 301L*5L), 301L),
    matrix(seq_len(400L), 1L))
  for (values in cases) {
    rownames(values) <- if (nrow(values)) paste0('cell_"雪\\', seq_len(nrow(values))) else character()
    cells <- rownames(values)
    plan <- .engine_space_memory_plan(values)
    observed <- scworkbench:::.wb_operation_pack_space_semantic_identity(cells,
      ncol(values), plan$read)
    stopifnot(identical(observed, .engine_space_old_semantic(values, cells)))
    primitive <- structure(list(kind = "space", space_id = "s雪", values = values,
      cell_id = cells, dimensions = as.integer(dim(values)),
      storage_profile = "space_dense_v1", meta = list(label = "a\nb\t雪")), class = "wb_primitive")
    hydrated <- unclass(primitive)
    lazy <- primitive; lazy$values <- NULL
    pair <- scworkbench:::.wb_operation_pack_space_envelope_identities("source", lazy, plan)
    old <- .engine_space_old_encoder()
    stopifnot(identical(pair$value_sha, digest::digest(old(hydrated),algo="sha256",serialize=FALSE)),
      identical(pair$wrapped_sha,digest::digest(old(list(input = "source", value = hydrated)),algo="sha256",serialize=FALSE)))
  }
  TRUE
}

test_engine_typed_space_backed_reader_contract <- function() {
  if (!requireNamespace("rhdf5", quietly = TRUE)) return(contract_test_skip("rhdf5 unavailable"))
  root <- tempfile("engine_space_reader_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- paste0("c", seq_len(1025L)); wb_define_cells(b, cells)
  values <- outer(seq_along(cells), seq_len(17L), function(i,j) (i-j)/7)
  rownames(values) <- rev(cells); colnames(values) <- paste0("d", 1:17)
  wb_add_space(b, "source", values, source = "contract")
  plan <- scworkbench:::.wb_space_payload_reader(b, "source")
  on.exit(plan$close(),add=TRUE)
  selected <- cells[c(1025L, 2L, 1L, 800L)]
  got <- plan$read(selected, c(17L, 1L, 3L))
  stopifnot(identical(plan$cells, cells), identical(dim(got), c(4L, 3L)),
    identical(as.numeric(got), as.numeric(values[selected, c(17L,1L,3L)])),
    identical(attr(got, "scworkbench_payload_read")$values_read, 12L))
  expected <- values[cells, , drop = FALSE]
  observed <- scworkbench:::.wb_operation_pack_space_semantic_identity(cells,
    ncol(values), plan$read, plan)
  stopifnot(identical(observed, .engine_space_old_semantic(expected, cells)),
    !any(vapply(plan, is.matrix, logical(1))))
  plan$close()
  DBI::dbExecute(b$con,"UPDATE cells SET rowid=-7 WHERE cell_id='c3'")
  DBI::dbExecute(b$con,"UPDATE cells SET rowid=9007199254740993 WHERE cell_id='c2'")
  DBI::dbExecute(b$con,"UPDATE cells SET rowid=9007199254740992 WHERE cell_id='c1'")
  plan <- scworkbench:::.wb_space_payload_reader(b,"source")
  stopifnot(identical(plan$cells,as.character(wb_cells(b,cell_set="all"))),
    identical(tail(plan$cells,2L),c("c1","c2")),identical(plan$cells[[1L]],"c3"))
  # A changed registry is not trusted merely because the planned axes still fit.
  DBI::dbExecute(b$con, "UPDATE space_payloads SET provenance_identity='changed' WHERE space_id='source'")
  stopifnot(inherits(try(plan$read(selected), silent = TRUE), "try-error"))
  TRUE
}

test_engine_typed_space_stream_failure_cleanup_contract <- function() {
  before <- sort(list.files(tempdir(), pattern = "^scwb_space_(identity|column_major)_", full.names = TRUE))
  values <- matrix(seq_len(40L), 10L, dimnames = list(paste0("c",1:10), NULL))
  plan <- .engine_space_memory_plan(values)
  calls <- 0L
  original <- plan$read
  plan$read <- function(cells, dims = seq_len(ncol(values))) {
    calls <<- calls+1L
    if (calls == 2L) stop("injected reader failure")
    original(cells, dims)
  }
  saved <- options(scworkbench.max_dense_materialize_mb = .01)
  on.exit(options(saved), add = TRUE)
  primitive <- structure(list(kind = "space", space_id = "source", cell_id = rownames(values),
    dimensions = as.integer(dim(values)), storage_profile = "space_dense_v1", meta = list()), class = "wb_primitive")
  # Force multiple reads despite tiny source without changing any identity rule.
  plan$read <- function(cells, dims = seq_len(ncol(values))) stop("injected reader failure")
  stopifnot(inherits(try(scworkbench:::.wb_operation_pack_space_envelope_identities(
    "source", primitive, plan), silent = TRUE), "try-error"))
  stopifnot(identical(before, sort(list.files(tempdir(),
    pattern = "^scwb_space_(identity|column_major)_", full.names = TRUE))))
  plan <- .engine_space_memory_plan(values)
  pair <- scworkbench:::.wb_operation_pack_space_envelope_identities("source", primitive, plan)
  hydrated <- primitive; hydrated$values <- values
  stopifnot(identical(pair$value_sha, scworkbench:::.wb_operation_pack_sha256(unclass(hydrated))))
  TRUE
}

test_engine_typed_space_grant_partition_contract <- function() {
  if (!requireNamespace("rhdf5", quietly = TRUE)) return(contract_test_skip("rhdf5 unavailable"))
  root <- tempfile("engine_space_grant_"); b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- paste0("c", seq_len(33L)); wb_define_cells(b, cells)
  values <- matrix(seq_len(99L)/13, 33L, dimnames = list(cells, paste0("d",1:3)))
  wb_add_space(b, "source", values, source = "contract")
  plan <- scworkbench:::.wb_space_payload_reader(b, "source")
  observed_elements <- numeric()
  getter <- plan$read
  plan$read <- function(cells, dims = seq_len(3L)) {
    observed_elements <<- c(observed_elements, length(cells)*length(dims))
    getter(cells, dims)
  }
  input <- wb_prim_space("source")
  input$cell_id <- cells; input$dimensions <- as.integer(dim(values))
  input$storage_profile <- "space_dense_v1"
  declaration <- list(kind = "space", alignment = "cell")
  observed <- scworkbench:::.wb_operation_pack_v2_input_descriptor("source", input,
    declaration, space_plan = plan)
  hydrated <- input; hydrated$values <- values
  expected <- scworkbench:::.wb_operation_pack_v2_input_descriptor("source", hydrated, declaration)
  stopifnot(identical(observed, expected))
  selected <- cells[c(33,2,1,20,7)]
  read_declaration <- list(name = "selected", input = "source", role = "query",
    selection = list(policy = "parameter_cell_selector_v1", parameter = "selected"),
    chunk_size_parameter = "chunk")
  stage <- file.path(root, "test_stage"); dir.create(stage)
  grant <- scworkbench:::.wb_operation_pack_v3_typed_space_grant(b,
    read_declaration, input, observed$descriptor,
    list(selected = as.list(selected), chunk = 2L), list(scheme="test",sha256=strrep("a",64L)),
    stage, space_plan = plan)
  stopifnot(identical(grant$source_reference$selected_content_identity,
    .engine_space_old_semantic(values[selected, , drop = FALSE], selected)))
  request <- list(typed_space_grants = list(grant))
  attr(request, "operation_pack_v3_typed_space_values") <- list(selected = list(
    cells = selected, input = input, plan = plan))
  state <- new.env(parent = emptyenv()); state$used <- FALSE; state$reader_calls <- list()
  adapter <- scworkbench:::.wb_operation_pack_v3_add_typed_space_readers(
    list(state = state, readers = list()), request)
  observed_elements <- numeric()
  # Invalid order/foreign/repeated/oversize calls consume no partition state.
  for (bad in list(rev(selected[1:2]), "foreign", selected[c(1,1)], selected[1:3]))
    stopifnot(inherits(try(adapter$readers$selected(bad), silent = TRUE), "try-error"))
  pieces <- lapply(list(selected[1:2], selected[3:4], selected[5]), adapter$readers$selected)
  stopifnot(identical(as.numeric(do.call(rbind, lapply(pieces, `[[`, "values"))),
      as.numeric(values[selected, , drop = FALSE])), max(observed_elements) <= 6,
    inherits(try(adapter$readers$selected(selected[1]), silent = TRUE), "try-error"))
  # Invocation plans are excluded from wire JSON, including durable paths/closures.
  json <- jsonlite::toJSON(request, auto_unbox = TRUE, null = "null")
  stopifnot(!grepl(root, json, fixed = TRUE), !grepl("space_plans", json, fixed = TRUE),
    !grepl("function", json, fixed = TRUE), is.null(input$values))
  before <- sort(list.files(file.path(root,"operation_pack_v2"), recursive = TRUE, all.files = TRUE))
  payload <- scworkbench:::.wb_space_payload_registry_row(b,"source")
  path <- scworkbench:::.wb_space_payload_path(b,payload,must_exist=TRUE)
  rhdf5::h5write(777, path, "coordinates", index = list(1L,1L))
  stopifnot(inherits(try(plan$read(cells[1]), silent = TRUE), "try-error"),
    inherits(try(scworkbench:::.wb_operation_pack_v3_full_space_assert_current(b,
      "source", cells = cells, expected_semantic_identity = .engine_space_old_semantic(values,cells)),
      silent = TRUE), "try-error"),
    identical(before, sort(list.files(file.path(root,"operation_pack_v2"), recursive = TRUE, all.files = TRUE))))
  TRUE
}

test_engine_typed_space_native_lifecycle_contract <- function() {
  if (!requireNamespace("rhdf5", quietly = TRUE)) return(contract_test_skip("rhdf5 unavailable"))
  root <- tempfile("engine_space_native_"); dir.create(root)
  lib <- file.path(root, "library"); dir.create(lib)
  old_lib <- .libPaths()
  b <- NULL; sessions <- list()
  on.exit({for (session in sessions) try(wb_session_discard(session),silent=TRUE)
    try(wb_operation_pack_unload("enginespacefixture"), silent = TRUE)
    if ("scwbEngineSpaceFixture" %in% loadedNamespaces()) try(unloadNamespace("scwbEngineSpaceFixture"),silent=TRUE)
    .libPaths(old_lib); if (!is.null(b)) try(wb_close_bundle(b),silent=TRUE)
    unlink(root, recursive = TRUE)}, add = TRUE)
  log <- file.path(root,"install.log")
  status <- system2(file.path(R.home("bin"),"R"), c("CMD","INSTALL",
    paste0("--library=",shQuote(lib)), shQuote(normalizePath("tests/fixtures/engine-typed-space"))),
    stdout=log,stderr=log)
  if (status != 0L) stop(paste(readLines(log),collapse="\n"))
  .libPaths(c(lib,old_lib))
  manifest <- system.file("scworkbench","operation-pack.json", package="scwbEngineSpaceFixture",lib.loc=lib)
  wb_operation_pack_activate(manifest, lib.loc=lib)
  b <- wb_init_bundle(file.path(root,"bundle"),overwrite=TRUE)
  cells <- paste0("c",seq_len(65L)); wb_define_cells(b,cells)
  values <- matrix(as.double(seq_len(65L*5L)),65L,dimnames=list(cells,paste0("d",1:5)))
  wb_add_space(b,"source",values,source="contract")
  observations <- new.env(parent=emptyenv()); observations$count <- 0L
  row <- scworkbench:::.wb_space_payload_registry_row(b,"source")
  observations$path <- normalizePath(scworkbench:::.wb_space_payload_path(b,row,must_exist=TRUE))
  saved_observations <- options(scworkbench.engine_space_observations=observations)
  on.exit(options(saved_observations),add=TRUE)
  trace(".wb_prov_sha256_file",where=asNamespace("scworkbench"),print=FALSE,
    tracer=quote({.observed <- getOption("scworkbench.engine_space_observations")
      if (!is.null(.observed) && identical(normalizePath(path,mustWork=FALSE),.observed$path))
        .observed$count <- .observed$count+1L}))
  on.exit(untrace(".wb_prov_sha256_file",where=asNamespace("scworkbench")),add=TRUE)
  trace("wb_space",where=asNamespace("scworkbench"),print=FALSE,
    tracer=quote(if (identical(space_id,"source") && is.null(cells))
      stop("Unbounded symbolic typed-space getter read")))
  on.exit(untrace("wb_space",where=asNamespace("scworkbench")),add=TRUE)
  workspace <- file.path(root,"sessions"); dir.create(workspace)
  initial <- wb_session_create(b,workspace_root=workspace,session_id="space_native")
  sessions[[length(sessions)+1L]] <- initial
  run <- function(session, size) wb_session_run_op(session,b,"enginespacefixture::row_sum",
    inputs=list(source="source",chunk_size=as.integer(size)))
  # Post-receipt fault exercises real transition rollback, not just hash cleanup.
  before <- list.files(file.path(b$dir,"operation_pack_v2"),recursive=TRUE,all.files=TRUE)
  for (failed_event in c("receipt_received","before_publication")) {
    saved <- options(scworkbench.operation_pack_v2_test_hook=function(event,...) {
      if (identical(event,failed_event)) stop("injected typed-space lifecycle failure")
    })
    failure <- try(run(initial,8L),silent=TRUE)
    options(saved)
    stopifnot(inherits(failure,"try-error"),length(initial$runs)==0L,
      identical(before,list.files(file.path(b$dir,"operation_pack_v2"),recursive=TRUE,all.files=TRUE)),
      nrow(wb_art_list(b))==0L)
  }
  observations$count <- 0L
  result <- run(initial,8L)
  sessions[[length(sessions)+1L]] <- result$session
  hashes_eight <- observations$count
  output <- result$run$outputs$sums
  stopifnot(identical(output$cell_id,cells),
    isTRUE(all.equal(as.numeric(output$value),as.numeric(rowSums(values)),tolerance=0)))
  # The exact same source is independently authenticated at request/audit;
  # increasing callback partitions does not change terminal values/identity.
  second_initial <- wb_session_create(b,workspace_root=workspace,session_id="space_native_other")
  sessions[[length(sessions)+1L]] <- second_initial
  observations$count <- 0L
  result2 <- run(second_initial,2L)
  sessions[[length(sessions)+1L]] <- result2$session
  stopifnot(identical(result2$run$outputs$sums,output),is.null(result$run$inputs$space_plans),
    hashes_eight>0L,observations$count==hashes_eight)
  cat("TYPED_SPACE_SOURCE_FILE_HASHES chunk8=",hashes_eight," chunk2=",observations$count,"\n",sep="")
  TRUE
}

test_engine_typed_space_vlen_metadata_contract <- function() {
  python <- Sys.getenv("PYBENCH_PYTHON", "")
  if (!nzchar(python)) return(contract_test_skip("PYBENCH_PYTHON not configured for HDF5 VLEN fixture"))
  root <- tempfile("engine_space_vlen_"); b <- wb_init_bundle(root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE)},add=TRUE)
  cells <- c("c雪1","c2","c3","c4"); wb_define_cells(b,cells)
  values <- matrix(as.double(1:12),4L,dimnames=list(cells,c("d1","dim_雪","d3")))
  wb_add_space(b,"source",values,source="synthetic_fixture")
  row <- scworkbench:::.wb_space_payload_registry_row(b,"source")
  path <- scworkbench:::.wb_space_payload_path(b,row,must_exist=TRUE)
  fresh <- file.path(root,"fresh_python_producer.h5")
  stopifnot(system2(python,c(shQuote("tests/fixtures/engine-typed-space/write_vlen_fixture.py"),shQuote(fresh)))==0L)
  # Construct a fresh producer fixture BEFORE authentication. This is not a
  # mutation accepted by a retained reader: changed published bytes without
  # corresponding independent authority are rejected in the other contracts.
  stopifnot(file.copy(fresh,path,overwrite=TRUE))
  DBI::dbExecute(b$con,"UPDATE space_payloads SET content_sha256=? WHERE space_id='source'",
    params=list(scworkbench:::.wb_prov_sha256_file(path)))
  plan <- scworkbench:::.wb_space_payload_reader(b,"source")
  on.exit(plan$close(),add=TRUE)
  got <- plan$read(c("c4","c雪1"),c(2L,1L))
  stopifnot(identical(as.numeric(got),as.numeric(values[c("c4","c雪1"),c(2L,1L)])),
    identical(colnames(got),c("dim_雪","d1")),
    identical(scworkbench:::.wb_operation_pack_space_semantic_identity(cells,3L,plan$read,plan),
      .engine_space_old_semantic(values,cells)))
  TRUE
}

test_engine_typed_space_shared_metadata_admission_contract <- function() {
  root <- tempfile("engine_space_budget_"); b <- wb_init_bundle(root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE)},add=TRUE)
  cells <- paste0("c",1:17); wb_define_cells(b,cells)
  values <- matrix(as.double(1:51),17L,dimnames=list(cells,paste0("d",1:3)))
  wb_add_space(b,"source",values,source="contract")
  budget <- scworkbench:::.wb_operation_pack_v3_broker_projection_budget(b)
  first <- scworkbench:::.wb_space_payload_reader(b,"source",.budget=budget)
  on.exit(first$close(),add=TRUE)
  charged <- budget$used; stopifnot(charged>0)
  second <- scworkbench:::.wb_space_payload_reader(b,"source",.budget=budget)
  on.exit(second$close(),add=TRUE)
  stopifnot(budget$used==2*charged-budget$space_hdf_bytes)
  second$close(); stopifnot(budget$used==charged)
  maximum <- budget$memory; budget$memory <- budget$used+8192+63
  stopifnot(inherits(try(first$read(cells[1],1L),silent=TRUE),"try-error"))
  budget$memory <- maximum
  stopifnot(identical(as.numeric(first$read(cells[1],1L)),as.numeric(values[1,1])))
  first$close(); stopifnot(budget$used==0,
    inherits(try(first$read(cells[1],1L),silent=TRUE),"try-error"))
  budget$limit <- 1
  stopifnot(inherits(try(scworkbench:::.wb_space_payload_reader(b,"source",.budget=budget),silent=TRUE),"try-error"),
    budget$used==0)
  TRUE
}
