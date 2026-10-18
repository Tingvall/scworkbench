# R/provenance_store.R

.wb_prov_new_snapshot_id <- function(con = NULL) {
  .wb_allocate_db_identifier(
    con, "prov_heads", "snapshot_id",
    paste0("prov_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
    n = 8L, purpose = "provenance snapshot"
  )
}

.wb_identity_schemes <- function() {
  c(
    legacy = "scworkbench.identity.legacy-hash-text16.v1",
    run = "scworkbench.integrity.run.framed-utf8.sha256.v2",
    contract = "scworkbench.integrity.contract.utf8.sha256.v2",
    structural = "scworkbench.structural.primitive-summary.sha256.v2",
    materialization = "scworkbench.materialization.r-serialize-v3.sha256.v2",
    identifier = "scworkbench.identifier.framed-utf8.sha256.v1"
  )
}

.wb_identity_digest_hook <- function(domain, n_bytes) {
  hook <- getOption("scworkbench.provenance_digest_test_hook", NULL)
  if (is.function(hook)) hook(domain = as.character(domain)[1], n_bytes = as.double(n_bytes)[1])
  invisible(TRUE)
}

.wb_sha256_raw <- function(x, domain = "raw") {
  .wb_assert(is.raw(x), "SHA-256 input must be raw bytes.")
  .wb_require_pkg("digest", "provenance SHA-256 identity")
  .wb_identity_digest_hook(domain, length(x))
  tolower(as.character(digest::digest(x, algo = "sha256", serialize = FALSE)))
}

.wb_utf8_raw <- function(x) {
  x <- as.character(x %||% "")
  x[is.na(x)] <- "NA"
  charToRaw(enc2utf8(paste(x, collapse = "|")))
}

.wb_hash_framed_utf8 <- function(parts, domain) {
  parts <- as.character(parts %||% "")
  parts[is.na(parts)] <- "NA"
  encoded <- lapply(enc2utf8(parts), charToRaw)
  framed <- c(
    charToRaw(enc2utf8(as.character(domain)[1])), as.raw(0L),
    unlist(lapply(encoded, function(bytes) {
      c(charToRaw(sprintf("%016x", length(bytes))), as.raw(0L), bytes)
    }), use.names = FALSE)
  )
  .wb_sha256_raw(framed, domain = domain)
}

# Generic non-persisted text identity. Persisted integrity callers use the
# scheme-specific helpers below so a digest is never ambiguous.
.wb_hash_text <- function(x) {
  if (is.raw(x)) return(.wb_sha256_raw(x, domain = "generic_raw"))
  .wb_sha256_raw(.wb_utf8_raw(x), domain = "generic_text")
}

# Read-only compatibility implementation for hashes already persisted before
# provenance schema 1.9. Double arithmetic avoids the original integer
# overflow; chunked vector operations avoid the warning-producing per-byte R
# loop. New identities must never use this function.
.wb_hash_text_legacy_v1 <- function(x) {
  bytes <- as.double(as.integer(.wb_utf8_raw(x)))
  if (!length(bytes)) return("0000000000000000")
  h1 <- 0
  h2 <- 0
  chunk_size <- 1000000L
  starts <- seq.int(1L, length(bytes), by = chunk_size)
  for (start in starts) {
    end <- min(length(bytes), start + chunk_size - 1L)
    pos <- as.double(seq.int(start, end))
    block <- bytes[start:end]
    h1 <- (h1 + sum(block * pos)) %% 2147483647
    h2 <- (h2 + sum(block * ((pos %% 251) + 1))) %% 2147483629
  }
  paste0(sprintf("%08x", as.integer(h1)), sprintf("%08x", as.integer(h2)))
}

.wb_prov_run_hash <- function(op_name, params_json, inputs_json,
                              symbolic_inputs_json, execution_inputs_json,
                              scheme = unname(.wb_identity_schemes()[["run"]])) {
  parts <- c(op_name %||% "", params_json, inputs_json,
             symbolic_inputs_json, execution_inputs_json)
  if (identical(as.character(scheme)[1], unname(.wb_identity_schemes()[["legacy"]]))) {
    return(.wb_hash_text_legacy_v1(parts))
  }
  .wb_assert(identical(as.character(scheme)[1], unname(.wb_identity_schemes()[["run"]])),
             paste0("Unsupported run hash scheme: ", as.character(scheme)[1]))
  .wb_hash_framed_utf8(parts, domain = "run-integrity-v2")
}

.wb_prov_contract_hash <- function(contract_json,
                                   scheme = unname(.wb_identity_schemes()[["contract"]])) {
  if (identical(as.character(scheme)[1], unname(.wb_identity_schemes()[["legacy"]]))) {
    return(.wb_hash_text_legacy_v1(as.character(contract_json %||% "")[1]))
  }
  .wb_assert(identical(as.character(scheme)[1], unname(.wb_identity_schemes()[["contract"]])),
             paste0("Unsupported contract hash scheme: ", as.character(scheme)[1]))
  .wb_sha256_raw(.wb_utf8_raw(as.character(contract_json %||% "")[1]), domain = "contract-integrity-v2")
}

.wb_prov_materialization_hash <- function(prim) {
  .wb_sha256_raw(serialize(prim, NULL, version = 3), domain = "materialization-v2")
}

.wb_identifier_sha256 <- function(parts, namespace) {
  paste0(as.character(namespace)[1], ":sha256:",
         .wb_hash_framed_utf8(parts, domain = paste0("identifier:", as.character(namespace)[1])))
}

.wb_prov_primitive_entity_binding <- function(x) {
  # execution_inputs stores compact primitive summaries, not payloads. Those
  # summaries are an explicit provenance contract and are safe to bind.
  if (!.wb_is_primitive(x) && !(is.list(x) && as.character(x$kind %||% "")[1] %in% c("matrix", "space", "space_2d", "model_ref"))) return(NULL)
  kind <- as.character(x$kind %||% "")[1]
  scalar_or <- function(value, default = "") {
    out <- as.character(value %||% default)[1]
    if (is.na(out) || !length(out)) default else out
  }
  id <- if (identical(kind, "matrix")) {
    x$matrix_id
  } else if (kind %in% c("space", "space_2d")) {
    x$space_id
  } else if (identical(kind, "model_ref")) {
    # A fitted model is not interchangeable with the space it projects into.
    # Keep this identifier opaque and stable across reopen; model_space_id alone
    # is insufficient when different engines share a destination space.
    paste(
      scalar_or(x$engine, "unknown"),
      scalar_or(x$model_space_id %||% x$space_id, ""),
      scalar_or(x$in_space_id, ""),
      sep = "|"
    )
  } else NULL
  if (is.null(id) || is.na(as.character(id)[1]) || !nzchar(as.character(id)[1])) return(NULL)
  list(
    entity_kind = if (kind %in% c("space", "space_2d")) "space" else kind,
    entity_id = as.character(id)[1],
    path = if (identical(kind, "model_ref")) as.character(x$model_path %||% NA_character_)[1] else NA_character_
  )
}

.wb_prov_collect_entity_bindings <- function(x, name = "input") {
  out <- list()
  walk <- function(v, path) {
    if (inherits(v, "wb_entity_ref") ||
        (is.list(v) && identical(as.character(v$ref_type %||% "")[1L], "bundle_entity"))) {
      ref <- .wb_capsule_normalize_ref(v, path)
      out[[length(out) + 1L]] <<- list(
        binding_name = path, entity_kind = ref$entity_kind,
        entity_id = ref$entity_id, path = NA_character_
      )
      return(invisible(NULL))
    }
    if (.wb_is_metadata_field_ref(v)) {
      ref <- .wb_validate_metadata_field_ref(v, path)
      out[[length(out) + 1L]] <<- list(
        binding_name = path, entity_kind = "metadata_field",
        entity_id = ref$field_id, path = NA_character_
      )
      return(invisible(NULL))
    }
    b <- .wb_prov_primitive_entity_binding(v)
    if (!is.null(b)) out[[length(out) + 1L]] <<- c(list(binding_name = path), b)
    if (is.list(v) && !inherits(v, "wb_primitive")) for (nm in names(v) %||% seq_along(v)) walk(v[[nm]], paste0(path, ".", nm))
  }
  walk(x, name); out
}

.wb_prov_schema_version <- function() "1.10"

.wb_replay_equivalence_policies <- function() {
  c(
    "exact_content", "exact_canonical_value", "exact_graph_descriptor", "cell_aligned_embedding",
    "loadable_reference", "not_comparable"
  )
}

.wb_replay_model_reference <- function(prim) {
  .wb_assert(.wb_is_primitive(prim) && identical(as.character(prim$kind), "model_ref"),
             "Replay model reference requires a model_ref primitive.")
  .wb_prov_sha256_object(list(
    identity_version = "scworkbench.replay.model_reference.v1",
    engine = as.character(prim$engine %||% "unknown")[1],
    model_space_id = as.character(prim$model_space_id %||% prim$space_id %||% "")[1],
    in_space_id = as.character(prim$in_space_id %||% "")[1],
    model_type = as.character(prim$model_type %||% prim$engine %||% "unknown")[1]
  ))
}

.wb_replay_space_alignment_reference <- function(bundle, prim, workspace = NULL,
                                                  staging_bundle = NULL) {
  if (!inherits(bundle, "scworkbench_bundle") || !.wb_is_primitive(prim) ||
      !as.character(prim$kind)[1] %in% c("space", "space_2d")) {
    return(list(valid = FALSE, reference = NA_character_,
                message = "Output is not a bundle-backed space primitive."))
  }
  space_id <- as.character(prim$space_id %||% "")[1]
  registry <- tryCatch(
    DBI::dbGetQuery(
      bundle$con,
      "SELECT space_id, source, dims, storage FROM spaces WHERE space_id = ?;",
      params = list(space_id)
    ),
    error = function(e) data.frame()
  )
  if (nrow(registry) != 1L) {
    return(list(valid = FALSE, reference = NA_character_,
                message = "Space registry row is missing or ambiguous."))
  }

  dims <- as.integer(registry$dims[1])
  if (identical(as.character(registry$storage[1]), .wb_space_payload_storage())) {
    summary <- tryCatch(.wb_space_payload_summary(
      bundle, space_id, verify_hash = FALSE, workspace = workspace,
      staging_bundle = staging_bundle
    ),
                        error = function(e) NULL)
    if (is.null(summary)) return(list(valid = FALSE, reference = NA_character_,
                                      message = "File-backed space payload is invalid."))
    cells <- sort(as.character(summary$cells))
    complete <- isTRUE(summary$complete)
    finite <- isTRUE(summary$finite)
    nondegenerate <- isTRUE(summary$nondegenerate)
    valid <- complete && finite && nondegenerate
    contract <- list(
      identity_version = "scworkbench.replay.cell_aligned_embedding.v1",
      kind = as.character(prim$kind)[1], space_id = space_id,
      source = as.character(registry$source[1] %||% ""),
      storage = as.character(registry$storage[1]), dims = dims,
      n_cells = length(cells), cell_ids_sha256 = .wb_prov_sha256_object(cells),
      complete = complete, finite = finite, nondegenerate = nondegenerate
    )
    return(list(valid = valid, reference = .wb_prov_sha256_object(contract),
                message = if (valid) "Space has the declared cell universe, dimensions, and finite nondegenerate coordinates." else "Space is incomplete, non-finite, or degenerate."))
  }
  wide <- identical(as.character(registry$storage[1]), "wide:space_2d")
  coordinates <- if (wide) {
    tryCatch(
      DBI::dbGetQuery(
        bundle$con,
        "SELECT cell_id, x, y FROM space_2d WHERE space_id = ? ORDER BY cell_id;",
        params = list(space_id)
      ),
      error = function(e) data.frame()
    )
  } else {
    tryCatch(
      DBI::dbGetQuery(
        bundle$con,
        "SELECT cell_id, dim, value FROM space_coords WHERE space_id = ? ORDER BY cell_id, dim;",
        params = list(space_id)
      ),
      error = function(e) data.frame()
    )
  }
  cells <- sort(unique(as.character(coordinates$cell_id %||% character())))
  values <- if (wide && nrow(coordinates)) {
    as.matrix(coordinates[, c("x", "y"), drop = FALSE])
  } else if (nrow(coordinates)) {
    split(as.numeric(coordinates$value), as.integer(coordinates$dim))
  } else {
    list()
  }
  finite <- if (wide) {
    length(values) > 0L && all(is.finite(values))
  } else {
    length(values) == dims && all(vapply(values, function(x) all(is.finite(x)), logical(1)))
  }
  nondegenerate <- if (wide) {
    nrow(values) > 1L && all(apply(values, 2L, function(x) diff(range(x)) > 0))
  } else {
    length(values) == dims && all(vapply(values, function(x) length(x) > 1L && diff(range(x)) > 0, logical(1)))
  }
  complete <- nrow(coordinates) > 0L && length(cells) > 0L &&
    if (wide) dims == 2L && nrow(coordinates) == length(cells) else
      nrow(coordinates) == length(cells) * dims &&
        !anyDuplicated(paste(coordinates$cell_id, coordinates$dim, sep = "\r"))
  valid <- isTRUE(complete) && isTRUE(finite) && isTRUE(nondegenerate)
  contract <- list(
    identity_version = "scworkbench.replay.cell_aligned_embedding.v1",
    kind = as.character(prim$kind)[1],
    space_id = space_id,
    source = as.character(registry$source[1] %||% ""),
    storage = as.character(registry$storage[1]),
    dims = dims,
    n_cells = length(cells),
    cell_ids_sha256 = .wb_prov_sha256_object(cells),
    complete = isTRUE(complete),
    finite = isTRUE(finite),
    nondegenerate = isTRUE(nondegenerate)
  )
  list(
    valid = valid,
    reference = .wb_prov_sha256_object(contract),
    message = if (valid) {
      "Space has the declared cell universe, dimensions, and finite nondegenerate coordinates."
    } else {
      "Space is incomplete, non-finite, or degenerate."
    }
  )
}

.wb_replay_equivalence_declaration <- function(op_name, output_name, prim, identity,
                                               bundle = NULL, workspace = NULL,
                                               staging_bundle = NULL) {
  # Ingestion/provenance-only runs are valid engine records even when they do
  # not dispatch through the analytical op catalog.
  op <- tryCatch(.wb_get_op(as.character(op_name)[1]), error = function(e) list(replay_equivalence = list()))
  kind <- if (.wb_is_primitive(prim)) as.character(prim$kind)[1] else "unknown"
  declared <- as.character(op$replay_equivalence[[as.character(output_name)[1]]] %||% "")[1]
  policy <- if (nzchar(declared)) {
    declared
  } else if (identical(kind, "model_ref")) {
    "loadable_reference"
  } else if (identical(as.character(identity$verification_level), "content") &&
             !is.na(identity$content_sha256) && nzchar(as.character(identity$content_sha256))) {
    "exact_canonical_value"
  } else {
    "not_comparable"
  }
  .wb_assert(policy %in% .wb_replay_equivalence_policies(), paste0(
    "Unknown replay-equivalence policy for ", op_name, "::", output_name, ": ", policy
  ))
  reference <- if (identical(policy, "loadable_reference") && identical(kind, "model_ref")) {
    .wb_replay_model_reference(prim)
  } else if (identical(policy, "exact_graph_descriptor")) {
    .wb_assert(identical(kind, "graph"), "Graph descriptor replay policy requires a graph primitive.")
    identity$graph_descriptor_identity$sha256
  } else if (identical(policy, "cell_aligned_embedding")) {
    alignment <- .wb_replay_space_alignment_reference(
      bundle, prim, workspace = workspace, staging_bundle = staging_bundle
    )
    .wb_assert(isTRUE(alignment$valid), paste0(
      "Cannot declare cell-aligned embedding replay equivalence for ",
      op_name, "::", output_name, ": ", alignment$message
    ))
    alignment$reference
  } else if (policy %in% c("exact_content", "exact_canonical_value")) {
    as.character(identity$content_sha256 %||% NA_character_)[1]
  } else {
    NA_character_
  }
  list(policy = policy, reference = reference, status = "declared")
}

# Content identity is deliberately separate from structural, integrity, and
# display-identifier schemes. Tables preserve their supplied row order; callers must
# declare and implement a stable-key ordering before an output is semantically
# unordered.
.wb_prov_sha256_object <- function(x) {
  .wb_require_pkg("digest", "SHA-256 provenance content identity")
  # R's native serialization header includes the producing R version, so the
  # same value serialized by two supported runtimes does not have the same
  # bytes.  A bundle content identity must survive transfer between runtimes.
  # serializeJSON preserves R types, attributes, names, and ordering while
  # providing a stable textual representation suitable for a portable digest.
  canonical <- jsonlite::serializeJSON(x, digits = NA)
  digest::digest(canonical, algo = "sha256", serialize = FALSE)
}

.wb_prov_sha256_file <- function(path) {
  .wb_require_pkg("openssl", "SHA-256 provenance payload identity")
  .wb_assert(file.exists(path) && !dir.exists(path), paste0("Missing payload file for SHA-256: ", path))
  input <- file(path, "rb")
  tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
}

.wb_content_identity_schemes <- function() {
  c(
    object = "scworkbench.content.object.canonical-json.v1",
    graph = "scworkbench.graph.content.canonical-json.v1",
    table = "scworkbench.content.table.row-json-fold.v1",
    matrix = "scworkbench.content.matrix.fragment-tree.v2",
    space = "scworkbench.content.space.canonical-json.v1",
    dense_space = "scworkbench.content.dense-space-hdf5.sha256.v1",
    raw_file = "scworkbench.content.raw-file.sha256.v1",
    file_tree = "scworkbench.content.file-tree.canonical-json.v1",
    registry = "scworkbench.content.registry.canonical-json.v1",
    metadata_field = "scworkbench.content.metadata-field.cell-id-fold.v1",
    cell_set_membership = "scworkbench.cell-set-membership.sorted-cell-id.canonical-json.v1"
  )
}

.wb_prov_path_identity <- function(path) {
  list(
    content_sha256 = .wb_prov_file_tree_sha256(path),
    content_identity_scheme = if (dir.exists(path)) {
      unname(.wb_content_identity_schemes()[["file_tree"]])
    } else {
      unname(.wb_content_identity_schemes()[["raw_file"]])
    }
  )
}

.wb_prov_structural_fingerprint <- function(prim) {
  kind <- if (.wb_is_primitive(prim)) as.character(prim$kind %||% "unknown")[1] else "unknown"
  summary <- if (.wb_is_primitive(prim)) .wb_prim_summary(prim) else list(class = class(prim))
  .wb_hash_framed_utf8(
    c(kind, jsonlite::toJSON(.wb_json_sanitize(summary), auto_unbox = TRUE, null = "null")),
    domain = "primitive-structural-v2"
  )
}

.wb_prov_output_identity_select <- function(con, prefix = "") {
  p <- if (nzchar(prefix)) paste0(prefix, ".") else ""
  structural <- if (.wb_db_has_column(con, "prov_run_outputs", "structural_fingerprint")) paste0("COALESCE(", p, "structural_fingerprint, ", p, "output_hash) AS structural_fingerprint") else paste0(p, "output_hash AS structural_fingerprint")
  content <- if (.wb_db_has_column(con, "prov_run_outputs", "content_sha256")) paste0(p, "content_sha256") else "NULL AS content_sha256"
  level <- if (.wb_db_has_column(con, "prov_run_outputs", "verification_level")) paste0("COALESCE(", p, "verification_level, 'structural') AS verification_level") else "'structural' AS verification_level"
  status <- if (.wb_db_has_column(con, "prov_run_outputs", "verification_status")) paste0("COALESCE(", p, "verification_status, 'legacy_structural_only') AS verification_status") else "'legacy_structural_only' AS verification_status"
  scheme <- if (.wb_db_has_column(con, "prov_run_outputs", "content_identity_scheme")) paste0(p, "content_identity_scheme") else "NULL AS content_identity_scheme"
  structural_scheme <- if (.wb_db_has_column(con, "prov_run_outputs", "structural_fingerprint_scheme")) paste0(p, "structural_fingerprint_scheme") else "NULL AS structural_fingerprint_scheme"
  output_scheme <- if (.wb_db_has_column(con, "prov_run_outputs", "output_hash_scheme")) paste0(p, "output_hash_scheme") else "NULL AS output_hash_scheme"
  paste(structural, content, level, status, scheme, structural_scheme, output_scheme, sep = ", ")
}

.wb_prov_output_replay_select <- function(con, prefix = "") {
  p <- if (nzchar(prefix)) paste0(prefix, ".") else ""
  policy <- if (.wb_db_has_column(con, "prov_run_outputs", "replay_equivalence_policy")) {
    paste0("COALESCE(", p, "replay_equivalence_policy, 'not_comparable') AS replay_equivalence_policy")
  } else "'not_comparable' AS replay_equivalence_policy"
  reference <- if (.wb_db_has_column(con, "prov_run_outputs", "replay_equivalence_reference")) {
    paste0(p, "replay_equivalence_reference")
  } else "NULL AS replay_equivalence_reference"
  status <- if (.wb_db_has_column(con, "prov_run_outputs", "replay_equivalence_status")) {
    paste0("COALESCE(", p, "replay_equivalence_status, 'legacy_not_comparable') AS replay_equivalence_status")
  } else "'legacy_not_comparable' AS replay_equivalence_status"
  paste(policy, reference, status, sep = ", ")
}

.wb_prov_run_identity_select <- function(con, prefix = "") {
  p <- if (nzchar(prefix)) paste0(prefix,".") else ""
  run_scheme <- if (.wb_db_has_column(con,"prov_runs","run_hash_scheme")) paste0(p,"run_hash_scheme") else "NULL AS run_hash_scheme"
  contract_scheme <- if (.wb_db_has_column(con,"prov_runs","contract_hash_scheme")) paste0(p,"contract_hash_scheme") else "NULL AS contract_hash_scheme"
  paste(run_scheme,contract_scheme,sep=", ")
}

.wb_prov_table_payload <- function(prim) {
  # Artifact tables are durably represented as one sanitized JSON object per
  # row plus sanitized JSON metadata.  Hash that canonical durable form rather
  # than transient R attributes (for example jsonlite's `json` class) or typed
  # NA variants that are intentionally normalized by the storage contract.
  table <- prim$table
  canonical_table <- if (!is.data.frame(table) || !nrow(table)) {
    data.frame(stringsAsFactors = FALSE)
  } else {
    row_json <- vapply(seq_len(nrow(table)), function(i) {
      as.character(jsonlite::toJSON(
        .wb_json_sanitize(as.list(table[i, , drop = FALSE])),
        auto_unbox = TRUE, null = "null"
      ))
    }, character(1))
    .wb_art_table_rows_to_df(data.frame(row_json = row_json, stringsAsFactors = FALSE))
  }
  meta_json <- as.character(jsonlite::toJSON(
    .wb_json_sanitize(prim$meta %||% list()), auto_unbox = TRUE, null = "null"
  ))
  canonical_meta <- jsonlite::fromJSON(meta_json, simplifyVector = TRUE)
  list(
    identity_version = "scworkbench.payload.table.v2",
    kind = as.character(prim$kind),
    table_type = as.character(prim$table_type %||% "generic")[1],
    entity_kind = if (identical(prim$kind, "obs_table")) as.character(prim$entity_kind %||% "generic")[1] else NULL,
    table = canonical_table,
    meta = canonical_meta
  )
}

.wb_prov_table_content_sha256 <- function(prim) {
  header <- list(
    identity_version = "scworkbench.payload.table.stream.v1",
    kind = as.character(prim$kind),
    table_type = as.character(prim$table_type %||% "generic")[1],
    entity_kind = if (identical(prim$kind, "obs_table")) as.character(prim$entity_kind %||% "generic")[1] else NULL,
    meta = jsonlite::fromJSON(as.character(jsonlite::toJSON(
      .wb_json_sanitize(prim$meta %||% list()), auto_unbox = TRUE, null = "null"
    )), simplifyVector = TRUE)
  )
  state <- .wb_prov_sha256_object(header)
  fold <- .wb_prov_table_fold(state)
  table <- prim$table
  if (is.data.frame(table) && nrow(table)) for (start in
      seq.int(1L, nrow(table), by = 1000L)) {
    rows <- seq.int(start, min(nrow(table), start + 999L))
    state <- fold(.wb_prov_table_row_json(table, rows))
  }
  state
}

.wb_prov_stored_table_content_sha256 <- function(con, artifact_id, chunk_size = 1000L) {
  info <- DBI::dbGetQuery(con, "SELECT a.type, t.table_type, t.entity_kind, t.meta_json FROM artifacts a JOIN artifact_tables t ON t.artifact_id=a.artifact_id WHERE a.artifact_id=?;", params=list(artifact_id))
  .wb_assert(nrow(info)==1L, paste0("Missing stored table artifact identity header: ",artifact_id))
  meta_text <- as.character(info$meta_json[1] %||% "{}")[1]
  meta <- if (!is.na(meta_text) && nzchar(meta_text)) jsonlite::fromJSON(meta_text,simplifyVector=TRUE) else list()
  header <- list(
    identity_version = "scworkbench.payload.table.stream.v1",
    kind = as.character(info$type[1]), table_type = as.character(info$table_type[1]),
    entity_kind = if (identical(as.character(info$type[1]),"obs_table")) as.character(info$entity_kind[1]) else NULL,
    meta = meta
  )
  state <- .wb_prov_sha256_object(header)
  fold <- .wb_prov_table_fold(state)
  last <- -1L
  repeat {
    rows <- DBI::dbGetQuery(con,"SELECT row_idx,row_json FROM artifact_table_rows WHERE artifact_id=? AND row_idx>? ORDER BY row_idx LIMIT ?;",params=list(artifact_id,last,as.integer(chunk_size)))
    if (!nrow(rows)) break
    state <- fold(as.character(rows$row_json))
    last <- max(as.integer(rows$row_idx))
  }
  state
}

.wb_prov_resolve_payload_location <- function(bundle, path, workspace = NULL,
                                              staging_bundle = NULL, kind = "payload", id = "") {
  raw <- as.character(path %||% "")[1]
  .wb_assert(nzchar(raw), paste0("Missing ", kind, " payload path", if (nzchar(id)) paste0(" for ", id) else ""))
  if (inherits(workspace, "wb_promotion_workspace")) {
    raw_norm <- normalizePath(raw, winslash = "/", mustWork = FALSE)
    for (rel in names(workspace$mappings)) {
      mapping <- workspace$mappings[[rel]]
      source <- normalizePath(as.character(mapping$source %||% "")[1], winslash = "/", mustWork = FALSE)
      final <- normalizePath(as.character(mapping$final %||% "")[1], winslash = "/", mustWork = FALSE)
      if (identical(raw, rel) || identical(raw_norm, source) || identical(raw_norm, final)) {
        pending <- as.character(mapping$pending %||% "")[1]
        .wb_assert(file.exists(pending) || dir.exists(pending), paste0(
          "Missing pending promotion payload for ", kind, if (nzchar(id)) paste0(" ", id) else "",
          ": attempted pending path ", pending
        ))
        return(pending)
      }
    }
  }
  if (.wb_path_is_absolute(raw)) {
    trusted_roots <- list()
    if (inherits(bundle, "scworkbench_bundle")) trusted_roots <- c(trusted_roots, list(bundle$dir))
    if (!is.null(staging_bundle) && inherits(staging_bundle,"scworkbench_bundle")) trusted_roots <- c(trusted_roots,list(staging_bundle$dir))
    if (inherits(workspace,"wb_promotion_workspace") && inherits(bundle,"scworkbench_bundle")) trusted_roots <- c(trusted_roots,list(bundle$dir))
    resolved <- normalizePath(raw,winslash="/",mustWork=FALSE)
    if (length(trusted_roots) && any(vapply(trusted_roots,function(root) .wb_path_inside(resolved,normalizePath(root,winslash="/",mustWork=TRUE)),logical(1))) && (file.exists(resolved)||dir.exists(resolved))) return(resolved)
    stop("PATH_ABSOLUTE: durable provenance payload paths must be bundle-relative.", call. = FALSE)
  }
  candidates <- list()
  if (!is.null(staging_bundle) && inherits(staging_bundle, "scworkbench_bundle")) candidates <- c(candidates, list(staging_bundle))
  if (inherits(bundle, "scworkbench_bundle")) candidates <- c(candidates, list(bundle))
  for (candidate_bundle in candidates) {
    status <- .wb_path_status(candidate_bundle$dir, raw, expected_type="either",
                              must_exist=TRUE, purpose=kind)
    if (isTRUE(status$ok)) return(status$absolute)
  }
  stop(paste0(
    "Missing ", kind, " payload for ", if (nzchar(id)) id else "<unknown>",
    "; lifecycle context=", if (inherits(workspace, "wb_promotion_workspace")) "promotion_workspace" else if (!is.null(staging_bundle)) "session_staging" else "durable_bundle",
    "; attempted contained bundle root(s): ", paste(vapply(candidates, function(x) x$dir, character(1)), collapse = ", ")
  ), call. = FALSE)
}

.wb_prov_file_tree_sha256 <- function(root) {
  .wb_assert(file.exists(root), paste0("Missing payload path for SHA-256: ", root))
  if (!dir.exists(root)) return(.wb_prov_sha256_file(root))
  root_abs <- normalizePath(root, winslash="/", mustWork=TRUE)
  entries <- sort(as.character(fs::dir_ls(root_abs, recurse=TRUE, type="any", all=TRUE, follow=FALSE)))
  resolved <- vapply(entries, normalizePath, character(1), winslash="/", mustWork=TRUE)
  .wb_assert(all(vapply(resolved, .wb_path_inside, logical(1), root=root_abs)),
             "PATH_SYMLINK_ESCAPE: payload tree contains an entry resolving outside its durable root.")
  files <- entries[!dir.exists(entries)]
  .wb_prov_sha256_object(lapply(files, function(f) list(
    path = substring(f, nchar(root_abs) + 2L), sha256 = .wb_prov_sha256_file(f)
  )))
}

.wb_prov_payload_identity <- function(bundle, prim, workspace = NULL, staging_bundle = NULL,
                                      graph_budgets = list()) {
  structural <- .wb_prov_structural_fingerprint(prim)
  if (!.wb_is_primitive(prim)) return(list(structural_fingerprint = structural, content_sha256 = NA_character_, content_identity_scheme = NA_character_, verification_level = "structural", verification_status = "unavailable"))
  kind <- as.character(prim$kind)[1]
  if (kind == "graph") {
    identity <- if (!is.null(prim$artifact_id)) {
      .wb_graph_retained_identities(bundle, prim$artifact_id, graph_budgets)
    } else if (!is.null(attr(prim, "graph_stage", exact = TRUE))) {
      state <- attr(prim, "graph_stage", exact = TRUE)
      .wb_graph_sql_identities(state$con, "staged", state$budgets)
    } else wb_graph_identity(prim)
    return(list(structural_fingerprint = structural,
      content_sha256 = identity$content_identity$sha256,
      content_identity_scheme = identity$content_identity$scheme,
      graph_binding_identity = identity$binding_identity,
      graph_descriptor_identity = identity$descriptor_identity,
      verification_level = "content", verification_status = "content_verified"))
  }
  if (kind %in% c("feature_table", "obs_table")) {
    return(list(structural_fingerprint = structural, content_sha256 = .wb_prov_table_content_sha256(prim), content_identity_scheme = unname(.wb_content_identity_schemes()[["table"]]), verification_level = "content", verification_status = "content_verified"))
  }
  if (kind %in% c("cell_vector", "cell_vector_family", "relation_family", "path_2d_family", "space_path_family")) {
    return(list(structural_fingerprint = structural, content_sha256 = .wb_prov_sha256_object(unclass(prim)), content_identity_scheme = unname(.wb_content_identity_schemes()[["object"]]), verification_level = "content", verification_status = "content_verified"))
  }
  if (kind == "matrix" && !is.null(bundle)) {
    frags <- tryCatch(wb_matrix_fragments(bundle, prim$matrix_id), error = function(e) data.frame())
    if (nrow(frags) && "path" %in% names(frags)) {
      rows <- lapply(seq_len(nrow(frags)), function(i) {
        rel <- as.character(frags$path[i]); abs <- .wb_prov_resolve_payload_location(bundle, rel, workspace = workspace, staging_bundle = staging_bundle, kind = "matrix fragment", id = as.character(prim$matrix_id)[1])
        # Physical fragment identifiers, paths, and creation times are
        # publication metadata, not matrix value identity. Keeping them in the
        # digest made a byte-identical replay fail solely because it ran in a
        # new session workspace.
        logical_columns <- intersect(
          c("matrix_id", "storage", "n_features", "n_cells",
            "feature_ids_json", "cell_ids_json", "source", "description"),
          names(frags)
        )
        list(
          fragment = as.list(frags[i, logical_columns, drop = FALSE]),
          payload_sha256 = .wb_prov_file_tree_sha256(abs)
        )
      })
      return(list(structural_fingerprint = structural, content_sha256 = .wb_prov_sha256_object(list(kind = kind, matrix_id = prim$matrix_id, fragments = rows)), content_identity_scheme = unname(.wb_content_identity_schemes()[["matrix"]]), verification_level = "content", verification_status = "content_verified"))
    }
  }
  if (kind %in% c("space", "space_2d") && !is.null(bundle)) {
    registry <- if (.wb_table_exists(bundle$con, "spaces")) {
      DBI::dbGetQuery(bundle$con, "SELECT * FROM spaces WHERE space_id = ?;", params = list(prim$space_id))
    } else data.frame()
    if (nrow(registry) == 1L && identical(as.character(registry$storage[[1L]]), .wb_space_payload_storage())) {
      payload <- .wb_space_payload_registry_row(bundle, prim$space_id)
      return(list(
        structural_fingerprint = structural,
        content_sha256 = as.character(payload$content_sha256[[1L]]),
        content_identity_scheme = as.character(payload$content_identity_scheme[[1L]]),
        registry_binding_sha256 = .wb_prov_sha256_object(list(
          space = as.list(registry[1L, , drop = FALSE]),
          payload = as.list(payload[1L, , drop = FALSE])
        )),
        verification_level = "content", verification_status = "content_verified"
      ))
    }
    tab <- if (kind == "space_2d" || .wb_table_exists(bundle$con, "space_2d")) {
      tryCatch(DBI::dbGetQuery(bundle$con, "SELECT * FROM space_2d WHERE space_id = ? ORDER BY cell_id;", params = list(prim$space_id)), error = function(e) data.frame())
    } else data.frame()
    if (!nrow(tab) && .wb_table_exists(bundle$con, "space_coords")) tab <- DBI::dbGetQuery(bundle$con, "SELECT * FROM space_coords WHERE space_id = ? ORDER BY cell_id, dim;", params = list(prim$space_id))
    if (nrow(registry) == 1L && nrow(tab)) return(list(structural_fingerprint = structural, content_sha256 = .wb_prov_sha256_object(list(kind = kind, space_id = prim$space_id, registry = registry, coordinates = tab)), content_identity_scheme = unname(.wb_content_identity_schemes()[["space"]]), verification_level = "content", verification_status = "content_verified"))
  }
  if (kind == "model_ref" && !is.null(bundle)) {
    rel <- as.character(prim$model_path %||% "")[1]
    if (!nzchar(rel) && .wb_table_exists(bundle$con, "space_models")) {
      row <- tryCatch(DBI::dbGetQuery(bundle$con, "SELECT model_path FROM space_models WHERE space_id = ? ORDER BY rowid DESC LIMIT 1;", params = list(as.character(prim$model_space_id %||% "")[1])), error = function(e) data.frame())
      if (nrow(row)) rel <- as.character(row$model_path[1] %||% "")[1]
    }
    if (nzchar(rel)) {
      abs <- .wb_prov_resolve_payload_location(bundle, rel, workspace = workspace, staging_bundle = staging_bundle, kind = "model reference", id = as.character(prim$model_space_id %||% "")[1])
      # Model payload integrity is the raw file/tree byte identity. Replay
      # equivalence is deliberately recorded and evaluated separately.
      path_identity <- .wb_prov_path_identity(abs)
      return(list(structural_fingerprint = structural, content_sha256 = path_identity$content_sha256, content_identity_scheme = path_identity$content_identity_scheme, verification_level = "content", verification_status = "content_verified"))
    }
  }
  list(structural_fingerprint = structural, content_sha256 = NA_character_, content_identity_scheme = NA_character_, verification_level = "structural", verification_status = "structural_only")
}

.wb_replay_model_loadable <- function(bundle, prim) {
  # This routine executes only inside explicit provenance replay verification;
  # it is not used by recipient validation. The replay runtime is the trusted
  # execution boundary, while containment remains mandatory below.
  if (!.wb_is_primitive(prim) || !identical(as.character(prim$kind), "model_ref")) {
    return(list(ok = FALSE, message = "Output is not a model_ref."))
  }
  engine <- as.character(prim$engine %||% "unknown")[1]
  path <- as.character(prim$model_path %||% "")[1]
  if (!nzchar(path) && identical(engine, "uwot")) {
    path <- tryCatch(wb_space_model_path(bundle, as.character(prim$model_space_id %||% prim$space_id %||% "")[1]), error = function(e) "")
  }
  status <- if (nzchar(path) && .wb_path_is_absolute(path)) {
    resolved <- normalizePath(path,winslash="/",mustWork=FALSE); root <- .wb_bundle_root(bundle)
    if (.wb_path_inside(resolved,root) && (file.exists(resolved)||dir.exists(resolved))) list(ok=TRUE,absolute=resolved) else list(ok=FALSE)
  } else if (nzchar(path)) .wb_path_status(bundle$dir, path, expected_type="either", must_exist=TRUE, purpose="replay model") else list(ok=FALSE)
  if (!isTRUE(status$ok)) return(list(ok = FALSE, message = "Model payload is missing or outside the bundle trust boundary."))
  path <- status$absolute
  if (!is.null(prim$model_tree_manifest)) {
    primary <- as.character(prim$model_primary_path %||%
      prim$model_tree_manifest$primary_path %||% "")[1]
    if (!.wb_operation_pack_v3_safe_model_entry(primary) ||
        !dir.exists(path)) return(list(ok = FALSE,
          message = "Contained model tree primary path is invalid."))
    path <- file.path(path, primary)
  }
  loaded <- tryCatch({
    if (identical(engine, "uwot")) {
      .wb_require_pkg("uwot", "UMAP replay-equivalence validation")
      uwot::load_uwot(path)
    } else {
      readRDS(path)
    }
  }, error = function(e) e)
  if (inherits(loaded, "error")) return(list(ok = FALSE, message = conditionMessage(loaded)))
  list(ok = TRUE, message = paste0("Loaded ", engine, " model reference successfully."))
}

.wb_prov_verify_replay_output <- function(bundle,
                                          original_run_id,
                                          original_output_name,
                                          expected_kind,
                                          expected_content_sha256,
                                          replay_equivalence_policy,
                                          expected_reference,
                                          replayed_prim,
                                          replay_run_id,
                                          replay_snapshot_id,
                                          replay_artifact_id = NA_character_,
                                          expected_content_identity_scheme = NA_character_,
                                          persist = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_migrate_provenance_tables(bundle$con)
  policy <- as.character(replay_equivalence_policy %||% "not_comparable")[1]
  .wb_assert(policy %in% .wb_replay_equivalence_policies(), paste0("Unknown replay-equivalence policy: ", policy))
  actual_kind <- if (.wb_is_primitive(replayed_prim)) as.character(replayed_prim$kind)[1] else "unknown"
  kind_ok <- identical(actual_kind, as.character(expected_kind)[1])
  actual_identity <- .wb_prov_payload_identity(bundle, replayed_prim)
  original_sha <- as.character(expected_content_sha256 %||% NA_character_)[1]
  replayed_sha <- as.character(actual_identity$content_sha256 %||% NA_character_)[1]
  original_scheme <- as.character(expected_content_identity_scheme %||% NA_character_)[1]
  replayed_scheme <- as.character(actual_identity$content_identity_scheme %||% NA_character_)[1]
  expected_ref <- as.character(expected_reference %||% NA_character_)[1]
  alignment_result <- if (identical(policy, "cell_aligned_embedding")) {
    .wb_replay_space_alignment_reference(bundle, replayed_prim)
  } else NULL
  replayed_ref <- if (identical(policy, "loadable_reference") && identical(actual_kind, "model_ref")) {
    .wb_replay_model_reference(replayed_prim)
  } else if (identical(policy, "exact_graph_descriptor") && identical(actual_kind, "graph")) {
    actual_identity$graph_descriptor_identity$sha256
  } else if (identical(policy, "cell_aligned_embedding")) {
    as.character(alignment_result$reference %||% NA_character_)[1]
  } else if (policy %in% c("exact_content", "exact_canonical_value")) {
    replayed_sha
  } else NA_character_
  payload_identical <- !is.na(original_sha) && nzchar(original_sha) &&
    !is.na(original_scheme) && nzchar(original_scheme) &&
    identical(original_scheme, replayed_scheme) && identical(original_sha, replayed_sha)

  load_result <- list(ok = TRUE, message = "")
  verified <- FALSE
  status <- "failed"
  message <- "Replay output did not satisfy its declared equivalence policy."
  if (identical(policy, "not_comparable")) {
    status <- "unsupported"
    message <- "Legacy or explicitly unsupported output has no replay-equivalence comparison."
  } else if (identical(policy, "exact_graph_descriptor")) {
    verified <- isTRUE(kind_ok) && identical(actual_kind, "graph") &&
      isTRUE(payload_identical) && !is.na(expected_ref) && nzchar(expected_ref) &&
      identical(expected_ref, replayed_ref)
    status <- if (verified) "verified" else "failed"
    message <- if (verified) "Exact graph content and binding descriptor matched." else "Graph descriptor mismatch."
  } else if (policy %in% c("exact_content", "exact_canonical_value")) {
    verified <- isTRUE(kind_ok) && isTRUE(payload_identical)
    status <- if (verified) "verified" else "failed"
    message <- if (verified) paste0(policy, " matched.") else paste0(policy, " mismatch.")
  } else if (identical(policy, "cell_aligned_embedding")) {
    ref_ok <- !is.na(expected_ref) && nzchar(expected_ref) && identical(expected_ref, replayed_ref)
    verified <- isTRUE(kind_ok) && isTRUE(ref_ok) && isTRUE(alignment_result$valid)
    status <- if (verified) "verified" else "failed"
    message <- if (verified) alignment_result$message else paste(
      c(if (!kind_ok) "Primitive kind mismatch." else NULL,
        if (!ref_ok) "Cell-aligned embedding reference mismatch." else NULL,
        if (!isTRUE(alignment_result$valid)) alignment_result$message else NULL),
      collapse = " "
    )
  } else if (identical(policy, "loadable_reference")) {
    load_prim <- replayed_prim
    replay_aid <- as.character(replay_artifact_id %||% "")[1]
    if ((!nzchar(replay_aid) || is.na(replay_aid)) && .wb_table_exists(bundle$con,"prov_run_outputs")) {
      lookup <- DBI::dbGetQuery(bundle$con,"SELECT artifact_id FROM prov_run_outputs WHERE snapshot_id=? AND run_id=? AND output_name=? AND artifact_id IS NOT NULL ORDER BY rowid DESC LIMIT 1;",params=list(as.character(replay_snapshot_id)[1],as.character(replay_run_id)[1],as.character(original_output_name)[1]))
      if (nrow(lookup)) replay_aid <- as.character(lookup$artifact_id[1] %||% "")[1]
    }
    if (nzchar(replay_aid) && !is.na(replay_aid)) {
      load_prim <- tryCatch(wb_art_load(bundle,replay_aid,expected_kind="model_ref"),error=function(e) replayed_prim)
    }
    load_result <- .wb_replay_model_loadable(bundle, load_prim)
    ref_ok <- !is.na(expected_ref) && nzchar(expected_ref) && identical(expected_ref, replayed_ref)
    verified <- isTRUE(kind_ok) && isTRUE(ref_ok) && isTRUE(load_result$ok)
    status <- if (verified) "verified" else "failed"
    message <- if (verified) load_result$message else paste(
      c(if (!kind_ok) "Primitive kind mismatch." else NULL,
        if (!ref_ok) "Canonical model reference mismatch." else NULL,
        if (!isTRUE(load_result$ok)) load_result$message else NULL),
      collapse = " "
    )
  }

  row <- data.frame(
    result_id = .wb_allocate_db_identifier(
      bundle$con, "prov_replay_equivalence_results", "result_id",
      paste0("replayeq_", format(Sys.time(), "%Y%m%d%H%M%OS6"), "_"),
      n = 8L, purpose = "replay-equivalence result"
    ),
    original_run_id = as.character(original_run_id)[1],
    original_output_name = as.character(original_output_name)[1],
    replay_run_id = as.character(replay_run_id)[1],
    replay_snapshot_id = as.character(replay_snapshot_id)[1],
    replay_artifact_id = as.character(replay_artifact_id %||% NA_character_)[1],
    primitive_kind = actual_kind,
    replay_equivalence_policy = policy,
    original_content_sha256 = original_sha,
    replayed_content_sha256 = replayed_sha,
    original_content_identity_scheme = original_scheme,
    replayed_content_identity_scheme = replayed_scheme,
    expected_reference = expected_ref,
    replayed_reference = replayed_ref,
    payload_identical = as.integer(isTRUE(payload_identical)),
    equivalence_verified = as.integer(isTRUE(verified)),
    verification_status = status,
    verification_message = message,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE
  )
  if (isTRUE(persist)) {
    .wb_db_append_chunked(bundle$con, "prov_replay_equivalence_results", row, chunk_size = 1L)
  }
  if (identical(status, "failed")) stop(message, call. = FALSE)
  row
}

#' List Replay-Equivalence Verification Results
#'
#' Returns target-reproduction comparisons. Raw payload SHA-256 identities are
#' retained alongside the independently declared scientific equivalence policy.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param replay_snapshot_id Optional replay snapshot filter.
#' @return A data frame with one row per verified replay output.
#' @export
wb_prov_replay_equivalence_results <- function(bundle, replay_snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_observational_schema(
    bundle, "prov_replay_equivalence_results",
    action = "replay-equivalence result inspection"
  )
  if (is.null(replay_snapshot_id)) {
    return(DBI::dbGetQuery(bundle$con, "SELECT * FROM prov_replay_equivalence_results ORDER BY created_at, result_id;"))
  }
  DBI::dbGetQuery(
    bundle$con,
    "SELECT * FROM prov_replay_equivalence_results WHERE replay_snapshot_id = ? ORDER BY created_at, result_id;",
    params = list(as.character(replay_snapshot_id)[1])
  )
}

.wb_prov_source_identity_validate <- function(x) {
  if (is.null(x)) return(NULL)
  .wb_assert(is.list(x), "source_identity must be a named list")
  .wb_assert(!is.null(names(x)) && all(nzchar(names(x))), "source_identity fields must be named")
  if (!is.null(x$inputs)) {
    .wb_assert(is.list(x$inputs), "source_identity$inputs must be a list")
    x$inputs <- lapply(x$inputs, function(input) {
      .wb_assert(is.list(input) && !is.null(names(input)), "each source_identity$inputs entry must be a named list")
      .wb_assert(any(nzchar(as.character(input$path %||% input$uri %||% input$accession %||% "")[1])),
                 "each source input requires path, uri, or accession")
      input
    })
    if (any(vapply(x$inputs, function(input) !is.null(input$scope) || !is.null(input$source_scope), logical(1)))) {
      x <- wb_source_preflight(x, verify_files = FALSE, strict = TRUE)$source_identity
    }
  }
  x
}

.wb_prov_record_source_inputs <- function(bundle, snapshot_id, run_id, source_identity) {
  inputs <- source_identity$inputs %||% list()
  if (!length(inputs)) return(invisible(FALSE))
  con <- bundle$con
  commit <- DBI::dbGetQuery(con, "SELECT commit_id FROM prov_heads WHERE snapshot_id = ?;", params = list(snapshot_id))$commit_id
  for (i in seq_along(inputs)) {
    input <- inputs[[i]]
    scope <- as.character(input$scope %||% input$source_scope %||% "legacy_external")[1]
    if (identical(scope, "internal_assembly")) next
    canonical <- jsonlite::toJSON(.wb_json_sanitize(input), auto_unbox = TRUE, null = "null")
    source_id <- as.character(input$source_id %||% .wb_identifier_sha256(canonical, "source"))[1]
    checksum <- as.character(input$checksum %||% NA_character_)[1]
    status <- if (identical(scope, "in_memory")) "nonportable_in_memory" else if (nzchar(checksum) && !is.na(checksum)) "checksummed" else "declared_no_checksum"
    old <- DBI::dbGetQuery(con, "SELECT source_json FROM prov_source_inputs WHERE snapshot_id=? AND run_id=? AND source_id=?;", params=list(snapshot_id, run_id, source_id))
    if (!nrow(old)) DBI::dbExecute(con, "INSERT INTO prov_source_inputs(snapshot_id, run_id, source_id, source_json, checksum_status) VALUES(?, ?, ?, ?, ?);", params=list(snapshot_id, run_id, source_id, canonical, status))
    else if (!identical(as.character(old$source_json[1]), as.character(canonical))) stop(paste0("Conflicting immutable external source input: ", source_id), call.=FALSE)
    entity_kind <- if (identical(scope, "in_memory")) "in_memory_source" else "external_source"
    .wb_prov_insert_entity_binding(con, snapshot_id, as.character(commit[1] %||% NA_character_), run_id,
      "input", paste0(scope, ".", i), entity_kind, source_id, "CONSUMES",
      path=as.character(input$uri %||% input$path %||% input$accession %||% NA_character_)[1], content_hash=checksum,
      content_identity_scheme=if (!is.na(checksum) && grepl("^[A-Fa-f0-9]{64}$", checksum)) unname(.wb_content_identity_schemes()[["raw_file"]]) else NA_character_,
      source="declared_ingestion_input")
  }
  invisible(TRUE)
}

.wb_prov_record_source_identity <- function(bundle, snapshot_id, run_id, matrix_ids, source_identity) {
  source_identity <- .wb_prov_source_identity_validate(source_identity)
  if (is.null(source_identity)) return(invisible(FALSE))
  .wb_require_pkg("jsonlite", "source identity provenance")
  matrix_ids <- unique(as.character(matrix_ids %||% character(0)))
  canonical_json <- jsonlite::toJSON(.wb_json_sanitize(source_identity), auto_unbox = TRUE, null = "null")
  for (matrix_id in matrix_ids[nzchar(matrix_ids)]) {
    existing <- DBI::dbGetQuery(
      bundle$con,
      "SELECT source_identity_json FROM prov_source_identities WHERE snapshot_id = ? AND run_id = ? AND matrix_id = ?;",
      params = list(snapshot_id, run_id, matrix_id)
    )
    if (!nrow(existing)) {
      DBI::dbExecute(
        bundle$con,
        "INSERT INTO prov_source_identities(snapshot_id, run_id, matrix_id, source_identity_json) VALUES(?, ?, ?, ?);",
        params = list(snapshot_id, run_id, matrix_id, canonical_json)
      )
    } else if (!identical(as.character(existing$source_identity_json[1]), as.character(canonical_json))) {
      stop(paste0("Conflicting immutable source identity for snapshot_id=", snapshot_id,
                  ", run_id=", run_id, ", matrix_id=", matrix_id), call. = FALSE)
    }
  }
  invisible(TRUE)
}

.wb_prov_runtime_fingerprint <- function(op_name, operation_pack_runtime = NULL) {
  loaded <- sort(loadedNamespaces())
  package_versions <- vapply(loaded, function(pkg) {
    tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NA_character_)
  }, character(1))
  image_sha <- Sys.getenv("SCWORKBENCH_RUNTIME_IMAGE_SHA256", unset = "")
  out <- list(
    schema = "scworkbench.runtime_attestation.v1",
    r_version = R.version.string,
    platform = R.version$platform,
    scworkbench_version = as.character(utils::packageVersion("scworkbench")),
    operation = list(name = as.character(op_name)[1], version = "1"),
    namespaces = as.list(package_versions),
    bpcells = list(
      version = if (requireNamespace("BPCells", quietly = TRUE)) as.character(utils::packageVersion("BPCells")) else NA_character_,
      native_provenance = tryCatch(as.character(utils::packageDescription("BPCells")$RemoteSha %||% NA_character_), error = function(e) NA_character_)
    ),
    image = if (nzchar(image_sha)) list(status = "bound", sha256 = image_sha) else list(status = "unavailable", sha256 = NA_character_),
    runtime_provenance = list(
      source_revision = Sys.getenv("SCWORKBENCH_SOURCE_REVISION", unset = NA_character_),
      container_digest = Sys.getenv("SCWORKBENCH_CONTAINER_DIGEST", unset = NA_character_)
    )
  )
  pack <- .wb_operation_pack_identity_for_op(op_name)
  if (!is.null(pack)) {
    out$operation_pack <- pack
    rec <- .wb_operation_pack_registry$packs[[pack$namespace]]
    out$operation_pack_runtime <- operation_pack_runtime %||%
      rec$runtime_attestation %||% list(status = "unavailable")
  }
  out
}

