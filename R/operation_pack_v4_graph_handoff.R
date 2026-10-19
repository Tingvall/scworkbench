# Private custody of ONE already independently decoded fresh native output.
# No persisted freshness claim; ordinary/recovery/Python reads remain full.
.wb_operation_pack_v4_graph_handoff_eligible <- function(request, receipt) {
  tryCatch({
    identical(request$pack_abi_version, "4") &&
      identical(receipt$runtime_attestation$backend, "R") &&
      length(request$graph_write_grants) == 1L &&
      !length(receipt$registry_requests %||% list()) &&
      sum(vapply(receipt$outputs, function(item)
        identical(item$descriptor$kind, "graph"), logical(1))) == 1L &&
      all(vapply(receipt$outputs, function(item) {
        descriptor <- item$descriptor
        identical(descriptor$kind, "graph") ||
          (descriptor$kind %in% c(.wb_object_primitive_kinds(), "obs_table", "feature_table") &&
            all(vapply(c("matrix_fragment_manifest", "contained_model_tree",
              "contained_model_sibling_tree", "contained_matrix_model_sibling_tree"),
              function(name) is.null(descriptor[[name]]), logical(1))))
      }, logical(1)))
  }, error = function(error) FALSE)
}

.wb_operation_pack_v4_graph_header_bytes <- function(path) {
  tryCatch(setNames(vapply(c("request.json", "receipt.json"), function(relative) {
    actual <- .wb_bundle_path_require(path, relative, expected_type = "file",
      must_exist = TRUE, purpose = "fresh graph validation header")
    .wb_prov_sha256_file(actual)
  }, character(1)), c("request.json", "receipt.json")), error = function(error) NULL)
}

.wb_operation_pack_v4_graph_stage_guard <- function(stage) {
  tryCatch({
    if (!is.environment(stage) || isTRUE(stage$closed) ||
        is.null(stage$con) || !DBI::dbIsValid(stage$con) ||
        RSQLite::sqliteIsTransacting(stage$con)) return(NULL)
    target <- .wb_sqlite_aux_read_target(stage$con)
    if (!isTRUE(target$immutable) || !identical(target$path,
        normalizePath(stage$path, winslash = "/", mustWork = TRUE)) ||
        nzchar(Sys.readlink(stage$path)) ||
        any(file.exists(paste0(stage$path, c("-wal", "-shm", "-journal"))))) return(NULL)
    list(connection = stage$con@ref, target = target,
      file_identity = .wb_graph_file_identity(stage$path),
      sha256 = .wb_prov_sha256_file(stage$path),
      policy = stage$con@ref$wb_graph_policy,
      cache_cap = stage$con@ref$wb_graph_cache_kib,
      cache = DBI::dbGetQuery(stage$con, "PRAGMA cache_size;"),
      temp = DBI::dbGetQuery(stage$con, "PRAGMA temp_store;"))
  }, error = function(error) NULL)
}