.wb_prov_current_contract_interface <- function(op_name) {
  op_name <- as.character(op_name)[1]
  op <- .wb_operation_catalog()[[op_name]] %||% list()
  out <- list(
    op_name = op_name,
    title = op$title %||% NA_character_, description = op$description %||% NA_character_,
    inputs = op$inputs %||% list(), params = op$params %||% list(),
    produces = .wb_op_interface_registry()[[op_name]]$produces %||% op$interface_produces %||% op$produces %||% list(),
    promotion_terminals = as.character(op$promotable %||% character(0)),
    semantics = op$semantics %||% list()
  )
  if (!is.null(op$source_pack)) {
    out$source_pack <- op$source_pack
    out$operation_definition_sha256 <- as.character(op$definition_sha256 %||%
      op$source_pack$operation_definition_sha256[[op_name]] %||% NA_character_)[1]
  }
  out
}

.wb_prov_contract_interface_identity <- function(x) {
  normalized <- jsonlite::fromJSON(
    jsonlite::toJSON(.wb_json_sanitize(x), auto_unbox = TRUE, null = "null"),
    simplifyVector = TRUE, simplifyDataFrame = FALSE
  )
  .wb_prov_sha256_object(normalized)
}

.wb_prov_operation_contract_incompatibility <- function(recorded_interface,
                                                         current_interface,
                                                         op_name) {
  if (identical(.wb_prov_contract_interface_identity(recorded_interface),
                .wb_prov_contract_interface_identity(current_interface))) {
    return(NULL)
  }
  .wb_prov_replay_diagnostic(
    "OPERATION_CONTRACT_INCOMPATIBLE",
    paste0("Installed contract for '", as.character(op_name)[1],
           "' differs from the recorded contract."),
    "Use the recorded scworkbench release or explicitly reconstruct inputs against the installed interface."
  )
}

.wb_prov_contract_snapshot <- function(run) {
  op_name <- as.character(run$op_name)[1]
  interface <- .wb_prov_current_contract_interface(op_name)
  list(version = "1", interface = interface,
       resolved_inputs = run$inputs$execution_inputs %||% list(),
       parameters = run$params %||% list())
}

.wb_prov_insert_entity_binding <- function(con, snapshot_id, commit_id, run_id,
                                           direction, binding_name, entity_kind,
                                           entity_id, relationship_type, path = NA_character_,
                                           content_hash = NA_character_,
                                           content_identity_scheme = NA_character_, source,
                                           resolution_json = NA_character_,
                                           source_membership_sha256 = NA_character_,
                                           source_membership_identity_scheme = NA_character_,
                                           source_member_count = NA_integer_,
                                           effective_membership_sha256 = NA_character_,
                                           effective_membership_identity_scheme = NA_character_,
                                           effective_member_count = NA_integer_) {
  bind_lifecycle <- TRUE
  if (identical(direction, "input") && identical(entity_kind, "in_memory_source")) bind_lifecycle <- FALSE
  if (identical(direction,"input") && identical(entity_kind,"model_ref")) {
    bits <- strsplit(as.character(entity_id),"|",fixed=TRUE)[[1]]
    bind_lifecycle <- length(bits)>=2L && .wb_table_exists(con,"space_models") &&
      nrow(DBI::dbGetQuery(con,"SELECT 1 FROM space_models WHERE space_id=? LIMIT 1;",params=list(bits[2])))==1L
  }
  if (bind_lifecycle) .wb_entity_bind_provenance(
    con = con,
    entity_kind = entity_kind,
    entity_id = entity_id,
    identity_hash = content_hash,
    identity_scheme = content_identity_scheme
  )
  DBI::dbExecute(
    con,
    "INSERT OR IGNORE INTO prov_run_entity_bindings(snapshot_id, commit_id, run_id, direction, binding_name, entity_kind, entity_id, relationship_type, path, content_hash, content_identity_scheme, source, resolution_json, source_membership_sha256, source_membership_identity_scheme, source_member_count, effective_membership_sha256, effective_membership_identity_scheme, effective_member_count) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    params = list(snapshot_id, commit_id %||% NA_character_, run_id, direction,
                  binding_name, entity_kind, entity_id, relationship_type,
                  path, content_hash, content_identity_scheme, source,
                  resolution_json, source_membership_sha256,
                  source_membership_identity_scheme, source_member_count,
                  effective_membership_sha256,
                  effective_membership_identity_scheme, effective_member_count)
  )
}

.wb_prov_record_ingestion <- function(bundle, run, artifact_id = NA_character_,
                                      matrix_ids = character(0), created_by = NULL,
                                      transaction_open = FALSE, source_identity = NULL,
                                      authoritative_entity_outputs = TRUE,
                                      metadata_fields = NULL) {
  .wb_assert(wb_is_run(run), "run must be a wb_run")
  matrix_ids <- unique(as.character(matrix_ids %||% character(0)))
  matrix_ids <- matrix_ids[nzchar(matrix_ids)]
  matrix_outputs <- if (isTRUE(authoritative_entity_outputs) && length(matrix_ids)) {
    stats::setNames(lapply(matrix_ids, wb_prim_matrix), paste0("matrix_", matrix_ids))
  } else list()
  run$outputs <- c(run$outputs %||% list(), matrix_outputs)
  promoted <- data.frame(
    run_id = as.character(run$run_id),
    output = "ingest_report",
    artifact_id = as.character(artifact_id %||% NA_character_)[1],
    status = if (nzchar(as.character(artifact_id %||% "")[1])) "ok" else "skipped",
    stringsAsFactors = FALSE
  )
  sid <- .wb_prov_write_snapshot(
    bundle = bundle, runs = stats::setNames(list(run), run$run_id), topo = run$run_id,
    heads = run$run_id, promoted_df = promoted, name_prefix = "ingestion",
    description = "Durable ingestion entity bindings", created_by = created_by,
    transaction_open = transaction_open
  )
  if (isTRUE(authoritative_entity_outputs)) {
    .wb_prov_record_source_identity(bundle, sid, run$run_id, matrix_ids, source_identity)
  }
  .wb_prov_record_source_inputs(bundle, sid, run$run_id, source_identity %||% list())
  if (!is.null(metadata_fields) && nrow(metadata_fields)) {
    .wb_metadata_identity_bind_producer(
      bundle$con, metadata_fields, sid, run$run_id,
      DBI::dbGetQuery(bundle$con, "SELECT commit_id FROM prov_heads WHERE snapshot_id=?;",
                      params = list(sid))$commit_id[[1L]],
      source = "declared_ingestion"
    )
  }
  sid
}

.wb_prov_link_source_to_existing_producers <- function(bundle, matrix_ids, space_ids,
                                                        source_identity,
                                                        artifact_ids = character(0),
                                                        metadata_field_ids = character(0)) {
  entity_rows <- function(kind, ids) {
    ids <- unique(as.character(ids %||% character()))
    data.frame(entity_kind = rep(kind, length(ids)), entity_id = ids, stringsAsFactors = FALSE)
  }
  entities <- rbind(
    entity_rows("matrix", matrix_ids),
    entity_rows("space", space_ids),
    entity_rows("artifact", artifact_ids),
    entity_rows("metadata_field", metadata_field_ids)
  )
  entities <- entities[!is.na(entities$entity_id) & nzchar(entities$entity_id), , drop = FALSE]
  if (!nrow(entities) || is.null(source_identity)) return(invisible(FALSE))
  producers <- do.call(rbind, lapply(seq_len(nrow(entities)), function(i) {
    rows <- DBI::dbGetQuery(
      bundle$con,
      "SELECT snapshot_id,run_id FROM prov_run_entity_bindings
       WHERE entity_kind=? AND entity_id=? AND relationship_type IN ('PRODUCES','MATERIALIZES')
       ORDER BY snapshot_id,run_id;",
      params = unname(as.list(entities[i, c("entity_kind", "entity_id")]))
    )
    if (nrow(rows)) cbind(rows, entities[rep(i, nrow(rows)), , drop = FALSE]) else NULL
  }))
  if (is.null(producers) || !nrow(producers)) return(invisible(FALSE))
  normalized_identity <- .wb_prov_source_identity_validate(source_identity)
  incoming_json <- jsonlite::toJSON(.wb_json_sanitize(normalized_identity), auto_unbox = TRUE, null = "null")
  matrix_producers <- producers[as.character(producers$entity_kind) == "matrix", , drop = FALSE]
  if (nrow(matrix_producers)) for (i in seq_len(nrow(matrix_producers))) {
    existing <- DBI::dbGetQuery(
      bundle$con,
      "SELECT source_identity_json FROM prov_source_identities WHERE snapshot_id=? AND run_id=? AND matrix_id=?;",
      params = unname(as.list(matrix_producers[i, c("snapshot_id", "run_id", "entity_id")]))
    )
    if (!nrow(existing) || identical(as.character(existing$source_identity_json[[1L]]), as.character(incoming_json))) next
    parsed <- tryCatch(jsonlite::fromJSON(existing$source_identity_json[[1L]], simplifyVector = FALSE), error = function(e) NULL)
    inputs <- parsed$inputs %||% list()
    replaceable <- length(inputs) > 0L && all(vapply(inputs, function(x) {
      identical(as.character(x$scope %||% x$source_scope %||% ""), "internal_assembly")
    }, logical(1)))
    if (!isTRUE(replaceable)) stop(
      paste0("Conflicting immutable source identity for snapshot_id=", matrix_producers$snapshot_id[[i]],
             ", run_id=", matrix_producers$run_id[[i]], ", matrix_id=", matrix_producers$entity_id[[i]]),
      call. = FALSE
    )
  }
  for (i in seq_len(nrow(producers))) {
    sid <- as.character(producers$snapshot_id[[i]])
    rid <- as.character(producers$run_id[[i]])
    .wb_prov_record_source_inputs(bundle, sid, rid, source_identity)
    if (identical(as.character(producers$entity_kind[[i]]), "matrix")) {
      mid <- as.character(producers$entity_id[[i]])
      existing <- DBI::dbGetQuery(
        bundle$con,
        "SELECT source_identity_json FROM prov_source_identities WHERE snapshot_id=? AND run_id=? AND matrix_id=?;",
        params = list(sid, rid, mid)
      )
      if (nrow(existing)) {
        parsed <- tryCatch(jsonlite::fromJSON(existing$source_identity_json[[1L]], simplifyVector = FALSE), error = function(e) NULL)
        inputs <- parsed$inputs %||% list()
        replaceable <- length(inputs) > 0L && all(vapply(inputs, function(x) {
          identical(as.character(x$scope %||% x$source_scope %||% ""), "internal_assembly")
        }, logical(1)))
        if (isTRUE(replaceable)) DBI::dbExecute(
          bundle$con,
          "DELETE FROM prov_source_identities WHERE snapshot_id=? AND run_id=? AND matrix_id=?;",
          params = list(sid, rid, mid)
        )
      }
      .wb_prov_record_source_identity(bundle, sid, rid, mid, source_identity)
    }
  }
  invisible(TRUE)
}