.wb_operation_pack_v4_graph_record_bytes <- function(path, grant, connections = list()) {
  # Reuse existing bounded directory-name admission. No rows, axes, JSON or
  # matrix data are decoded, and no per-partition metadata ledger is retained.
  .wb_graph_require(dir.exists(path) && !nzchar(Sys.readlink(path)),
    "GRAPH_PAYLOAD_INVALID", "Fresh graph record root is missing or linked.")
  root <- list(path = normalizePath(path, winslash = "/", mustWork = TRUE),
    file_identity = .wb_graph_file_identity(path))
  # Preserve the original payload admission BEFORE any new full-file hashing.
  payloads <- vapply(c("payload.json", "graph.parts.ndjson"), function(leaf)
    .wb_bundle_path_require(path, paste0("outputs/", grant$output_name, "/", leaf),
      expected_type = "file", must_exist = TRUE, purpose = "fresh graph payload"), "")
  .wb_graph_require(!any(nzchar(Sys.readlink(payloads))), "GRAPH_PAYLOAD_INVALID",
    "Fresh graph payload is linked.")
  sizes <- file.info(payloads)$size
  .wb_graph_require(!anyNA(sizes) && sizes[[1L]] <= 16384,
    "GRAPH_RESOURCE_EXCEEDED", "Graph compact payload exceeds metadata admission.")
  .wb_graph_require(sum(sizes) <= as.numeric(grant$resource_budgets$max_staged_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Complete graph stage including descriptor exceeds admitted storage budget.")
  budgets <- .wb_operation_pack_v4_graph_budgets(grant$resource_budgets)
  for (con in Filter(function(con) !is.null(con) && DBI::dbIsValid(con), connections))
    budgets <- .wb_graph_effective_budgets(con, budgets)
  # Half a MiB covers two simultaneous compact byte ledgers, relative-name
  # copies, SHA strings/vectors and the fixed private stage/metadata proof.
  # Existing traversal names/C/R carriers remain separately pre-admitted.
  entries <- tryCatch(.wb_graph_native_tree_entries(path, budgets,
    reserve_bytes = 524288), error = function(error) {
      if (grepl("GRAPH_RESOURCE_EXCEEDED", conditionMessage(error), fixed = TRUE)) NULL
      else stop(error)
    })
  if (is.null(entries) || length(entries) > 128L ||
      sum(nchar(entries, type = "bytes")) > 8192) return(NULL)
  relative <- substring(entries, nchar(path) + 2L)
  info <- file.info(entries)
  .wb_graph_require(!anyNA(info$isdir) && !any(nzchar(Sys.readlink(entries))),
    "GRAPH_PAYLOAD_INVALID", "Fresh graph record contains a missing or linked entry.")
  files <- !info$isdir
  other <- files & !relative %in% c("state.json",
    paste0("outputs/", grant$output_name, "/graph.parts.ndjson"))
  # Ordinary side outputs retain their own admission. This first lane handles
  # only a compact complete record, not an extra scan of large mixed payloads.
  if (sum(info$size[other]) > 1048576) return(NULL)
  sha <- rep(NA_character_, length(entries)); bytes <- info$size
  for (i in which(files & relative != "state.json"))
    sha[[i]] <- .wb_prov_sha256_file(entries[[i]])
  bytes[!files | relative == "state.json"] <- NA_real_
  result <- data.frame(path = relative, directory = info$isdir,
    bytes = unname(bytes), sha256 = sha, stringsAsFactors = FALSE)
  .wb_graph_require(identical(root, list(path = normalizePath(path, winslash = "/",
      mustWork = TRUE), file_identity = .wb_graph_file_identity(path))) &&
    !nzchar(Sys.readlink(path)), "GRAPH_PAYLOAD_INVALID",
    "Fresh graph record root changed during byte observation.")
  attr(result, "root_identity") <- root
  result
}

.wb_operation_pack_v4_graph_stage_metadata <- function(stage) {
  list(seal = stage$seal, observations = stage$observations,
    budgets = stage$budgets, finished = stage$finished)
}

.wb_operation_pack_v4_graph_handoff_create <- function(path, request, receipt,
    request_identity, receipt_identity, headers_before, connections) {
  grant <- request$graph_write_grants[[1L]]
  seal <- receipt$graph_write_observations[[1L]]
  before <- .wb_operation_pack_v4_graph_record_bytes(path, grant, connections)
  if (is.null(before)) return(NULL)
  header_rows <- match(names(headers_before), before$path)
  .wb_graph_require(length(headers_before) == 2L && !anyNA(header_rows) &&
    identical(unname(headers_before), before$sha256[header_rows]),
    "GRAPH_PAYLOAD_INVALID", "Graph record headers changed during full validation.")
  staged <- .wb_operation_pack_v4_graph_payload(path, grant$output_name,
    seal, grant, connections = connections, cache_slots = 1L, .immutable_seal = TRUE)
  success <- FALSE
  on.exit(if (!success) .wb_graph_stage_discard(staged), add = TRUE)
  .wb_operation_pack_v4_graph_output_bindings_assert(staged, grant)
  .wb_graph_require(identical(before,
      .wb_operation_pack_v4_graph_record_bytes(path, grant, connections)) &&
    identical(staged$handoff_bytes, .wb_operation_pack_v4_graph_stage_guard(staged)),
    "GRAPH_PAYLOAD_INVALID", "Actual graph bytes changed during full validation.")
  result <- list(stage = staged, files = before, grant = grant, seal = seal,
    stage_bytes = staged$handoff_bytes,
    stage_metadata = .wb_operation_pack_v4_graph_stage_metadata(staged),
    request_identity = request_identity, receipt_identity = receipt_identity)
  success <- TRUE
  result
}

.wb_operation_pack_v4_graph_handoff_accept <- function(handoff, path,
    item, receipt, request, connections = list()) {
  same <- function(a, b) identical(.wb_operation_pack_canonical_json(a),
    .wb_operation_pack_canonical_json(b))
  grant <- Filter(function(x) identical(x$output_name, item$name), request$graph_write_grants)
  seal <- Filter(function(x) identical(x$output_name, item$name), receipt$graph_write_observations)
  .wb_graph_require(length(grant) == 1L && length(seal) == 1L &&
    same(handoff$request_identity, request$request_identity) &&
    same(handoff$receipt_identity, receipt$receipt_identity) &&
    same(handoff$grant, grant[[1L]]) && same(handoff$seal, seal[[1L]]) &&
    identical(handoff$files, .wb_operation_pack_v4_graph_record_bytes(path, grant[[1L]], connections)) &&
    identical(handoff$stage_metadata,
      .wb_operation_pack_v4_graph_stage_metadata(handoff$stage)) &&
    identical(handoff$stage_bytes,
      .wb_operation_pack_v4_graph_stage_guard(handoff$stage)),
    "GRAPH_PAYLOAD_INVALID", "Fresh graph evidence changed after independent validation.")
  state_path <- .wb_bundle_path_require(path, "state.json", expected_type = "file",
    must_exist = TRUE, purpose = "fresh graph transition state")
  state_bytes <- file.info(state_path)$size
  .wb_graph_require(length(state_bytes) == 1L && !is.na(state_bytes) &&
    state_bytes <= 65536, "GRAPH_PAYLOAD_INVALID",
    "Fresh graph transition state exceeds its compact metadata boundary.")
  state <- jsonlite::read_json(state_path, simplifyVector = FALSE)
  expected <- list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "reopened", transition_id = receipt$transition_id,
    receipt_identity = receipt$receipt_identity)
  .wb_graph_require(same(state, expected), "GRAPH_PAYLOAD_INVALID",
    "Fresh graph transition no longer has its expected reopened state.")
  handoff$stage
}