.wb_prov_record_ingestion_substep <- function(bundle, run, artifact_id, created_by = NULL) {
  .wb_assert(wb_is_run(run), "run must be a wb_run")
  .wb_prov_write_snapshot(
    bundle = bundle, runs = stats::setNames(list(run), run$run_id), topo = run$run_id,
    heads = run$run_id,
    promoted_df = data.frame(run_id = run$run_id, output = "feature_metadata",
      artifact_id = artifact_id, status = "ok", stringsAsFactors = FALSE),
    name_prefix = "ingestion", description = "Ingestion feature metadata substep",
    created_by = created_by
  )
}

.wb_migrate_provenance_tables <- function(con) {
  if (isTRUE(attr(con, "scworkbench_read_only"))) return(invisible(FALSE))
  status <- .wb_schema_status(con)
  if (identical(status$status, "current")) return(invisible(TRUE))
  bundle_dir <- .wb_bundle_dir_from_connection(con)
  .wb_with_bundle_writer_lock(bundle_dir, operation = "provenance schema migration", code = {
    .wb_schema_migrate_connection(con, bundle_dir = bundle_dir, backup = TRUE)
  })
}

.wb_migrate_provenance_tables_locked <- function(con) {
  if (isTRUE(attr(con, "scworkbench_read_only"))) return(invisible(FALSE))
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_heads (
      snapshot_id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL,
      created_by TEXT,
      name_prefix TEXT,
      description TEXT,
      schema_version TEXT,
      head_run_ids_json TEXT NOT NULL,
      n_runs INTEGER NOT NULL,
      n_artifacts INTEGER NOT NULL
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_heads_created_at ON prov_heads(created_at);")
  if (!.wb_db_has_column(con, "prov_heads", "schema_version")) {
    DBI::dbExecute(con, "ALTER TABLE prov_heads ADD COLUMN schema_version TEXT;")
    DBI::dbExecute(con, "UPDATE prov_heads SET schema_version = ? WHERE schema_version IS NULL OR schema_version = '';", params = list(.wb_prov_schema_version()))
  }
  if (!.wb_db_has_column(con, "prov_heads", "commit_id")) {
    DBI::dbExecute(con, "ALTER TABLE prov_heads ADD COLUMN commit_id TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_heads", "replay_status")) {
    DBI::dbExecute(con, "ALTER TABLE prov_heads ADD COLUMN replay_status TEXT;")
  }

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_commits (
      commit_id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL,
      created_by TEXT,
      state TEXT NOT NULL,
      selected_outputs_json TEXT NOT NULL,
      runtime_fingerprint_json TEXT NOT NULL,
      error_message TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_runs (
      snapshot_id TEXT NOT NULL,
      run_id TEXT NOT NULL,
      op_name TEXT NOT NULL,
      created_at TEXT,
      notes TEXT,
      params_json TEXT NOT NULL,
      inputs_json TEXT NOT NULL,
      symbolic_inputs_json TEXT,
      execution_inputs_json TEXT,
      run_hash TEXT NOT NULL,
      PRIMARY KEY(snapshot_id, run_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_runs_snapshot ON prov_runs(snapshot_id);")
  if (!.wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")) {
    DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN symbolic_inputs_json TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_runs", "execution_inputs_json")) {
    DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN execution_inputs_json TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_runs", "op_version")) {
    DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN op_version TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_runs", "runtime_fingerprint_json")) {
    DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN runtime_fingerprint_json TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_runs", "contract_json")) DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN contract_json TEXT;")
  if (!.wb_db_has_column(con, "prov_runs", "contract_hash")) DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN contract_hash TEXT;")
  if (!.wb_db_has_column(con, "prov_runs", "run_hash_scheme")) DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN run_hash_scheme TEXT;")
  if (!.wb_db_has_column(con, "prov_runs", "contract_hash_scheme")) DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN contract_hash_scheme TEXT;")
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS prov_source_identities (snapshot_id TEXT NOT NULL, run_id TEXT NOT NULL, matrix_id TEXT NOT NULL, source_identity_json TEXT NOT NULL, PRIMARY KEY(snapshot_id, run_id, matrix_id));")
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS prov_source_inputs (snapshot_id TEXT NOT NULL, run_id TEXT NOT NULL, source_id TEXT NOT NULL, source_json TEXT NOT NULL, checksum_status TEXT NOT NULL, PRIMARY KEY(snapshot_id, run_id, source_id));")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_run_edges (
      snapshot_id TEXT NOT NULL,
      parent_run_id TEXT NOT NULL,
      child_run_id TEXT NOT NULL,
      edge_type TEXT NOT NULL,
      edge_label TEXT,
      PRIMARY KEY(snapshot_id, parent_run_id, child_run_id, edge_type, edge_label)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_edges_snapshot ON prov_run_edges(snapshot_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_run_outputs (
      snapshot_id TEXT NOT NULL,
      run_id TEXT NOT NULL,
      output_name TEXT NOT NULL,
      primitive_kind TEXT NOT NULL,
      output_hash TEXT NOT NULL,
      artifact_id TEXT,
      PRIMARY KEY(snapshot_id, run_id, output_name)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_outputs_snapshot ON prov_run_outputs(snapshot_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_outputs_artifact ON prov_run_outputs(artifact_id);")
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS prov_run_entity_bindings (snapshot_id TEXT NOT NULL, commit_id TEXT, run_id TEXT NOT NULL, direction TEXT NOT NULL, binding_name TEXT NOT NULL, entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL, relationship_type TEXT NOT NULL, path TEXT, content_hash TEXT, source TEXT NOT NULL, PRIMARY KEY(snapshot_id, run_id, direction, binding_name, entity_kind, entity_id, relationship_type));")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_entity_bindings_snapshot ON prov_run_entity_bindings(snapshot_id, run_id);")
  if (!.wb_db_has_column(con, "prov_run_entity_bindings", "content_identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_entity_bindings ADD COLUMN content_identity_scheme TEXT;")
  }
  cell_set_binding_columns <- c(
    resolution_json = "TEXT",
    source_membership_sha256 = "TEXT",
    source_membership_identity_scheme = "TEXT",
    source_member_count = "INTEGER",
    effective_membership_sha256 = "TEXT",
    effective_membership_identity_scheme = "TEXT",
    effective_member_count = "INTEGER"
  )
  for (column in names(cell_set_binding_columns)) {
    if (!.wb_db_has_column(con, "prov_run_entity_bindings", column)) {
      DBI::dbExecute(con, paste0(
        "ALTER TABLE prov_run_entity_bindings ADD COLUMN ", column, " ",
        unname(cell_set_binding_columns[[column]]), ";"
      ))
    }
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "materialization_class")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN materialization_class TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "materialization_path")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN materialization_path TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "structural_fingerprint")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN structural_fingerprint TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "output_hash_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN output_hash_scheme TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "structural_fingerprint_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN structural_fingerprint_scheme TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "content_sha256")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN content_sha256 TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "verification_level")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN verification_level TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "verification_status")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN verification_status TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "content_identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN content_identity_scheme TEXT;")
  }
  DBI::dbExecute(con, "UPDATE prov_run_outputs SET verification_level = 'structural', verification_status = 'legacy_structural_only' WHERE verification_level IS NULL OR verification_level = '';")
  if (!.wb_db_has_column(con, "prov_run_outputs", "replay_equivalence_policy")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN replay_equivalence_policy TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "replay_equivalence_reference")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN replay_equivalence_reference TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_run_outputs", "replay_equivalence_status")) {
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN replay_equivalence_status TEXT;")
  }
  DBI::dbExecute(con, "UPDATE prov_run_outputs SET replay_equivalence_policy = 'not_comparable', replay_equivalence_status = 'legacy_not_comparable' WHERE replay_equivalence_policy IS NULL OR replay_equivalence_policy = '';")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_replay_equivalence_results (
      result_id TEXT PRIMARY KEY,
      original_run_id TEXT NOT NULL,
      original_output_name TEXT NOT NULL,
      replay_run_id TEXT NOT NULL,
      replay_snapshot_id TEXT NOT NULL,
      replay_artifact_id TEXT,
      primitive_kind TEXT NOT NULL,
      replay_equivalence_policy TEXT NOT NULL,
      original_content_sha256 TEXT,
      replayed_content_sha256 TEXT,
      original_content_identity_scheme TEXT,
      replayed_content_identity_scheme TEXT,
      expected_reference TEXT,
      replayed_reference TEXT,
      payload_identical INTEGER NOT NULL,
      equivalence_verified INTEGER NOT NULL,
      verification_status TEXT NOT NULL,
      verification_message TEXT,
      created_at TEXT NOT NULL
    );
  ")
  if (!.wb_db_has_column(con, "prov_replay_equivalence_results", "original_content_identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_replay_equivalence_results ADD COLUMN original_content_identity_scheme TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_replay_equivalence_results", "replayed_content_identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_replay_equivalence_results ADD COLUMN replayed_content_identity_scheme TEXT;")
  }
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_replay_results_snapshot ON prov_replay_equivalence_results(replay_snapshot_id);")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_materializations (
      commit_id TEXT NOT NULL,
      run_id TEXT NOT NULL,
      output_name TEXT NOT NULL,
      primitive_kind TEXT NOT NULL,
      path TEXT NOT NULL,
      output_hash TEXT NOT NULL,
      PRIMARY KEY(commit_id, run_id, output_name)
    );
  ")
  if (!.wb_db_has_column(con, "prov_materializations", "content_sha256")) DBI::dbExecute(con, "ALTER TABLE prov_materializations ADD COLUMN content_sha256 TEXT;")
  if (!.wb_db_has_column(con, "prov_materializations", "content_identity_scheme")) DBI::dbExecute(con, "ALTER TABLE prov_materializations ADD COLUMN content_identity_scheme TEXT;")
  if (!.wb_db_has_column(con, "prov_materializations", "output_hash_scheme")) DBI::dbExecute(con, "ALTER TABLE prov_materializations ADD COLUMN output_hash_scheme TEXT;")

  invisible(TRUE)
}

.wb_migrate_provenance_identity_schemes_locked <- function(con) {
  .wb_migrate_provenance_tables_locked(con)
  legacy <- unname(.wb_identity_schemes()[["legacy"]])
  DBI::dbExecute(con, "UPDATE prov_runs SET run_hash_scheme=? WHERE run_hash_scheme IS NULL OR run_hash_scheme='';", params=list(legacy))
  DBI::dbExecute(con, "UPDATE prov_runs SET contract_hash_scheme=? WHERE contract_hash IS NOT NULL AND contract_hash<>'' AND (contract_hash_scheme IS NULL OR contract_hash_scheme='');", params=list(legacy))
  DBI::dbExecute(con, "UPDATE prov_run_outputs SET output_hash_scheme=? WHERE output_hash_scheme IS NULL OR output_hash_scheme='';", params=list(legacy))
  DBI::dbExecute(con, "UPDATE prov_run_outputs SET structural_fingerprint_scheme=? WHERE structural_fingerprint IS NOT NULL AND structural_fingerprint<>'' AND (structural_fingerprint_scheme IS NULL OR structural_fingerprint_scheme='');", params=list(legacy))
  DBI::dbExecute(con, "UPDATE prov_materializations SET output_hash_scheme=? WHERE output_hash_scheme IS NULL OR output_hash_scheme='';", params=list(legacy))
  invisible(TRUE)
}

.wb_prov_write_snapshot <- function(bundle,
                                    runs,
                                    topo,
                                    heads,
                                    promoted_df,
                                    name_prefix = NULL,
                                    description = NULL,
                                    created_by = NULL,
                                    commit_id = NULL,
                                    materializations = NULL,
                                    runtime_fingerprint = NULL,
                                    workspace = NULL,
                                    staging_bundle = NULL,
                                    transaction_open = FALSE) {
  .wb_require_pkg("jsonlite", "provenance snapshot write")
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  sid <- .wb_prov_new_snapshot_id(con)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  head_json <- jsonlite::toJSON(as.character(heads), auto_unbox = FALSE, null = "null")
  n_artifacts <- sum(
    !is.na(promoted_df$artifact_id %||% NA_character_) &
      nzchar(as.character(promoted_df$artifact_id %||% ""))
  )

  artifact_map <- list()
  ok <- promoted_df[
    as.character(promoted_df$status %||% "") == "ok" &
      !is.na(promoted_df$output %||% NA_character_) &
      !is.na(promoted_df$artifact_id %||% NA_character_),
    ,
    drop = FALSE
  ]
  if (nrow(ok)) {
    for (i in seq_len(nrow(ok))) {
      k <- paste0(as.character(ok$run_id[i]), "::", as.character(ok$output[i]))
      artifact_map[[k]] <- as.character(ok$artifact_id[i])
    }
  }

  write_snapshot <- function() {
    DBI::dbExecute(
      con,
      "INSERT INTO prov_heads(snapshot_id, created_at, created_by, name_prefix, description, schema_version, head_run_ids_json, n_runs, n_artifacts, commit_id, replay_status)
       VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
      params = list(
        sid, created_at, created_by %||% NA_character_, name_prefix %||% NA_character_,
        description %||% NA_character_, .wb_prov_schema_version(),
        as.character(head_json), as.integer(length(topo)), as.integer(n_artifacts),
        as.character(commit_id %||% NA_character_),
        if (is.null(runtime_fingerprint)) "inspectable_only" else "replayable"
      )
    )

    for (rid in topo) {
      run <- runs[[rid]]
      if (is.null(run) || !wb_is_run(run)) next

      params_json <- jsonlite::toJSON(.wb_json_sanitize(run$params %||% list()), auto_unbox = TRUE, null = "null")
      inputs_json <- jsonlite::toJSON(.wb_json_sanitize(run$inputs %||% list()), auto_unbox = TRUE, null = "null")
      symbolic_inputs <- run$inputs$symbolic_inputs %||% run$inputs$user_inputs %||% list()
      execution_inputs <- run$inputs$execution_inputs %||% list(
        effective_n = run$inputs$effective_n %||% NA_integer_,
        resolved = list()
      )
      symbolic_inputs_json <- jsonlite::toJSON(.wb_json_sanitize(symbolic_inputs), auto_unbox = TRUE, null = "null")
      execution_inputs_json <- jsonlite::toJSON(.wb_json_sanitize(execution_inputs), auto_unbox = TRUE, null = "null")
      run_hash <- .wb_prov_run_hash(run$op_name, params_json, inputs_json, symbolic_inputs_json, execution_inputs_json)
      contract_run <- run
      contract_run$inputs$execution_inputs <- execution_inputs
      contract_json <- jsonlite::toJSON(.wb_json_sanitize(.wb_prov_contract_snapshot(contract_run)), auto_unbox = TRUE, null = "null")

      DBI::dbExecute(
        con,
        "INSERT INTO prov_runs(snapshot_id, run_id, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json, execution_inputs_json, run_hash, op_version, runtime_fingerprint_json, contract_json, contract_hash, run_hash_scheme, contract_hash_scheme)
         VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
        params = list(
          sid,
          as.character(run$run_id),
          as.character(run$op_name %||% ""),
          as.character(run$created_at %||% NA_character_),
          as.character(run$notes %||% NA_character_),
          as.character(params_json),
          as.character(inputs_json),
          as.character(symbolic_inputs_json),
          as.character(execution_inputs_json),
          as.character(run_hash),
          "1",
          as.character(jsonlite::toJSON(utils::modifyList(
            .wb_prov_runtime_fingerprint(
              run$op_name, operation_pack_runtime = run$operation_pack_runtime %||% NULL),
            runtime_fingerprint %||% list()), auto_unbox = TRUE, null = "null")),
          as.character(contract_json),
          as.character(.wb_prov_contract_hash(contract_json)),
          unname(.wb_identity_schemes()[["run"]]),
          unname(.wb_identity_schemes()[["contract"]])
        )
      )

      parents <- unique(as.character(run$inputs$parents %||% character(0)))
      parents <- parents[nzchar(parents)]
      for (p in parents) {
        DBI::dbExecute(
          con,
          "INSERT OR IGNORE INTO prov_run_edges(snapshot_id, parent_run_id, child_run_id, edge_type, edge_label)
           VALUES(?, ?, ?, ?, ?);",
          params = list(sid, as.character(p), as.character(rid), "depends_on_run", NA_character_)
        )
      }

      refs <- .wb_dag_collect_refs(run$inputs$user_inputs %||% list(), path = "inputs$user_inputs")
      if (nrow(refs)) {
        refs <- refs[refs$ref_type == "run" & nzchar(refs$run_id), , drop = FALSE]
        if (nrow(refs)) {
          for (j in seq_len(nrow(refs))) {
            DBI::dbExecute(
              con,
              "INSERT OR IGNORE INTO prov_run_edges(snapshot_id, parent_run_id, child_run_id, edge_type, edge_label)
               VALUES(?, ?, ?, ?, ?);",
              params = list(
                sid,
                as.character(refs$run_id[j]),
                as.character(rid),
                "input_run_ref",
                as.character(refs$output[j] %||% NA_character_)
              )
            )
          }
        }
      }
      input_bindings <- c(.wb_prov_collect_entity_bindings(run$inputs$execution_inputs %||% list(), "resolved"), .wb_prov_collect_entity_bindings(run$inputs$user_inputs %||% list(), "input"))
      if (length(input_bindings)) for (binding in input_bindings) {
        binding_path <- as.character(binding$path %||% NA_character_)[1]
        binding_identity <- if (identical(binding$entity_kind,"model_ref") && !is.na(binding_path) && nzchar(binding_path)) {
          absolute <- if (.wb_path_is_absolute(binding_path)) {
            resolved <- normalizePath(binding_path,winslash="/",mustWork=FALSE)
            roots <- c(.wb_bundle_root(bundle),as.character(bundle$staging_source_dir %||% character()))
            roots <- roots[nzchar(roots)]
            normalized_roots <- vapply(roots, normalizePath, character(1),
              winslash = "/", mustWork = TRUE)
            inside <- vapply(normalized_roots, function(root)
              .wb_path_inside(resolved, root), logical(1))
            if (any(inside)) {
              owner <- normalized_roots[[which(inside)[[1L]]]]
              binding_path <- substring(resolved, nchar(owner) + 2L)
              resolved
            } else ""
          } else tryCatch(.wb_bundle_path_require(bundle,binding_path,expected_type="either",purpose="model provenance input"),error=function(e) "")
          if (nzchar(absolute) && (file.exists(absolute) || dir.exists(absolute))) .wb_prov_path_identity(absolute) else list(content_sha256=NA_character_,content_identity_scheme=NA_character_)
        } else list(content_sha256=NA_character_,content_identity_scheme=NA_character_)
        .wb_prov_insert_entity_binding(con, sid, commit_id, rid, "input", binding$binding_name, binding$entity_kind, binding$entity_id, "CONSUMES", path=binding_path, content_hash=binding_identity$content_sha256, content_identity_scheme=binding_identity$content_identity_scheme, source = "resolved_operation_input")
      }
      cell_set_resolutions <- .wb_cell_set_resolution_records(
        run$inputs$cell_set_resolutions %||% list()
      )
      if (length(cell_set_resolutions)) for (resolution in cell_set_resolutions) {
        resolution_json <- jsonlite::toJSON(
          .wb_json_sanitize(resolution), auto_unbox = TRUE, null = "null"
        )
        .wb_prov_insert_entity_binding(
          con, sid, commit_id, rid, "input",
          as.character(resolution$binding_name)[1], "cell_set",
          as.character(resolution$entity_id)[1], "CONSUMES",
          content_hash = as.character(resolution$entity_content_sha256)[1],
          content_identity_scheme = as.character(resolution$entity_content_identity_scheme)[1],
          source = "resolved_named_cell_set",
          resolution_json = as.character(resolution_json),
          source_membership_sha256 = as.character(resolution$source_membership_sha256)[1],
          source_membership_identity_scheme = as.character(resolution$source_membership_identity_scheme)[1],
          source_member_count = as.integer(resolution$source_member_count)[1],
          effective_membership_sha256 = as.character(resolution$effective_membership_sha256)[1],
          effective_membership_identity_scheme = as.character(resolution$effective_membership_identity_scheme)[1],
          effective_member_count = as.integer(resolution$effective_member_count)[1]
        )
      }
      # Fixed typed inputs contribute to provenance_refs during ordinary input
      # resolution. Capability-owned parameters (for example ABI-v3 G4
      # artifact collections) remain nested in user_inputs and are resolved
      # only after the generic runner starts. Persist both sources so every
      # authenticated durable artifact consumed by the run has a matching
      # provenance binding.
      artifact_refs <- .wb_dag_collect_refs(list(
        provenance_refs = run$inputs$provenance_refs %||% list(),
        user_inputs = run$inputs$user_inputs %||% list()), path = "inputs")
      artifact_refs <- artifact_refs[
        artifact_refs$ref_type == "artifact" &
          !is.na(artifact_refs$artifact_id) &
          nzchar(as.character(artifact_refs$artifact_id)),
        , drop = FALSE
      ]
      if (nrow(artifact_refs)) artifact_refs <- artifact_refs[
        !duplicated(as.character(artifact_refs$artifact_id)), , drop = FALSE]
      if (nrow(artifact_refs)) for (j in seq_len(nrow(artifact_refs))) .wb_prov_insert_entity_binding(con, sid, commit_id, rid, "input", as.character(artifact_refs$path[j]), "artifact", as.character(artifact_refs$artifact_id[j]), "CONSUMES", source = "resolved_artifact_input")

      outs <- run$outputs %||% list()
      if (length(outs)) {
        for (nm in names(outs)) {
          prim <- outs[[nm]]
          kind <- if (.wb_is_primitive(prim)) as.character(prim$kind %||% "unknown")[1] else "unknown"
          graph_stage <- attr(prim, "graph_stage", exact = TRUE)
          graph_policy <- if (kind == "graph") .wb_graph_effective_budgets(con,
            if (is.null(graph_stage)) list() else graph_stage$budgets) else list()
          identity <- .wb_prov_payload_identity(bundle, prim, workspace = workspace,
            staging_bundle = staging_bundle, graph_budgets = graph_policy)
          replay_decl <- .wb_replay_equivalence_declaration(
            run$op_name, nm, prim, identity, bundle = bundle,
            workspace = workspace, staging_bundle = staging_bundle
          )
          out_hash <- identity$structural_fingerprint
          art_id <- artifact_map[[paste0(rid, "::", nm)]] %||% NA_character_
          mat_row <- if (is.data.frame(materializations) && nrow(materializations)) {
            materializations[as.character(materializations$run_id) == as.character(rid) &
              as.character(materializations$output_name) == as.character(nm), , drop = FALSE]
          } else data.frame()
          mat_path <- if (nrow(mat_row)) as.character(mat_row$path[1]) else NA_character_
          mat_class <- if (!is.na(art_id) && nzchar(as.character(art_id))) "public_artifact" else if (nrow(mat_row)) "internal_materialization" else "none"

          DBI::dbExecute(
            con,
            "INSERT INTO prov_run_outputs(snapshot_id, run_id, output_name, primitive_kind, output_hash, artifact_id, materialization_class, materialization_path, structural_fingerprint, content_sha256, verification_level, verification_status, replay_equivalence_policy, replay_equivalence_reference, replay_equivalence_status, content_identity_scheme, output_hash_scheme, structural_fingerprint_scheme)
             VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            params = list(
              sid, as.character(rid), as.character(nm), as.character(kind), as.character(out_hash), as.character(art_id), mat_class, mat_path,
              identity$structural_fingerprint, identity$content_sha256, identity$verification_level, identity$verification_status,
              replay_decl$policy, replay_decl$reference, replay_decl$status, identity$content_identity_scheme,
              unname(.wb_identity_schemes()[["structural"]]), unname(.wb_identity_schemes()[["structural"]])
            )
          )
          if (!is.na(art_id) && nzchar(art_id) && kind %in%
              c("cell_vector", "cell_vector_family", "graph")) {
            retained <- if (kind == "graph") {
              graph_identity <- .wb_graph_sql_identities(con, art_id, graph_policy)
              graph_identity[c("content_identity", "binding_identity", "descriptor_identity")]
            } else .wb_graph_object_verify(con, art_id, require_certificate = FALSE)
            DBI::dbExecute(con, paste0("UPDATE prov_run_outputs SET retained_payload_identity_json=? ",
              "WHERE snapshot_id=? AND run_id=? AND output_name=?;"), params = list(
                .wb_operation_pack_canonical_json(retained), sid, as.character(rid), as.character(nm)))
          }
          primitive_binding <- .wb_prov_primitive_entity_binding(prim)
          identity_hash <- identity$content_sha256 %||% out_hash
          if (!is.null(primitive_binding)) .wb_prov_insert_entity_binding(con, sid, commit_id, rid, "output", nm, primitive_binding$entity_kind, primitive_binding$entity_id, "MATERIALIZES", mat_path, identity_hash, identity$content_identity_scheme, "promotion_materialization")
          if (!is.na(art_id) && nzchar(art_id)) .wb_prov_insert_entity_binding(con, sid, commit_id, rid, "output", nm, "artifact", as.character(art_id), "PRODUCES", mat_path, identity_hash, identity$content_identity_scheme, "promotion_artifact")
        }
      }
      .wb_operation_pack_v2_write_registry_bindings(
        bundle, sid, commit_id, rid)
    }
  }
  if (isTRUE(transaction_open)) write_snapshot() else DBI::dbWithTransaction(con, write_snapshot())

  if (is.data.frame(materializations) && nrow(materializations)) {
    .wb_db_append_chunked(con, "prov_materializations", materializations)
  }

  sid
}

#' List Persisted Provenance Snapshots
#'
#' Return provenance snapshot heads recorded in the bundle.
#'
#' @param bundle Open `scworkbench_bundle`.
#'
#' @return A data frame of persisted provenance snapshot heads.
#'
#' @export
wb_prov_list_heads <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_assert_observational_schema(bundle, "prov_heads", action = "provenance-head inspection")
  DBI::dbGetQuery(
    con,
    "SELECT snapshot_id, created_at, created_by, name_prefix, description, schema_version, n_runs, n_artifacts
     FROM prov_heads
     ORDER BY created_at DESC;"
  )
}

#' Reconstruct A Persisted Provenance DAG
#'
#' Rebuild the persisted run/artifact DAG for one provenance snapshot.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param snapshot_id Optional snapshot id. When omitted, the latest snapshot
#'   is used.
#'
#' @return A named list with `snapshot_id`, `head_run_ids`, `nodes`, and
#'   `edges`. Persisted output identity schemes are retained in output payloads.
#'
#' @export
wb_prov_dag <- function(bundle, snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance DAG reconstruction")
  con <- bundle$con
  .wb_assert_observational_schema(
    bundle, c("prov_heads", "prov_runs", "prov_run_outputs", "prov_run_edges"),
    action = "provenance DAG inspection"
  )

  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid)) {
    h <- DBI::dbGetQuery(con, "SELECT snapshot_id FROM prov_heads ORDER BY created_at DESC LIMIT 1;")
    if (!nrow(h)) {
      return(list(
        snapshot_id = NA_character_,
        head_run_ids = character(0),
        nodes = data.frame(id = character(0), node_type = character(0), label = character(0), stringsAsFactors = FALSE),
        edges = data.frame(from = character(0), to = character(0), edge_type = character(0), label = character(0), stringsAsFactors = FALSE)
      ))
    }
    sid <- as.character(h$snapshot_id[1])
  }

  head <- DBI::dbGetQuery(
    con,
    "SELECT head_run_ids_json FROM prov_heads WHERE snapshot_id = ?;",
    params = list(sid)
  )
  .wb_assert(nrow(head) == 1, paste0("Unknown snapshot_id: ", sid))
  head_runs <- jsonlite::fromJSON(as.character(head$head_run_ids_json[1]))
  head_runs <- as.character(head_runs %||% character(0))

  runs <- DBI::dbGetQuery(
    con,
    "SELECT run_id, op_name, created_at FROM prov_runs WHERE snapshot_id = ? ORDER BY created_at, run_id;",
    params = list(sid)
  )
  run_nodes <- if (nrow(runs)) data.frame(
    id = paste0("run:", as.character(runs$run_id)),
    node_type = "run",
    label = as.character(runs$op_name),
    run_id = as.character(runs$run_id),
    op_name = as.character(runs$op_name),
    created_at = as.character(runs$created_at),
    artifact_id = NA_character_,
    artifact_type = NA_character_,
    stringsAsFactors = FALSE
  ) else data.frame(
    id = character(0), node_type = character(0), label = character(0), run_id = character(0),
    op_name = character(0), created_at = character(0), artifact_id = character(0), artifact_type = character(0),
    stringsAsFactors = FALSE
  )

  arts <- DBI::dbGetQuery(
    con,
    "SELECT o.run_id, o.output_name, o.artifact_id, a.type, a.name, a.created_at
     FROM prov_run_outputs o
     LEFT JOIN artifacts a ON a.artifact_id = o.artifact_id
     WHERE o.snapshot_id = ? AND o.artifact_id IS NOT NULL AND o.artifact_id <> ''
     ORDER BY o.run_id, o.output_name;",
    params = list(sid)
  )
  art_nodes <- if (nrow(arts)) data.frame(
    id = paste0("artifact:", as.character(arts$artifact_id)),
    node_type = "artifact",
    label = as.character(arts$name %||% arts$artifact_id),
    run_id = NA_character_,
    op_name = NA_character_,
    created_at = as.character(arts$created_at %||% NA_character_),
    artifact_id = as.character(arts$artifact_id),
    artifact_type = as.character(arts$type %||% NA_character_),
    stringsAsFactors = FALSE
  ) else run_nodes[0, , drop = FALSE]

  nodes <- unique(rbind(run_nodes, art_nodes))

  ee <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id, child_run_id, edge_type, edge_label
     FROM prov_run_edges WHERE snapshot_id = ?
     ORDER BY parent_run_id, child_run_id, edge_type;",
    params = list(sid)
  )
  run_edges <- if (nrow(ee)) data.frame(
    from = paste0("run:", as.character(ee$parent_run_id)),
    to = paste0("run:", as.character(ee$child_run_id)),
    edge_type = as.character(ee$edge_type),
    label = as.character(ee$edge_label %||% NA_character_),
    stringsAsFactors = FALSE
  ) else data.frame(from = character(0), to = character(0), edge_type = character(0), label = character(0), stringsAsFactors = FALSE)

  art_edges <- if (nrow(arts)) data.frame(
    from = paste0("run:", as.character(arts$run_id)),
    to = paste0("artifact:", as.character(arts$artifact_id)),
    edge_type = "promoted_to_artifact",
    label = as.character(arts$output_name),
    stringsAsFactors = FALSE
  ) else run_edges[0, , drop = FALSE]

  list(
    snapshot_id = sid,
    head_run_ids = head_runs,
    nodes = nodes,
    edges = unique(rbind(run_edges, art_edges))
  )
}

#' Inspect One Persisted Run From Provenance
#'
#' Read one persisted run plus its local lineage and outputs from a provenance
#' snapshot.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param run_id Run id inside the snapshot.
#' @param snapshot_id Optional snapshot id. When omitted, all snapshots are
#'   searched and the run is returned only when exactly one snapshot contains
#'   it. Ambiguous run-only lookup fails explicitly.
#'
#' @return A named list with `run`, `parents`, `children`, `entity_bindings`,
#'   and `outputs`. Named cell-set bindings include their source and effective
#'   membership SHA-256/count evidence. The run and output records expose their
#'   explicit persisted identity schemes.
#'
#' @export
wb_prov_run_details <- function(bundle, run_id, snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance run inspection")
  con <- bundle$con
  .wb_assert_observational_schema(
    bundle, c("prov_runs", "prov_run_edges", "prov_run_entity_bindings", "prov_run_outputs"),
    action = "provenance run inspection"
  )

  rid <- as.character(run_id)[1]
  .wb_assert(nzchar(rid), "run_id must be non-empty")

  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid)) {
    matches <- DBI::dbGetQuery(
      con,
      "SELECT DISTINCT snapshot_id FROM prov_runs WHERE run_id = ? ORDER BY snapshot_id;",
      params = list(rid)
    )
    if (!nrow(matches)) {
      .wb_prov_lookup_abort(
        "PROVENANCE_RUN_NOT_FOUND",
        paste0("Run not found in any provenance snapshot: ", rid),
        list(run_id = rid, snapshot_ids = character(0))
      )
    }
    if (nrow(matches) > 1L) {
      candidates <- as.character(matches$snapshot_id)
      .wb_prov_lookup_abort(
        "PROVENANCE_RUN_AMBIGUOUS",
        paste0("Run appears in multiple provenance snapshots; supply snapshot_id: ", rid),
        list(run_id = rid, snapshot_ids = candidates)
      )
    }
    sid <- as.character(matches$snapshot_id[[1L]])
  }

  has_sym <- .wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")
  has_exec <- .wb_db_has_column(con, "prov_runs", "execution_inputs_json")
  has_run_scheme <- .wb_db_has_column(con, "prov_runs", "run_hash_scheme")
  has_contract_scheme <- .wb_db_has_column(con, "prov_runs", "contract_hash_scheme")
  rr <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT run_id, op_name, created_at, notes, params_json, inputs_json, op_version, runtime_fingerprint_json, contract_json, contract_hash, ",
      if (has_run_scheme) "run_hash_scheme" else "NULL AS run_hash_scheme", ", ",
      if (has_contract_scheme) "contract_hash_scheme" else "NULL AS contract_hash_scheme", ", ",
      if (has_sym) "symbolic_inputs_json" else "NULL AS symbolic_inputs_json",
      ", ",
      if (has_exec) "execution_inputs_json" else "NULL AS execution_inputs_json",
      ", run_hash FROM prov_runs WHERE snapshot_id = ? AND run_id = ?;"
    ),
    params = list(sid, rid)
  )
  if (nrow(rr) != 1L) {
    .wb_prov_lookup_abort(
      "PROVENANCE_RUN_NOT_FOUND",
      paste0("Run not found in snapshot: ", rid, " / ", sid),
      list(run_id = rid, snapshot_ids = sid)
    )
  }

  parents <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id FROM prov_run_edges
     WHERE snapshot_id = ? AND child_run_id = ?
       AND edge_type IN ('depends_on_run','input_run_ref')
     ORDER BY parent_run_id;",
    params = list(sid, rid)
  )$parent_run_id
  parents <- unique(as.character(parents %||% character(0)))

  children <- DBI::dbGetQuery(
    con,
    "SELECT child_run_id FROM prov_run_edges
     WHERE snapshot_id = ? AND parent_run_id = ?
       AND edge_type IN ('depends_on_run','input_run_ref')
     ORDER BY child_run_id;",
    params = list(sid, rid)
  )$child_run_id
  children <- unique(as.character(children %||% character(0)))

  outs <- DBI::dbGetQuery(
    con,
    paste0("SELECT output_name, primitive_kind, output_hash, artifact_id, ", .wb_prov_output_identity_select(con),
           " FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? ORDER BY output_name;"),
    params = list(sid, rid)
  )
  if (!nrow(outs)) {
    outs <- data.frame(
      output_name = character(0),
      primitive_kind = character(0),
      output_hash = character(0),
      artifact_id = character(0),
      stringsAsFactors = FALSE
    )
  }
  bindings <- if (.wb_table_exists(con, "prov_run_entity_bindings")) DBI::dbGetQuery(
    con,
    "SELECT * FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? ORDER BY direction,binding_name,entity_kind,entity_id;",
    params = list(sid,rid)
  ) else data.frame()

  list(
    snapshot_id = sid,
    run = list(
      run_id = as.character(rr$run_id[1]),
      op_name = as.character(rr$op_name[1]),
      created_at = as.character(rr$created_at[1]),
      notes = as.character(rr$notes[1]),
      params = jsonlite::fromJSON(as.character(rr$params_json[1]), simplifyVector = FALSE),
      inputs = jsonlite::fromJSON(as.character(rr$inputs_json[1]), simplifyVector = FALSE),
      symbolic_inputs = jsonlite::fromJSON(as.character(rr$symbolic_inputs_json[1] %||% "null"), simplifyVector = FALSE),
      execution_inputs = jsonlite::fromJSON(as.character(rr$execution_inputs_json[1] %||% "null"), simplifyVector = FALSE),
      run_hash = as.character(rr$run_hash[1]),
      run_hash_scheme = as.character(rr$run_hash_scheme[1] %||% NA_character_),
      operation_version = as.character(rr$op_version[1] %||% NA_character_),
      runtime_fingerprint = jsonlite::fromJSON(as.character(rr$runtime_fingerprint_json[1] %||% "null"), simplifyVector = FALSE),
      contract = jsonlite::fromJSON(as.character(rr$contract_json[1] %||% "null"), simplifyVector = FALSE),
      contract_hash = as.character(rr$contract_hash[1] %||% NA_character_),
      contract_hash_scheme = as.character(rr$contract_hash_scheme[1] %||% NA_character_)
    ),
    parents = parents,
    children = children,
    entity_bindings = bindings,
    outputs = outs
  )
}

.wb_prov_replay_diagnostic <- function(code, message, action,
                                       severity = "error", path = NULL) {
  out <- list(
    code = as.character(code)[1], severity = as.character(severity)[1],
    message = as.character(message)[1], action = as.character(action)[1]
  )
  if (!is.null(path)) out$path <- as.character(path)[1]
  out
}

.wb_prov_collect_replay_run_refs <- function(x, path = "inputs") {
  if (!is.list(x)) return(list())
  if (identical(as.character(x$ref_type %||% "")[1], "run")) {
    return(list(list(
      path = path, run_id = as.character(x$run_id %||% "")[1],
      output = as.character(x$output %||% "")[1],
      status = "requires_matching_session_run"
    )))
  }
  nms <- names(x)
  out <- list()
  for (i in seq_along(x)) {
    child <- if (!is.null(nms) && nzchar(nms[[i]])) paste0(path, "$", nms[[i]]) else paste0(path, "[[", i, "]]")
    out <- c(out, .wb_prov_collect_replay_run_refs(x[[i]], child))
  }
  out
}

.wb_prov_replay_result <- function(snapshot_id, run_id, op_name, op_version,
                                   contract_hash, inputs = list(), issues = list(),
                                   run_references = list()) {
  compatible <- !any(vapply(issues, function(x) identical(x$severity, "error"), logical(1)))
  structure(list(
    schema_version = "scworkbench.provenance.run_replay_inputs.v1",
    snapshot_id = as.character(snapshot_id)[1],
    run_id = as.character(run_id)[1],
    op_name = as.character(op_name)[1],
    op_version = as.character(op_version)[1],
    contract_hash = as.character(contract_hash)[1],
    inputs = if (compatible) inputs else list(),
    diagnostics = list(
      status = if (compatible) "compatible" else "incompatible",
      compatible = compatible,
      issues = issues,
      run_references = run_references
    )
  ), class = c("wb_prov_run_replay_inputs", "list"))
}

#' Get Typed Replay Inputs For One Persisted Run
#'
#' Rehydrates the exact persisted symbolic inputs and operation parameters
#' through the installed operation contract. Unlike [wb_prov_run_details()],
#' which deliberately preserves the nested JSON inspection representation,
#' this getter returns values ready for `wb_session_run_op(inputs = ...)`.
#' It is read-only and reports unavailable or changed operation contracts as an
#' explicit incompatible diagnostic with an empty `inputs` list.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param run_id Persisted run identifier.
#' @param snapshot_id Optional provenance snapshot. It is required when the run
#'   identifier occurs in more than one snapshot.
#' @return A `wb_prov_run_replay_inputs` list with schema, resolved run and
#'   operation identities, replay-ready `inputs`, and compatibility diagnostics.
#'   Run-reference diagnostics identify references that are executable only in
#'   a session containing the corresponding recorded dependency.
#' @export
wb_prov_run_replay_inputs <- function(bundle, run_id, snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "typed provenance replay inputs")
  con <- bundle$con
  .wb_assert(.wb_table_exists(con, "prov_runs"), "Bundle has no persisted provenance runs.")
  rid <- as.character(run_id)[1]
  .wb_assert(nzchar(rid), "run_id must be non-empty")
  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid)) {
    matches <- DBI::dbGetQuery(
      con, "SELECT DISTINCT snapshot_id FROM prov_runs WHERE run_id = ? ORDER BY snapshot_id;",
      params = list(rid)
    )
    if (!nrow(matches)) {
      .wb_prov_lookup_abort("PROVENANCE_RUN_NOT_FOUND",
        paste0("Run not found in any provenance snapshot: ", rid),
        list(run_id = rid, snapshot_ids = character(0)))
    }
    if (nrow(matches) > 1L) {
      .wb_prov_lookup_abort("PROVENANCE_RUN_AMBIGUOUS",
        paste0("Run appears in multiple provenance snapshots; supply snapshot_id: ", rid),
        list(run_id = rid, snapshot_ids = as.character(matches$snapshot_id)))
    }
    sid <- as.character(matches$snapshot_id[[1L]])
  }
  required <- c("op_name", "op_version", "contract_json", "contract_hash",
                "contract_hash_scheme", "inputs_json", "symbolic_inputs_json", "params_json")
  available <- DBI::dbListFields(con, "prov_runs")
  missing <- setdiff(required, available)
  .wb_assert(!length(missing), paste0(
    "Persisted provenance schema cannot provide typed replay inputs; missing: ",
    paste(missing, collapse = ", "), "."))
  rr <- DBI::dbGetQuery(con, paste0(
    "SELECT ", paste(required, collapse = ", "),
    " FROM prov_runs WHERE snapshot_id = ? AND run_id = ?;"
  ), params = list(sid, rid))
  if (nrow(rr) != 1L) {
    .wb_prov_lookup_abort("PROVENANCE_RUN_NOT_FOUND",
      paste0("Run not found in snapshot: ", rid, " / ", sid),
      list(run_id = rid, snapshot_ids = sid))
  }

  op_name <- as.character(rr$op_name[[1L]] %||% "")
  op_version <- as.character(rr$op_version[[1L]] %||% "")
  contract_hash <- as.character(rr$contract_hash[[1L]] %||% "")
  contract_json <- as.character(rr$contract_json[[1L]] %||% "")
  issues <- list()
  add_issue <- function(code, message, action) {
    issues[[length(issues) + 1L]] <<- .wb_prov_replay_diagnostic(code, message, action)
  }
  installed_catalog <- .wb_operation_catalog()
  if (!op_name %in% names(installed_catalog)) {
    recorded_contract <- tryCatch(jsonlite::fromJSON(contract_json, simplifyVector = TRUE,
      simplifyDataFrame = FALSE), error = function(e) list())
    recorded_pack <- recorded_contract$interface$source_pack %||% NULL
    if (!is.null(recorded_pack)) {
      package_name <- as.character(recorded_pack$package$name %||% "the producing package")[1]
      package_version <- as.character(recorded_pack$package$version %||% "recorded version")[1]
      pack_sha256 <- as.character(recorded_pack$pack_sha256 %||% "")[1]
      backend <- as.character(recorded_pack$backend %||% "R")[1]
      add_issue("OPERATION_PACK_REQUIRED",
        paste0("Operation '", op_name, "' requires absent operation pack '", package_name,
               "' version '", package_version, "' with backend '", backend,
               "' (pack_sha256=", pack_sha256, ")."),
        if (identical(backend, "Python")) {
          paste0("Install the exact Python distribution and explicitly activate entry point '",
                 as.character(recorded_pack$entry_point %||% "")[1], "' from group '",
                 as.character(recorded_pack$entry_point_group %||% "scworkbench.operation_packs.v1")[1],
                 "' through the compatible Python operation-pack runtime.")
        } else {
          paste0("Install the exact compatible R package and explicitly call wb_operation_pack_load('",
                 package_name, "').")
        })
    } else {
      add_issue("OPERATION_UNAVAILABLE", paste0("Installed catalog has no operation '", op_name, "'."),
                "Install a scworkbench release that provides the recorded operation.")
    }
  }
  if (!identical(op_version, "1")) {
    add_issue("OPERATION_VERSION_INCOMPATIBLE",
              paste0("Recorded operation version is '", op_version, "'; installed version is '1'."),
              "Use a scworkbench release with the recorded operation-contract version.")
  }
  contract <- tryCatch(jsonlite::fromJSON(contract_json, simplifyVector = TRUE,
                                           simplifyDataFrame = FALSE), error = identity)
  if (inherits(contract, "error") || !is.list(contract)) {
    add_issue("CONTRACT_INVALID", "Recorded operation contract JSON is invalid.",
              "Repair or reproduce the bundle from an intact provenance source.")
  } else {
    scheme <- as.character(rr$contract_hash_scheme[[1L]] %||% "")
    observed <- tryCatch(.wb_prov_contract_hash(contract_json, scheme = scheme), error = identity)
    if (inherits(observed, "error") || !nzchar(contract_hash) ||
        !identical(tolower(as.character(observed)), tolower(contract_hash))) {
      add_issue("CONTRACT_IDENTITY_INVALID", "Recorded contract hash does not authenticate contract_json.",
                "Validate bundle provenance integrity before replay.")
    }
    if (op_name %in% names(installed_catalog)) {
      recorded_interface <- contract$interface %||% list()
      current_interface <- .wb_prov_current_contract_interface(op_name)
      issue <- .wb_prov_operation_contract_incompatibility(
        recorded_interface, current_interface, op_name)
      if (!is.null(issue)) issues[[length(issues) + 1L]] <- issue
    }
  }
  stored_run_inputs <- tryCatch(
    jsonlite::fromJSON(as.character(rr$inputs_json[[1L]] %||% "{}"), simplifyVector = FALSE),
    error = function(e) list()
  )
  resolution_issue <- tryCatch({
    .wb_verify_cell_set_resolution_records(
      bundle, stored_run_inputs$cell_set_resolutions %||% list(),
      context = "replay planning"
    )
    NULL
  }, wb_cell_set_resolution_error = function(e) e)
  if (!is.null(resolution_issue)) {
    add_issue(
      as.character(resolution_issue$code %||% "CELL_SET_RESOLUTION_MISMATCH")[1],
      conditionMessage(resolution_issue),
      "Restore the exact durable named-set membership recorded by the historical run before replay."
    )
  }
  if (length(issues)) {
    return(.wb_prov_replay_result(sid, rid, op_name, op_version, contract_hash,
                                  issues = issues))
  }

  symbolic_text <- as.character(rr$symbolic_inputs_json[[1L]] %||% "")
  if (nzchar(symbolic_text) && !identical(symbolic_text, "null")) {
    recorded_inputs <- jsonlite::fromJSON(symbolic_text, simplifyVector = FALSE)
    if (is.null(recorded_inputs)) recorded_inputs <- list()
  } else {
    stored <- jsonlite::fromJSON(as.character(rr$inputs_json[[1L]] %||% "{}"),
                                 simplifyVector = FALSE)
    recorded_inputs <- .wb_prov_compact_inputs(stored)
  }
  recorded_params <- jsonlite::fromJSON(as.character(rr$params_json[[1L]] %||% "{}"),
                                        simplifyVector = FALSE)
  inputs <- .wb_prov_replay_execution_inputs(
    recorded_inputs, recorded_params, run_id = rid, op_name = op_name
  )
  refs <- .wb_prov_collect_replay_run_refs(inputs)
  if (length(refs)) {
    issues[[1L]] <- .wb_prov_replay_diagnostic(
      "RUN_REFERENCE_REQUIRES_SESSION_CONTEXT",
      "One or more wb_ref_run() inputs require matching recorded dependencies in the new session.",
      "Replay or otherwise make the recorded dependency runs available before executing this input set.",
      severity = "info"
    )
  }
  .wb_prov_replay_result(sid, rid, op_name, op_version, contract_hash,
                         inputs = inputs, issues = issues, run_references = refs)
}

#' Get Immutable Ingestion Source Identity
#' @param bundle Open bundle.
#' @param matrix_id Optional matrix identifier.
#' @return Data frame with persisted source identity JSON; empty for legacy or
#' unavailable identity records.
#' @export
wb_prov_source_identity <- function(bundle, matrix_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_observational_schema(
    bundle, "prov_source_identities",
    action = "ingestion source-identity inspection"
  )
  if (!.wb_table_exists(bundle$con, "prov_source_identities")) return(data.frame(snapshot_id=character(), run_id=character(), matrix_id=character(), source_identity_json=character(), status=character(), stringsAsFactors=FALSE))
  q <- "SELECT snapshot_id, run_id, matrix_id, source_identity_json FROM prov_source_identities"
  params <- list()
  if (!is.null(matrix_id)) { q <- paste0(q, " WHERE matrix_id = ?"); params <- list(as.character(matrix_id)[1]) }
  q <- paste0(q, " ORDER BY snapshot_id, run_id, matrix_id;")
  out <- if (length(params)) DBI::dbGetQuery(bundle$con, q, params = params) else DBI::dbGetQuery(bundle$con, q)
  if (!nrow(out)) return(data.frame(snapshot_id=character(), run_id=character(), matrix_id=character(), source_identity_json=character(), status=character(), stringsAsFactors=FALSE))
  out$status <- "available"
  out
}

#' List declared external ingestion inputs
#'
#' @param bundle scworkbench bundle.
#' @param run_id Optional ingestion run id.
#' @return Durable declared source records, including checksum status and, for
#'   nested conversion inputs, `parent_source_id` and `source_relation`.
#' @export
wb_prov_source_inputs <- function(bundle, run_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_observational_schema(
    bundle, "prov_source_inputs",
    action = "ingestion source-input inspection"
  )
  empty <- data.frame(snapshot_id=character(), run_id=character(), source_id=character(), source_json=character(), scope=character(), portable=logical(), path=character(), uri=character(), accession=character(), role=character(), format=character(), parent_source_id=character(), source_relation=character(), checksum_algorithm=character(), checksum_value=character(), checksum_status=character(), stringsAsFactors=FALSE)
  if (!.wb_table_exists(bundle$con, "prov_source_inputs")) return(empty)
  out <- DBI::dbGetQuery(bundle$con, "SELECT snapshot_id, run_id, source_id, source_json, checksum_status FROM prov_source_inputs ORDER BY snapshot_id, run_id, source_id;")
  if (!is.null(run_id)) out <- out[as.character(out$run_id) %in% as.character(run_id), , drop=FALSE]
  if (!nrow(out)) return(empty)
  norm <- lapply(out$source_json, function(txt) {
    x <- tryCatch(jsonlite::fromJSON(as.character(txt), simplifyVector=FALSE), error=function(e) list())
    sha <- as.character(x$sha256 %||% "")[1]
    alg <- tolower(as.character(x$checksum_algorithm %||% if (nzchar(sha)) "sha256" else "")[1])
    val <- as.character(if (nzchar(sha)) sha else x$checksum %||% "")[1]
    valid_sha <- identical(alg, "sha256") && grepl("^[A-Fa-f0-9]{64}$", val)
    status <- if (!nzchar(val)) "declared_no_checksum" else if (valid_sha) "checksummed" else if (identical(alg, "sha256") || nzchar(sha)) "malformed_checksum" else "unsupported_checksum"
    scope <- as.character(x$scope %||% x$source_scope %||% "legacy_external")[1]
    list(scope=scope, portable=scope %in% c("public_file", "external_file") && isTRUE(x$bundled %||% FALSE), path=as.character(x$path %||% NA_character_)[1], uri=as.character(x$uri %||% NA_character_)[1], accession=as.character(x$accession %||% NA_character_)[1], role=as.character(x$role %||% x$file_kind %||% NA_character_)[1], format=as.character(x$format %||% NA_character_)[1], parent_source_id=as.character(x$parent_source_id %||% NA_character_)[1], source_relation=as.character(x$source_relation %||% NA_character_)[1], checksum_algorithm=if(nzchar(alg)) alg else NA_character_, checksum_value=if(nzchar(val)) val else NA_character_, checksum_status=if(identical(scope,"in_memory")) "nonportable_in_memory" else status)
  })
  extra <- do.call(rbind, lapply(norm, as.data.frame, stringsAsFactors=FALSE))
  cbind(out[, c("snapshot_id", "run_id", "source_id", "source_json"), drop=FALSE], extra, stringsAsFactors=FALSE)
}

.wb_r_single_quote_escape <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub("'", "\\\\'", x, fixed = TRUE)
  x
}

.wb_emit_r_paste0_chunks <- function(var_name, txt, chunk_size = 700L) {
  s <- .wb_r_single_quote_escape(txt %||% "")
  n <- nchar(s, type = "chars")
  if (!is.finite(n) || n <= chunk_size) {
    return(paste0(var_name, " <- '", s, "'"))
  }
  starts <- seq.int(1L, n, by = as.integer(chunk_size))
  chunks <- vapply(starts, function(i) substr(s, i, min(i + chunk_size - 1L, n)), character(1))
  c(
    paste0(var_name, " <- paste0("),
    paste0("  '", chunks, "'", collapse = ",\n"),
    ")"
  )
}

.wb_prov_compact_inputs <- function(stored_inputs) {
  x <- stored_inputs %||% list()
  if (!is.list(x)) return(list())
  ui <- x$user_inputs %||% list()
  if (!is.list(ui)) ui <- list()
  if (is.null(ui$cell_set) && !is.null(x$cell_set)) ui$cell_set <- x$cell_set
  if (is.null(ui$min_cells) && !is.null(x$min_cells)) ui$min_cells <- x$min_cells
  ui
}

.wb_drop_key_recursive <- function(x, key) {
  if (!is.list(x)) return(x)
  nms <- names(x) %||% character(length(x))
  keep <- if (length(nms)) !(nms %in% key) else rep(TRUE, length(x))
  y <- x[keep]
  if (!length(y)) return(y)
  y <- lapply(y, .wb_drop_key_recursive, key = key)
  if (!is.null(names(x))) names(y) <- names(x)[keep]
  y
}

.wb_emit_r_object_assign <- function(var_name, obj) {
  txt <- utils::capture.output(base::dput(obj))
  if (!length(txt)) return(paste0(var_name, " <- list()"))
  if (length(txt) == 1L) return(paste0(var_name, " <- ", txt[[1]]))
  c(paste0(var_name, " <- ", txt[[1]]), txt[-1])
}

.wb_prov_rehydrate_reference <- function(x) {
  if (!is.list(x) || is.null(x$ref_type)) return(x)
  ref_type <- as.character(unlist(x$ref_type, recursive = TRUE, use.names = FALSE))[1]
  if (identical(ref_type, "run")) {
    return(wb_ref_run(
      as.character(unlist(x$run_id, recursive = TRUE, use.names = FALSE))[1],
      as.character(unlist(x$output, recursive = TRUE, use.names = FALSE))[1]
    ))
  }
  if (identical(ref_type, "artifact")) {
    return(wb_ref_artifact(
      as.character(unlist(x$artifact_id, recursive = TRUE, use.names = FALSE))[1],
      as.character(unlist(x$output, recursive = TRUE, use.names = FALSE))[1]
    ))
  }
  if (identical(ref_type, "metadata_field")) {
    return(wb_ref_metadata_field(
      as.character(unlist(x$field_id, recursive = TRUE, use.names = FALSE))[1]
    ))
  }
  x
}

.wb_prov_rehydrate_value <- function(value, type) {
  if (is.null(value)) return(NULL)
  if (is.list(value) && !is.null(value$ref_type)) {
    return(.wb_prov_rehydrate_reference(value))
  }
  type <- as.character(type %||% "")[1]
  flat <- function(x) unlist(x, recursive = TRUE, use.names = FALSE)
  if (type %in% c("int", "int_range", "int_vec")) return(as.integer(flat(value)))
  if (type %in% c("dbl", "number")) return(as.numeric(flat(value)))
  if (type %in% c("bool", "logical")) return(as.logical(flat(value)))
  if (type %in% c("string", "path", "cell_set", "choice")) return(as.character(flat(value))[1])
  if (type %in% c("string_vec", "string_array", "cell_ids")) return(as.character(flat(value)))
  if (identical(type, "metadata_field")) {
    return(if (is.list(value)) .wb_prov_rehydrate_reference(value) else as.character(flat(value))[1])
  }
  if (identical(type, "metadata_field_array")) {
    if (is.character(value)) return(as.character(value))
    values <- lapply(value, function(x) {
      if (is.list(x) && !is.null(x$ref_type)) .wb_prov_rehydrate_reference(x)
      else as.character(flat(x))[1]
    })
    if (all(vapply(values, is.character, logical(1)))) return(unlist(values, use.names = FALSE))
    return(values)
  }
  if (identical(type, "cell_ids_or_set") && !is.list(value)) return(as.character(flat(value)))
  if (identical(type, "string_vec_or_list")) {
    if (!is.list(value) || is.null(names(value))) return(as.character(flat(value)))
    out <- lapply(value, function(x) as.character(flat(x)))
    names(out) <- names(value)
    return(out)
  }
  value
}

.wb_prov_rehydrate_named_inputs <- function(x, op_name) {
  x <- x %||% list()
  .wb_assert(is.list(x), "Persisted replay values must be a list.")
  params <- .wb_op_param_records(op_name)
  controls <- .wb_op_engine_input_specs()
  for (nm in names(x)) {
    spec <- params[[nm]] %||% controls[[nm]]
    if (!is.null(spec)) x[[nm]] <- .wb_prov_rehydrate_value(x[[nm]], spec$type)
    else if (is.list(x[[nm]]) && !is.null(x[[nm]]$ref_type)) {
      x[[nm]] <- .wb_prov_rehydrate_reference(x[[nm]])
    }
  }
  x
}

# Merge persisted user/symbolic inputs with the recorded run parameters into
# the sole public execution surface accepted by wb_session_run_op().  A run can
# legitimately record a parameter both in inputs and in params (for example an
# input echo added by a runner); only exactly identical values are safe to
# de-duplicate.  A narrowly identified legacy association result label is
# removed before the merge because it is output annotation, not an execution
# setting.  Never let replay silently choose one version of a conflicting
# scientific setting.
.wb_prov_replay_execution_inputs <- function(inputs, params, run_id = NULL, op_name = NULL) {
  inputs <- inputs %||% list()
  params <- params %||% list()
  .wb_assert(is.list(inputs), "Persisted replay inputs must be a list.")
  .wb_assert(is.list(params), "Persisted replay params must be a list.")
  if (length(inputs)) .wb_assert(!is.null(names(inputs)) && all(nzchar(names(inputs))),
                                 "Persisted replay inputs must be named.")
  if (length(params)) .wb_assert(!is.null(names(params)) && all(nzchar(names(params))),
                                 "Persisted replay params must be named.")

  op_name <- as.character(op_name %||% "")[1]
  resolved_op_name <- if (nzchar(op_name)) {
    tryCatch(.wb_operation_name_resolve(op_name), error = function(...) op_name)
  } else op_name
  if (nzchar(resolved_op_name) &&
      resolved_op_name %in% names(.wb_operation_catalog())) {
    inputs <- .wb_prov_rehydrate_named_inputs(inputs, resolved_op_name)
    params <- .wb_prov_rehydrate_named_inputs(params, resolved_op_name)
  }

  # JSON/R deparsing of optional NULL parameters in older snapshots can leave
  # the literal string "NA" in runner diagnostics.  It is not an executable
  # value for a catalog parameter whose public default is NULL.
  op_spec <- .wb_operation_catalog()[[resolved_op_name]]
  if (!is.null(op_spec)) {
    op_params <- op_spec$params %||% list()
    # Runner parameter records include output diagnostics (for example PCA's
    # realised `space_id`). Only declared public parameters are executable.
    param_names <- vapply(op_params, function(p) as.character(p$name %||% "")[1], character(1))
    params <- params[intersect(names(params), param_names)]
    null_optional <- vapply(op_params, function(p) {
      identical(p$default %||% NULL, NULL)
    }, logical(1))
    names(null_optional) <- vapply(op_params, function(p) as.character(p$name %||% "")[1], character(1))
    for (nm in intersect(names(params), names(null_optional)[null_optional])) {
      val <- params[[nm]]
      if (!(nm %in% names(inputs)) || is.null(val) ||
          (length(val) == 1L && (is.na(val) || identical(as.character(val), "NA")))) {
        params[[nm]] <- NULL
      }
    }
  }

  # The association operation historically stored the *dispatched result*
  # (for example fisher_exact or kruskal_anova) in params$method, while its
  # public input is the requested method (often auto).  That result label is
  # an output diagnostic, not an execution parameter.  Preserve the recorded
  # request and do not mistake this legacy output annotation for a conflict.
  replay_op_name <- as.character(op_name %||% "")[1]
  if (identical(sub("^.*::", "", replay_op_name), "cell_vector_association") &&
      !is.null(inputs$method) && !is.null(params$method) &&
      !identical(inputs$method, params$method)) {
    params$method <- NULL
  }

  merged <- inputs
  for (nm in names(params)) {
    if (nm %in% names(merged)) {
      .wb_assert(
        identical(merged[[nm]], params[[nm]]),
        paste0(
          "Replay input/parameter collision for run ", as.character(run_id %||% "<unknown>"),
          ", name '", nm, "': persisted values differ."
        )
      )
      next
    }
    merged[[nm]] <- params[[nm]]
  }
  required_names <- if (!is.null(op_spec)) names(.wb_op(resolved_op_name)$requires %||% list()) else character()
  has_required <- all(vapply(required_names, function(nm) {
    alias <- .wb_op_input_alias(nm)
    any(c(nm, alias, paste0(nm, "_ref"), if (!is.null(alias)) paste0(alias, "_ref") else NULL) %in% names(merged))
  }, logical(1)))
  if (!is.null(op_spec) && has_required) {
    merged <- .wb_validate_op_inputs_contract(resolved_op_name, merged)$inputs
  }
  merged
}

#' Rehydrate Persisted Operation Inputs for Public Replay Scripts
#'
#' Merges persisted symbolic inputs and validated operation parameters using
#' the same duplicate/conflict rules as strict replay. This is the public
#' boundary used by scripts emitted by [wb_prov_emit_r_script()] and
#' [wb_art_emit_r_script()]; it performs no execution or bundle mutation.
#'
#' @param inputs Persisted named symbolic input list.
#' @param params Persisted named operation parameter list.
#' @param run_id Optional historical run identifier used in diagnostics.
#' @param op_name Optional operation name used for current-contract validation.
#' @return A named input list suitable for [wb_session_run_op()].
#' @export
wb_prov_replay_execution_inputs <- function(inputs, params, run_id = NULL, op_name = NULL) {
  .wb_prov_replay_execution_inputs(inputs, params, run_id = run_id, op_name = op_name)
}

#' Emit an R replay script from persisted provenance
#'
#' The generated script replays the persisted run order using the sole public
#' `wb_session_run_op(inputs = ...)` surface. Stored symbolic/literal inputs
#' and run parameters are merged into one execution list. A duplicate name is
#' accepted only when its values are exactly identical; otherwise generation
#' and validation fail rather than silently choosing a scientific setting.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param snapshot_id Optional snapshot id. When omitted, the latest snapshot is
#'   used.
#' @param bundle_dir_literal Optional literal bundle path to embed in the script.
#' @param include_header If `TRUE`, include comments and setup header.
#' @param mode Replay input mode: `"symbolic"` or `"literal"`.
#' @param sidecar_rds_path Sidecar `.rds` path used when `mode = "literal"`.
#' @param style Replay script style: `"bench_pretty"` or `"raw_json"`.
#'
#' @return Length-1 character string containing the replay script text.
#'
#' @export
wb_prov_emit_r_script <- function(bundle,
                                  snapshot_id = NULL,
                                  bundle_dir_literal = "<BUNDLE_DIR>",
                                  include_header = TRUE,
                                  mode = c("symbolic", "literal"),
                                  sidecar_rds_path = "replay_inputs.rds",
                                  style = c("bench_pretty", "raw_json")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance replay script")
  mode <- match.arg(mode)
  style <- match.arg(style)
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  sid <- .wb_prov_snapshot_id_or_latest(con, snapshot_id)
  rr <- .wb_prov_get_runs_order(con, sid)
  .wb_prov_emit_r_script_core(
    runs = rr$runs,
    run_order = rr$run_order,
    snapshot_id = sid,
    bundle_dir_literal = bundle_dir_literal,
    include_header = include_header,
    mode = mode,
    sidecar_rds_path = sidecar_rds_path,
    style = style,
    target = NULL
  )
}

.wb_prov_emit_r_script_core <- function(runs,
                                        run_order,
                                        snapshot_id,
                                        bundle_dir_literal = "<BUNDLE_DIR>",
                                        include_header = TRUE,
                                        mode = c("symbolic", "literal"),
                                        sidecar_rds_path = "replay_inputs.rds",
                                        style = c("bench_pretty", "raw_json"),
                                        target = NULL) {
  .wb_require_pkg("jsonlite", "provenance replay script")
  mode <- match.arg(mode)
  style <- match.arg(style)
  sid <- as.character(snapshot_id)[1]
  .wb_assert(is.data.frame(runs) && nrow(runs) > 0, "runs must be a non-empty data.frame")
  run_order <- as.character(run_order %||% character(0))
  run_order <- run_order[nzchar(run_order)]
  .wb_assert(length(run_order) > 0, "run_order is empty")

  runs <- runs[match(run_order, as.character(runs$run_id)), , drop = FALSE]
  runs <- runs[!is.na(runs$run_id), , drop = FALSE]
  .wb_assert(nrow(runs) == length(run_order), "run_order contains run_ids not present in runs")
  run_idx <- stats::setNames(seq_len(nrow(runs)), as.character(runs$run_id))
  payload <- .wb_prov_payload_from_runs(runs = runs, run_order = run_order, mode = mode)

  if (identical(mode, "literal")) {
    base::saveRDS(payload, file = sidecar_rds_path)
  }

  tgt <- target %||% list()
  tgt_artifact_id <- as.character(tgt$artifact_id %||% "")[1]
  tgt_run_id <- as.character(tgt$run_id %||% "")[1]
  tgt_output_name <- as.character(tgt$output_name %||% "")[1]

  lines <- character(0)
  if (isTRUE(include_header)) {
    lines <- c(
      lines,
      "# scworkbench provenance replay script",
      paste0("# snapshot_id: ", sid),
      paste0("# mode: ", mode),
      paste0("# style: ", style),
      if (nzchar(tgt_artifact_id)) paste0("# target_artifact_id: ", tgt_artifact_id) else NULL,
      if (nzchar(tgt_run_id)) paste0("# target_run_id: ", tgt_run_id) else NULL,
      if (nzchar(tgt_output_name)) paste0("# target_output: ", tgt_output_name) else NULL,
      "library(scworkbench)",
      "library(jsonlite)",
      "",
      paste0("bundle_dir <- '", .wb_r_single_quote_escape(bundle_dir_literal), "'"),
      "bundle <- wb_open_bundle(bundle_dir)",
      # `source()` evaluates top-level expressions one at a time, so an
      # `on.exit()` here can close this connection before the next emitted
      # expression.  The caller/process owns this short-lived handle.
      "sess <- wb_session_new()",
      "replay_map <- list()",
      "target_res <- NULL",
      "`%or%` <- function(x, y) if (is.null(x)) y else x",
      "",
      "rewrite_run_refs <- function(x, replay_map) {",
      "  if (!is.list(x)) return(x)",
      "  if (identical(as.character(x$ref_type %or% '')[1], 'run')) {",
      "    old <- as.character(x$run_id %or% '')[1]",
      "    if (nzchar(old) && !is.null(replay_map[[old]])) x$run_id <- replay_map[[old]]",
      "    return(x)",
      "  }",
      "  y <- lapply(x, rewrite_run_refs, replay_map = replay_map)",
      "  if (!is.null(names(x))) names(y) <- names(x)",
      "  y",
      "}",
      ""
    )
    if (identical(mode, "literal")) {
      lines <- c(
        lines,
        paste0("replay_payload <- readRDS('", .wb_r_single_quote_escape(sidecar_rds_path), "')"),
        ""
      )
    }
  }

  for (rid in run_order) {
    i <- run_idx[[rid]]
    op_name <- as.character(runs$op_name[i])
    notes <- as.character(runs$notes[i] %||% "")
    if (identical(mode, "literal")) {
      lines <- c(
        lines,
        paste0("# run_id: ", rid, " op: ", op_name),
        paste0("entry <- replay_payload[['", .wb_r_single_quote_escape(rid), "']]"),
        "recorded_params <- entry$params %or% list()",
        "recorded_inputs <- entry$inputs %or% list()",
        paste0("execution_inputs <- wb_prov_replay_execution_inputs(recorded_inputs, recorded_params, run_id = '", .wb_r_single_quote_escape(rid), "', op_name = '", .wb_r_single_quote_escape(op_name), "')"),
        "execution_inputs <- rewrite_run_refs(execution_inputs, replay_map = replay_map)",
        paste0("res <- wb_session_run_op(session = sess, bundle = bundle, op_name = '", .wb_r_single_quote_escape(op_name), "', ",
               "inputs = execution_inputs, notes = '", .wb_r_single_quote_escape(notes), "')"),
        "sess <- res$session",
        paste0("replay_map[['", .wb_r_single_quote_escape(rid), "']] <- res$run$run_id"),
        if (nzchar(tgt_run_id) && identical(rid, tgt_run_id)) "target_res <- res" else NULL,
        ""
      )
    } else if (identical(style, "bench_pretty")) {
      lines <- c(
        lines,
        paste0("# run_id: ", rid, " op: ", op_name),
        .wb_emit_r_object_assign("recorded_params", payload[[rid]]$params %||% list()),
        .wb_emit_r_object_assign("recorded_inputs", payload[[rid]]$inputs %||% list()),
        paste0("execution_inputs <- wb_prov_replay_execution_inputs(recorded_inputs, recorded_params, run_id = '", .wb_r_single_quote_escape(rid), "', op_name = '", .wb_r_single_quote_escape(op_name), "')"),
        "execution_inputs <- rewrite_run_refs(execution_inputs, replay_map = replay_map)",
        paste0("res <- wb_session_run_op(session = sess, bundle = bundle, op_name = '", .wb_r_single_quote_escape(op_name), "', ",
               "inputs = execution_inputs, notes = '", .wb_r_single_quote_escape(notes), "')"),
        "sess <- res$session",
        paste0("replay_map[['", .wb_r_single_quote_escape(rid), "']] <- res$run$run_id"),
        if (nzchar(tgt_run_id) && identical(rid, tgt_run_id)) "target_res <- res" else NULL,
        ""
      )
    } else {
      params_json <- jsonlite::toJSON(payload[[rid]]$params %||% list(), auto_unbox = TRUE, null = "null")
      inputs_json <- jsonlite::toJSON(payload[[rid]]$inputs %||% list(), auto_unbox = TRUE, null = "null")
      lines <- c(
        lines,
        paste0("# run_id: ", rid, " op: ", op_name),
        .wb_emit_r_paste0_chunks("params_json_txt", params_json),
        .wb_emit_r_paste0_chunks("inputs_json_txt", inputs_json),
        "recorded_params <- jsonlite::fromJSON(params_json_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)",
        "recorded_inputs <- jsonlite::fromJSON(inputs_json_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)",
        paste0("execution_inputs <- wb_prov_replay_execution_inputs(recorded_inputs, recorded_params, run_id = '", .wb_r_single_quote_escape(rid), "', op_name = '", .wb_r_single_quote_escape(op_name), "')"),
        "execution_inputs <- rewrite_run_refs(execution_inputs, replay_map = replay_map)",
        paste0("res <- wb_session_run_op(session = sess, bundle = bundle, op_name = '", .wb_r_single_quote_escape(op_name), "', ",
               "inputs = execution_inputs, notes = '", .wb_r_single_quote_escape(notes), "')"),
        "sess <- res$session",
        paste0("replay_map[['", .wb_r_single_quote_escape(rid), "']] <- res$run$run_id"),
        if (nzchar(tgt_run_id) && identical(rid, tgt_run_id)) "target_res <- res" else NULL,
        ""
      )
    }
  }

  lines <- c(
    lines,
    "# replay complete",
    "cat('replay complete\\n')",
    "cat('runs:', length(sess$runs), '\\n')",
    if (nzchar(tgt_artifact_id)) paste0("cat('target artifact: ', '", .wb_r_single_quote_escape(tgt_artifact_id), "', '\\n', sep='')") else NULL,
    if (nzchar(tgt_run_id)) paste0("cat('target original run: ', '", .wb_r_single_quote_escape(tgt_run_id), "', '\\n', sep='')") else NULL,
    if (nzchar(tgt_output_name)) paste0("cat('target output: ', '", .wb_r_single_quote_escape(tgt_output_name), "', '\\n', sep='')") else NULL,
    "if (!is.null(target_res) && !is.null(target_res$run$outputs)) cat('target outputs replayed:', paste(names(target_res$run$outputs), collapse=', '), '\\n')"
  )

  paste(lines, collapse = "\n")
}

.wb_prov_snapshot_id_or_latest <- function(con, snapshot_id = NULL) {
  sid <- as.character(snapshot_id %||% "")[1]
  if (nzchar(sid)) return(sid)
  h <- DBI::dbGetQuery(con, "SELECT snapshot_id FROM prov_heads ORDER BY created_at DESC LIMIT 1;")
  .wb_assert(nrow(h) == 1, "No provenance snapshots available.")
  as.character(h$snapshot_id[1])
}

.wb_prov_select_runs <- function(con, sid) {
  has_sym <- .wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")
  has_exec <- .wb_db_has_column(con, "prov_runs", "execution_inputs_json")
  q <- paste0(
    "SELECT run_id, op_name, created_at, notes, params_json, inputs_json, ",
    if (has_sym) "symbolic_inputs_json" else "NULL AS symbolic_inputs_json",
    ", ",
    if (has_exec) "execution_inputs_json" else "NULL AS execution_inputs_json",
    " FROM prov_runs WHERE snapshot_id = ? ORDER BY created_at, run_id;"
  )
  DBI::dbGetQuery(con, q, params = list(sid))
}

.wb_prov_get_runs_order <- function(con, sid) {
  runs <- .wb_prov_select_runs(con, sid)
  .wb_assert(nrow(runs) > 0, paste0("No runs for snapshot_id: ", sid))

  edges <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id, child_run_id
     FROM prov_run_edges
     WHERE snapshot_id = ? AND edge_type IN ('depends_on_run','input_run_ref');",
    params = list(sid)
  )
  # A parent can be recorded both as a general dependency and as an explicit
  # run reference.  They are one ordering relationship; duplicate rows must
  # not leave a child with permanent residual indegree.
  if (nrow(edges)) edges <- unique(edges[, c("parent_run_id", "child_run_id"), drop = FALSE])

  run_ids <- as.character(runs$run_id)
  if (!nrow(edges)) return(list(runs = runs, run_order = run_ids))

  indeg <- stats::setNames(integer(length(run_ids)), run_ids)
  kids <- stats::setNames(vector("list", length(run_ids)), run_ids)
  for (i in seq_len(nrow(edges))) {
    p <- as.character(edges$parent_run_id[i])
    c <- as.character(edges$child_run_id[i])
    if (!(p %in% run_ids) || !(c %in% run_ids)) next
    kids[[p]] <- c(kids[[p]], c)
    indeg[[c]] <- indeg[[c]] + 1L
  }
  q <- sort(names(indeg[indeg == 0L]))
  topo <- character(0)
  while (length(q)) {
    n <- q[1]
    q <- q[-1]
    topo <- c(topo, n)
    ch <- unique(as.character(kids[[n]] %||% character(0)))
    ch <- ch[ch %in% names(indeg)]
    for (c in ch) indeg[[c]] <- indeg[[c]] - 1L
    q <- sort(unique(c(q, names(indeg[indeg == 0L & !(names(indeg) %in% topo)]))))
  }
  run_order <- if (length(topo) == length(run_ids)) topo else run_ids
  list(runs = runs, run_order = run_order)
}

.wb_prov_upstream_run_closure <- function(con, snapshot_id, target_run_id) {
  sid <- as.character(snapshot_id)[1]
  rid <- as.character(target_run_id)[1]
  .wb_assert(nzchar(sid), "snapshot_id must be non-empty")
  .wb_assert(nzchar(rid), "target_run_id must be non-empty")

  edges <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id, child_run_id
     FROM prov_run_edges
     WHERE snapshot_id = ? AND edge_type IN ('depends_on_run','input_run_ref');",
    params = list(sid)
  )
  if (!nrow(edges)) return(rid)

  parents_by_child <- split(
    as.character(edges$parent_run_id),
    as.character(edges$child_run_id)
  )

  seen <- character(0)
  stack <- rid
  while (length(stack)) {
    cur <- as.character(stack[[1]])
    stack <- stack[-1]
    if (!nzchar(cur) || cur %in% seen) next
    seen <- c(seen, cur)
    ps <- unique(as.character(parents_by_child[[cur]] %||% character(0)))
    ps <- ps[nzchar(ps) & !(ps %in% seen)]
    if (length(ps)) stack <- c(ps, stack)
  }
  unique(c(seen, rid))
}

.wb_prov_artifact_source_link <- function(bundle, artifact_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  aid <- as.character(artifact_id)[1]
  .wb_assert(nzchar(aid), "artifact_id must be a non-empty string")

  link <- DBI::dbGetQuery(
    bundle$con,
    "SELECT snapshot_id, run_id, output_name, primitive_kind, artifact_id
     FROM prov_run_outputs WHERE artifact_id = ?
     ORDER BY snapshot_id, run_id, output_name;",
    params = list(aid)
  )
  .wb_assert(is.data.frame(link) && nrow(link) >= 1, paste0("No persisted provenance link for artifact: ", aid))

  row <- link[1, , drop = FALSE]
  sid <- as.character(row$snapshot_id[1] %||% "")[1]
  rid <- as.character(row$run_id[1] %||% "")[1]
  out_nm <- as.character(row$output_name[1] %||% "")[1]
  .wb_assert(nzchar(sid), paste0("Artifact has no snapshot_id linkage: ", aid))
  .wb_assert(nzchar(rid), paste0("Artifact has no run_id linkage: ", aid))

  list(
    artifact_id = aid,
    snapshot_id = sid,
    run_id = rid,
    output_name = out_nm
  )
}

.wb_prov_payload_from_runs <- function(runs, run_order, mode = "symbolic") {
  payload <- list()
  run_idx <- stats::setNames(seq_len(nrow(runs)), as.character(runs$run_id))
  for (rid in run_order) {
    i <- run_idx[[rid]]
    sym_txt <- as.character(runs$symbolic_inputs_json[i] %||% "")[1]
    if (nzchar(sym_txt)) {
      inputs_use <- jsonlite::fromJSON(sym_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)
      if (is.null(inputs_use)) inputs_use <- list()
    } else {
      inputs_stored <- jsonlite::fromJSON(
        as.character(runs$inputs_json[i] %||% "{}"),
        simplifyVector = TRUE,
        simplifyDataFrame = FALSE
      )
      inputs_use <- .wb_prov_compact_inputs(inputs_stored)
    }
    if (identical(mode, "symbolic")) {
      inputs_use <- .wb_drop_key_recursive(inputs_use, key = "cell_ids")
    }
    params_use <- jsonlite::fromJSON(
      as.character(runs$params_json[i] %||% "{}"),
      simplifyVector = TRUE,
      simplifyDataFrame = FALSE
    )
    payload[[rid]] <- list(params = params_use, inputs = inputs_use)
  }
  payload
}

#' Emit a minimal R replay script for a target artifact
#'
#' Emits only the producing run for `artifact_id` and its upstream run dependencies
#' within the linked persisted provenance snapshot.
#'
#' @param bundle scworkbench bundle
#' @param artifact_id artifact id
#' @param bundle_dir_literal Optional literal bundle path to embed in script
#' @param include_header If TRUE, include comments and setup header
#' @param mode Replay input mode: `symbolic` (default) or `literal`
#' @param sidecar_rds_path Sidecar `.rds` path when `mode = "literal"`
#' @param style Replay script style (`bench_pretty` or `raw_json`)
#' @return length-1 character string containing R script text
#' @export
wb_art_emit_r_script <- function(bundle,
                                 artifact_id,
                                 bundle_dir_literal = "<BUNDLE_DIR>",
                                 include_header = TRUE,
                                 mode = c("symbolic", "literal"),
                                 sidecar_rds_path = "replay_inputs.rds",
                                 style = c("bench_pretty", "raw_json")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  mode <- match.arg(mode)
  style <- match.arg(style)

  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  src <- .wb_prov_artifact_source_link(bundle, artifact_id = artifact_id)
  rr <- .wb_prov_get_runs_order(con, src$snapshot_id)
  need_run_ids <- .wb_prov_upstream_run_closure(con, src$snapshot_id, src$run_id)

  keep <- as.character(rr$runs$run_id) %in% need_run_ids
  runs_min <- rr$runs[keep, , drop = FALSE]
  order_min <- as.character(rr$run_order)[as.character(rr$run_order) %in% need_run_ids]
  .wb_assert(length(order_min) > 0, paste0("Failed to resolve upstream run subgraph for artifact: ", src$artifact_id))

  .wb_prov_emit_r_script_core(
    runs = runs_min,
    run_order = order_min,
    snapshot_id = src$snapshot_id,
    bundle_dir_literal = bundle_dir_literal,
    include_header = include_header,
    mode = mode,
    sidecar_rds_path = sidecar_rds_path,
    style = style,
    target = list(
      artifact_id = src$artifact_id,
      run_id = src$run_id,
      output_name = src$output_name
    )
  )
}

.wb_prov_output_hash <- function(prim, bundle = NULL) .wb_prov_payload_identity(bundle, prim)

#' Validate Replay Of A Persisted Snapshot
#'
#' Replays persisted runs and compares output kind plus content SHA-256 where
#' the snapshot recorded content-verifiable payload identity. Legacy snapshots
#' are reported as structural-only evidence.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param snapshot_id Optional snapshot id. When omitted, the latest snapshot is
#'   used.
#' @param mode Replay input mode: `"symbolic"` or `"literal"`.
#' @param profile Validation profile: `"strict"`, `"kind_only"`, or `"none"`.
#' @param strict If `TRUE`, stop on the first replay error.
#' @param destination_bundle Optional writable source-boundary bundle in which
#'   to execute the replay. Expected identities are always read from `bundle`.
#'   Use this when the persisted outputs in `bundle` are immutable and would
#'   collide with the replayed output identifiers.
#'
#' @return A named list with `summary`, `per_run`, `per_output`, and
#'   `replay_session`.
#'
#' @export
wb_prov_validate_replay <- function(bundle,
                                    snapshot_id = NULL,
                                    mode = c("symbolic", "literal"),
                                    profile = c("strict", "kind_only", "none"),
                                    strict = FALSE,
                                    destination_bundle = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  if (!is.null(destination_bundle)) {
    .wb_assert(inherits(destination_bundle, "scworkbench_bundle"),
               "destination_bundle must be an open scworkbench_bundle")
  }
  .wb_require_pkg("jsonlite", "provenance replay validation")
  mode <- match.arg(mode)
  profile <- match.arg(profile)

  con <- bundle$con
  .wb_migrate_provenance_tables(con)
  sid <- .wb_prov_snapshot_id_or_latest(con, snapshot_id)
  rr <- .wb_prov_get_runs_order(con, sid)
  runs <- rr$runs
  run_order <- rr$run_order
  payload <- .wb_prov_payload_from_runs(runs, run_order, mode = mode)

  expected <- DBI::dbGetQuery(
    con,
    paste0("SELECT run_id, output_name, primitive_kind, output_hash, ", .wb_prov_output_identity_select(con), ", ", .wb_prov_output_replay_select(con),
           " FROM prov_run_outputs WHERE snapshot_id = ? ORDER BY run_id, output_name;"),
    params = list(sid)
  )
  exp_map <- list()
  if (nrow(expected)) {
    for (i in seq_len(nrow(expected))) {
      exp_map[[paste0(expected$run_id[i], "::", expected$output_name[i])]] <- list(
        kind = as.character(expected$primitive_kind[i]),
        structural_fingerprint = as.character(expected$structural_fingerprint[i] %||% expected$output_hash[i]),
        content_sha256 = as.character(expected$content_sha256[i] %||% NA_character_),
        content_identity_scheme = as.character(expected$content_identity_scheme[i] %||% NA_character_),
        verification_level = as.character(expected$verification_level[i] %||% "structural")[1],
        verification_status = as.character(expected$verification_status[i] %||% "legacy_structural_only")[1],
        replay_equivalence_policy = as.character(expected$replay_equivalence_policy[i] %||% "not_comparable")[1],
        replay_equivalence_reference = as.character(expected$replay_equivalence_reference[i] %||% NA_character_)[1]
      )
    }
  }

  replay_map <- list()
  sess <- wb_session_new()
  execution_bundle <- destination_bundle %||% bundle
  per_run <- list()
  per_out <- list()
  ri <- 0L
  oi <- 0L

  rewrite_run_refs <- function(x, replay_map) {
    if (!is.list(x)) return(x)
    if (identical(as.character(x$ref_type %||% "")[1], "run")) {
      old <- as.character(x$run_id %||% "")[1]
      if (nzchar(old) && !is.null(replay_map[[old]])) x$run_id <- replay_map[[old]]
      return(x)
    }
    y <- lapply(x, rewrite_run_refs, replay_map = replay_map)
    if (!is.null(names(x))) names(y) <- names(x)
    y
  }

  for (rid in run_order) {
    idx <- which(as.character(runs$run_id) == rid)[1]
    op_name <- as.character(runs$op_name[idx])
    notes <- as.character(runs$notes[idx] %||% "")[1]
    params <- payload[[rid]]$params %||% list()
    inputs <- payload[[rid]]$inputs %||% list()
    recorded_run_inputs <- jsonlite::fromJSON(
      as.character(runs$inputs_json[idx] %||% "{}"), simplifyVector = FALSE
    )
    selection_error <- tryCatch({
      .wb_verify_cell_set_resolution_records(
        execution_bundle,
        recorded_run_inputs$cell_set_resolutions %||% list(),
        context = "replay"
      )
      NULL
    }, wb_cell_set_resolution_error = function(e) e)
    if (!is.null(selection_error)) {
      if (isTRUE(strict)) stop(selection_error)
      ri <- ri + 1L
      per_run[[ri]] <- data.frame(
        run_id = rid,
        replay_run_id = NA_character_,
        op_name = op_name,
        status = "error",
        error = conditionMessage(selection_error),
        stringsAsFactors = FALSE
      )
      next
    }
    execution_inputs <- .wb_prov_replay_execution_inputs(inputs, params, run_id = rid, op_name = op_name)
    execution_inputs <- rewrite_run_refs(execution_inputs, replay_map = replay_map)

    err <- NULL
    out <- try(
      wb_session_run_op(
        session = sess,
        bundle = execution_bundle,
        op_name = op_name,
        inputs = execution_inputs,
        notes = notes
      ),
      silent = TRUE
    )
    if (inherits(out, "try-error")) {
      err <- as.character(out)
      if (isTRUE(strict)) stop(err, call. = FALSE)
      ri <- ri + 1L
      per_run[[ri]] <- data.frame(
        run_id = rid,
        replay_run_id = NA_character_,
        op_name = op_name,
        status = "error",
        error = err,
        stringsAsFactors = FALSE
      )
      next
    }

    sess <- out$session
    replay_rid <- as.character(out$run$run_id)
    replay_map[[rid]] <- replay_rid

    ri <- ri + 1L
    per_run[[ri]] <- data.frame(
      run_id = rid,
      replay_run_id = replay_rid,
      op_name = op_name,
      status = "ok",
      error = NA_character_,
      stringsAsFactors = FALSE
    )

    outs <- out$run$outputs %||% list()
    for (nm in names(outs)) {
      prim <- outs[[nm]]
      actual_kind <- if (.wb_is_primitive(prim)) as.character(prim$kind %||% "unknown")[1] else "unknown"
      replay_bundle <- wb_session_view(sess)
      actual_identity <- .wb_prov_output_hash(prim, bundle = replay_bundle)
      ex <- exp_map[[paste0(rid, "::", nm)]] %||% list(kind = NA_character_, structural_fingerprint = NA_character_, content_sha256 = NA_character_, verification_level = "structural", verification_status = "missing")
      kind_match <- identical(as.character(ex$kind), as.character(actual_kind))
      content_expected <- identical(as.character(ex$verification_level), "content") &&
        !is.na(ex$content_sha256) && nzchar(ex$content_sha256) &&
        !is.na(ex$content_identity_scheme) && nzchar(ex$content_identity_scheme)
      hash_match <- if (content_expected) {
        identical(as.character(ex$content_identity_scheme), as.character(actual_identity$content_identity_scheme)) &&
          identical(as.character(ex$content_sha256), as.character(actual_identity$content_sha256))
      } else identical(as.character(ex$structural_fingerprint), as.character(actual_identity$structural_fingerprint))
      policy <- as.character(ex$replay_equivalence_policy %||% "not_comparable")[1]
      expected_reference <- as.character(ex$replay_equivalence_reference %||% NA_character_)[1]
      alignment_result <- if (identical(policy, "cell_aligned_embedding")) {
        .wb_replay_space_alignment_reference(replay_bundle, prim)
      } else NULL
      replayed_reference <- if (identical(policy, "loadable_reference") && identical(actual_kind, "model_ref")) {
        .wb_replay_model_reference(prim)
      } else if (identical(policy, "exact_graph_descriptor") && identical(actual_kind, "graph")) {
        actual_identity$graph_descriptor_identity$sha256
      } else if (identical(policy, "cell_aligned_embedding")) {
        as.character(alignment_result$reference %||% NA_character_)[1]
      } else if (policy %in% c("exact_content", "exact_canonical_value")) {
        as.character(actual_identity$content_sha256)
      } else NA_character_
      equivalence_verified <- if (policy %in% c("exact_content", "exact_canonical_value")) {
        isTRUE(kind_match) && isTRUE(hash_match)
      } else if (identical(policy, "exact_graph_descriptor")) {
        isTRUE(kind_match) && identical(actual_kind, "graph") && isTRUE(hash_match) &&
          !is.na(expected_reference) && nzchar(expected_reference) &&
          identical(expected_reference, replayed_reference)
      } else if (identical(policy, "cell_aligned_embedding")) {
        isTRUE(kind_match) && isTRUE(alignment_result$valid) &&
          !is.na(expected_reference) && identical(expected_reference, replayed_reference)
      } else if (identical(policy, "loadable_reference")) {
        loadable <- .wb_replay_model_loadable(replay_bundle, prim)
        isTRUE(kind_match) && !is.na(expected_reference) && identical(expected_reference, replayed_reference) && isTRUE(loadable$ok)
      } else {
        # Legacy records retain their former structural/content comparison;
        # they are not silently upgraded to a declared scientific policy.
        isTRUE(kind_match) && isTRUE(hash_match)
      }

      oi <- oi + 1L
      per_out[[oi]] <- data.frame(
        run_id = rid,
        replay_run_id = replay_rid,
        output_name = as.character(nm),
        expected_kind = as.character(ex$kind),
        actual_kind = as.character(actual_kind),
        expected_hash = if (content_expected) as.character(ex$content_sha256) else as.character(ex$structural_fingerprint),
        actual_hash = if (content_expected) as.character(actual_identity$content_sha256) else as.character(actual_identity$structural_fingerprint),
        verification_level = if (content_expected) "content" else "structural",
        verification_status = if (content_expected) "content_verified" else as.character(ex$verification_status),
        replay_equivalence_policy = policy,
        expected_replay_reference = expected_reference,
        actual_replay_reference = replayed_reference,
        equivalence_verified = isTRUE(equivalence_verified),
        kind_match = isTRUE(kind_match),
        hash_match = isTRUE(hash_match),
        output_match = FALSE,
        stringsAsFactors = FALSE
      )
      hash_required <- identical(profile, "strict")
      kind_required <- !identical(profile, "none")
      per_out[[oi]]$output_match <- if (!kind_required) {
        TRUE
      } else if (hash_required) {
        isTRUE(equivalence_verified)
      } else {
        isTRUE(kind_match)
      }
    }
  }

  run_df <- if (length(per_run)) do.call(rbind, per_run) else data.frame(
    run_id = character(0), replay_run_id = character(0), op_name = character(0),
    status = character(0), error = character(0), stringsAsFactors = FALSE
  )
  out_df <- if (length(per_out)) do.call(rbind, per_out) else data.frame(
    run_id = character(0), replay_run_id = character(0), output_name = character(0),
    expected_kind = character(0), actual_kind = character(0), expected_hash = character(0),
    actual_hash = character(0), verification_level = character(0), verification_status = character(0), replay_equivalence_policy = character(0), expected_replay_reference = character(0), actual_replay_reference = character(0), equivalence_verified = logical(0), kind_match = logical(0), hash_match = logical(0), output_match = logical(0),
    stringsAsFactors = FALSE
  )

  list(
    snapshot_id = sid,
    summary = list(
      profile = profile,
      n_runs = nrow(run_df),
      n_run_errors = sum(run_df$status == "error"),
      n_outputs = nrow(out_df),
      n_kind_mismatch = sum(!out_df$kind_match),
      n_hash_mismatch = sum(!out_df$hash_match),
      valid = (sum(run_df$status == "error") == 0L) && (sum(!out_df$output_match) == 0L)
    ),
    per_run = run_df,
    per_output = out_df,
    replay_session = sess
  )
}

#' Freeze A Provenance Snapshot
#'
#' Writes replay scripts, DAG JSON, run tables, and manifest into `out_dir`.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param out_dir Output directory, created if missing.
#' @param snapshot_id Optional snapshot id. When omitted, the latest snapshot is
#'   used.
#' @param include_literal If `TRUE`, include the literal replay sidecar.
#' @param replay_style Replay script style: `"bench_pretty"` or `"raw_json"`.
#' @param validate_replay If `TRUE`, run [wb_prov_validate_replay()] and write
#'   validation files.
#' @param validation_profile Validation profile passed to
#'   [wb_prov_validate_replay()].
#'
#' @return A named list with `snapshot_id`, `out_dir`, and `files`.
#'
#' @export
wb_freeze_snapshot <- function(bundle,
                               out_dir,
                               snapshot_id = NULL,
                               include_literal = TRUE,
                               replay_style = c("bench_pretty", "raw_json"),
                               validate_replay = TRUE,
                               validation_profile = c("strict", "kind_only", "none")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "freeze snapshot")
  replay_style <- match.arg(replay_style)
  validation_profile <- match.arg(validation_profile)
  .wb_assert(is.character(out_dir) && length(out_dir) == 1 && nzchar(out_dir), "out_dir must be non-empty path")

  con <- bundle$con
  .wb_migrate_provenance_tables(con)
  sid <- .wb_prov_snapshot_id_or_latest(con, snapshot_id)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list()

  # replay scripts
  sym_path <- file.path(out_dir, "replay_symbolic.R")
  sym_txt <- wb_prov_emit_r_script(
    bundle = bundle,
    snapshot_id = sid,
    bundle_dir_literal = bundle$dir %||% "<BUNDLE_DIR>",
    mode = "symbolic",
    style = replay_style
  )
  writeLines(sym_txt, con = sym_path, useBytes = TRUE)
  files$replay_symbolic <- sym_path

  if (isTRUE(include_literal)) {
    lit_path <- file.path(out_dir, "replay_literal.R")
    side_path <- file.path(out_dir, "replay_inputs.rds")
    lit_txt <- wb_prov_emit_r_script(
      bundle = bundle,
      snapshot_id = sid,
      bundle_dir_literal = bundle$dir %||% "<BUNDLE_DIR>",
      mode = "literal",
      style = replay_style,
      sidecar_rds_path = side_path
    )
    lit_txt <- gsub(
      pattern = paste0("readRDS('", side_path, "')"),
      replacement = "readRDS('replay_inputs.rds')",
      x = lit_txt,
      fixed = TRUE
    )
    writeLines(lit_txt, con = lit_path, useBytes = TRUE)
    files$replay_literal <- lit_path
    files$replay_inputs <- side_path
  }

  # DAG JSON
  dag <- wb_prov_dag(bundle, snapshot_id = sid)
  dag_path <- file.path(out_dir, "dag.json")
  jsonlite::write_json(dag, path = dag_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  files$dag_json <- dag_path

  # runs / outputs tables
  runs <- DBI::dbGetQuery(
    con,
    "SELECT run_id, op_name, created_at, notes, run_hash
     FROM prov_runs WHERE snapshot_id = ? ORDER BY created_at, run_id;",
    params = list(sid)
  )
  runs_path <- file.path(out_dir, "runs.csv")
  utils::write.csv(runs, file = runs_path, row.names = FALSE)
  files$runs_csv <- runs_path

  outs <- DBI::dbGetQuery(
    con,
    "SELECT run_id, output_name, primitive_kind, output_hash, artifact_id
     FROM prov_run_outputs WHERE snapshot_id = ? ORDER BY run_id, output_name;",
    params = list(sid)
  )
  outs_path <- file.path(out_dir, "outputs.csv")
  utils::write.csv(outs, file = outs_path, row.names = FALSE)
  files$outputs_csv <- outs_path

  # replay validation
  if (isTRUE(validate_replay)) {
    val <- wb_prov_validate_replay(
      bundle,
      snapshot_id = sid,
      mode = "symbolic",
      profile = validation_profile,
      strict = FALSE
    )
    val_out <- list(
      snapshot_id = as.character(val$snapshot_id %||% sid),
      summary = val$summary %||% list(),
      per_run = val$per_run %||% data.frame(stringsAsFactors = FALSE),
      per_output = val$per_output %||% data.frame(stringsAsFactors = FALSE)
    )
    val_path <- file.path(out_dir, "validation.json")
    jsonlite::write_json(val_out, path = val_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
    files$validation_json <- val_path
  }

  # manifest
  manifest <- list(
    snapshot_id = sid,
    schema_version = .wb_prov_schema_version(),
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    bundle_dir = bundle$dir %||% NA_character_,
    files = files
  )
  man_path <- file.path(out_dir, "manifest.json")
  jsonlite::write_json(manifest, path = man_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  files$manifest_json <- man_path

  list(snapshot_id = sid, out_dir = out_dir, files = files)
}

.wb_prov_param_inline <- function(x) {
  if (is.null(x)) return("NULL")
  if (is.atomic(x)) {
    y <- as.character(x)
    if (!length(y)) return("<empty>")
    if (length(y) > 5L) y <- c(y[1:5], "...")
    return(paste(y, collapse = ","))
  }
  if (is.list(x)) return("<list>")
  as.character(x)
}

.wb_prov_params_inline <- function(params) {
  params <- params %||% list()
  if (!is.list(params) || !length(params)) return("none")
  nms <- names(params) %||% rep("", length(params))
  out <- character(0)
  for (i in seq_along(params)) {
    nm <- as.character(nms[[i]] %||% "")[1]
    if (!nzchar(nm)) nm <- paste0("param", i)
    out <- c(out, paste0(nm, "=", .wb_prov_param_inline(params[[i]])))
  }
  paste(out, collapse = "; ")
}

.wb_prov_write_report_scaffold <- function(bundle, snapshot_id, out_dir, freeze_files) {
  .wb_require_pkg("jsonlite", "freeze report scaffold")
  con <- bundle$con
  runs <- .wb_prov_select_runs(con, snapshot_id)

  md <- c(
    "# Analysis Freeze Report",
    "",
    paste0("- snapshot_id: ", snapshot_id),
    paste0("- schema_version: ", .wb_prov_schema_version()),
    paste0("- generated_at: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
    ""
  )

  if (!nrow(runs)) {
    md <- c(md, "No runs in snapshot.", "")
  } else {
    md <- c(md, "## Methods (Draft)", "")
    for (i in seq_len(nrow(runs))) {
      rid <- as.character(runs$run_id[i])
      op_name <- as.character(runs$op_name[i])
      params <- jsonlite::fromJSON(as.character(runs$params_json[i] %||% "{}"), simplifyVector = FALSE)
      sym <- jsonlite::fromJSON(as.character(runs$symbolic_inputs_json[i] %||% "null"), simplifyVector = FALSE)
      cell_set <- as.character(sym$cell_set %||% "all")[1]
      ptxt <- .wb_prov_params_inline(params)
      md <- c(
        md,
        paste0("- `", rid, "`: op `", op_name, "` on cell_set `", cell_set, "`. Params: ", ptxt, ".")
      )
    }
    md <- c(md, "")
  }

  md <- c(md, "## Files", "")
  fn <- names(freeze_files)
  if (!length(fn)) {
    md <- c(md, "- none", "")
  } else {
    for (nm in fn) {
      md <- c(md, paste0("- ", nm, ": ", basename(as.character(freeze_files[[nm]]))))
    }
    md <- c(md, "")
  }

  path <- file.path(out_dir, "report_draft.md")
  writeLines(md, con = path, useBytes = TRUE)
  path
}

#' Freeze A Provenance Packet
#'
#' Convenience wrapper for agent/client workflows. Runs `wb_freeze_snapshot()`
#' and optionally adds a lightweight `report_draft.md` methods scaffold.
#'
#' @inheritParams wb_freeze_snapshot
#' @param include_report If `TRUE`, emit `report_draft.md`.
#'
#' @return A named list with `snapshot_id`, `out_dir`, and `files`.
#'
#' @export
wb_freeze_packet <- function(bundle,
                             out_dir,
                             snapshot_id = NULL,
                             include_literal = TRUE,
                             replay_style = c("bench_pretty", "raw_json"),
                             validate_replay = TRUE,
                             validation_profile = c("strict", "kind_only", "none"),
                             include_report = TRUE) {
  replay_style <- match.arg(replay_style)
  validation_profile <- match.arg(validation_profile)

  fr <- wb_freeze_snapshot(
    bundle = bundle,
    out_dir = out_dir,
    snapshot_id = snapshot_id,
    include_literal = include_literal,
    replay_style = replay_style,
    validate_replay = validate_replay,
    validation_profile = validation_profile
  )

  files <- fr$files %||% list()
  if (isTRUE(include_report)) {
    report_path <- .wb_prov_write_report_scaffold(
      bundle = bundle,
      snapshot_id = fr$snapshot_id,
      out_dir = out_dir,
      freeze_files = files
    )
    files$report_draft_md <- report_path
  }

  list(snapshot_id = fr$snapshot_id, out_dir = fr$out_dir, files = files)
}
