# Canonical file-backed dense-space storage.

.wb_space_payload_schema <- function() "scworkbench.dense-space.hdf5.v1"
.wb_space_payload_storage <- function() "hdf5:dense-space:v1"
.wb_space_payload_content_scheme <- function() unname(.wb_content_identity_schemes()[["dense_space"]])

.wb_space_payload_transaction_collector <- function() {
  x <- new.env(parent = emptyenv()); x$new <- character(); x$retire <- character(); x
}

.wb_space_payload_transaction_finish <- function(collector, committed) {
  paths <- if (isTRUE(committed)) collector$retire else collector$new
  for (path in unique(paths)) if (file.exists(path)) unlink(path, force = TRUE)
  invisible(TRUE)
}

.wb_ensure_space_payloads_table <- function(con) {
  if (.wb_schema_component_is_current(con, "space_payloads")) return(invisible(TRUE))
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS space_payloads (
      space_id TEXT PRIMARY KEY,
      path TEXT NOT NULL UNIQUE,
      schema_version TEXT NOT NULL,
      n_cells INTEGER NOT NULL,
      n_dims INTEGER NOT NULL,
      cell_ids_sha256 TEXT NOT NULL,
      dim_labels_json TEXT NOT NULL,
      dtype TEXT NOT NULL,
      endianness TEXT NOT NULL,
      chunk_rows INTEGER NOT NULL,
      chunk_dims INTEGER NOT NULL,
      content_sha256 TEXT NOT NULL,
      content_identity_scheme TEXT NOT NULL,
      provenance_identity TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(space_id) REFERENCES spaces(space_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_payloads_path ON space_payloads(path);")
  invisible(TRUE)
}

.wb_space_payload_require_runtime <- function() {
  .wb_require_pkg("rhdf5", "file-backed dense-space storage")
  invisible(TRUE)
}

.wb_space_payload_normalize <- function(coords) {
  if (is.data.frame(coords)) {
    if ("cell_id" %in% names(coords)) {
      ids <- as.character(coords$cell_id)
      mat <- as.matrix(coords[, setdiff(names(coords), "cell_id"), drop = FALSE])
      rownames(mat) <- ids
    } else {
      mat <- as.matrix(coords)
    }
  } else {
    mat <- as.matrix(coords)
  }
  .wb_assert(is.matrix(mat) && nrow(mat) > 0L && ncol(mat) > 0L,
             "Dense-space coordinates must be a non-empty matrix.")
  .wb_assert(!is.null(rownames(mat)), "Dense-space coordinates require rownames = cell_id.")
  ids <- as.character(rownames(mat))
  .wb_assert(!anyNA(ids) && all(nzchar(ids)) && !anyDuplicated(ids),
             "Dense-space cell identities must be non-empty and unique.")
  storage.mode(mat) <- "double"
  .wb_assert(!anyNA(mat) && all(is.finite(mat)),
             "Dense-space coordinates must contain only finite numeric values.")
  labels <- colnames(mat)
  if (is.null(labels) || length(labels) != ncol(mat) || anyNA(labels) || any(!nzchar(labels))) {
    labels <- paste0("dim", seq_len(ncol(mat)))
  }
  .wb_assert(!anyDuplicated(labels), "Dense-space dimension labels must be unique.")
  colnames(mat) <- as.character(labels)
  mat
}

.wb_space_payload_file_name <- function(bundle, space_id) {
  root <- file.path(bundle$dir, "space_payloads")
  pending <- file.path(root, ".pending")
  .wb_allocate_identifier(
    prefix = "space_", n = 24L, purpose = "dense-space payload path",
    occupied = function(candidate) {
      file.exists(file.path(root, paste0(candidate, ".h5"))) ||
        file.exists(file.path(pending, paste0(candidate, ".h5"))) ||
        .wb_db_identifier_exists(bundle$con, "space_payloads", "path",
                                 file.path("space_payloads", paste0(candidate, ".h5")))
    }
  ) |> paste0(".h5")
}

.wb_space_payload_h5_metadata <- function(path) {
  .wb_space_payload_require_runtime()
  listed <- tryCatch(rhdf5::h5ls(path, recursive = FALSE), error = function(e) data.frame())
  .wb_assert(nrow(listed) > 0L && all(c("coordinates", "cell_ids", "dim_labels") %in% listed$name),
             "SPACE_PAYLOAD_DATASET_MISSING: required HDF5 datasets are absent.")
  attrs <- tryCatch(rhdf5::h5readAttributes(path, "/"), error = function(e) list())
  coords_row <- listed[listed$name == "coordinates", , drop = FALSE]
  dims <- as.integer(strsplit(gsub("[ ]", "", as.character(coords_row$dim[[1L]])), "x", fixed = TRUE)[[1L]])
  # h5ls reports dimensions as "rows x columns"; fall back to a bounded
  # one-cell read only when an older rhdf5 display format differs.
  if (length(dims) != 2L || anyNA(dims)) {
    probe <- rhdf5::h5read(path, "coordinates", index = list(1L, NULL))
    dims <- c(1L, length(probe))
  }
  list(
    schema_version = as.character(attrs$schema_version %||% "")[1L],
    space_id = as.character(attrs$space_id %||% "")[1L],
    n_cells = as.integer(attrs$n_cells %||% dims[[1L]])[1L],
    n_dims = as.integer(attrs$n_dims %||% dims[[2L]])[1L],
    dtype = as.character(attrs$dtype %||% "")[1L],
    endianness = as.character(attrs$endianness %||% "")[1L],
    chunk_rows = as.integer(attrs$chunk_rows %||% NA_integer_)[1L],
    chunk_dims = as.integer(attrs$chunk_dims %||% NA_integer_)[1L],
    cell_ids = as.character(rhdf5::h5read(path, "cell_ids")),
    dim_labels = as.character(rhdf5::h5read(path, "dim_labels")),
    physical_dims = dims
  )
}

.wb_space_payload_validate_file <- function(path, expected = NULL, verify_hash = FALSE,
                                            validate_values = FALSE) {
  .wb_assert(file.exists(path) && !dir.exists(path),
             "SPACE_PAYLOAD_MISSING: dense-space payload file is absent.")
  meta <- .wb_space_payload_h5_metadata(path)
  .wb_assert(identical(meta$schema_version, .wb_space_payload_schema()),
             "SPACE_PAYLOAD_VERSION_UNKNOWN: unsupported dense-space schema version.")
  .wb_assert(meta$n_cells > 0L && meta$n_dims > 0L &&
               identical(meta$physical_dims, c(meta$n_cells, meta$n_dims)),
             "SPACE_PAYLOAD_SHAPE_MISMATCH: HDF5 shape contradicts declared shape.")
  .wb_assert(length(meta$cell_ids) == meta$n_cells && !anyNA(meta$cell_ids) &&
               all(nzchar(meta$cell_ids)) && !anyDuplicated(meta$cell_ids),
             "SPACE_PAYLOAD_CELL_IDENTITY_INVALID: ordered cell identities are invalid.")
  .wb_assert(length(meta$dim_labels) == meta$n_dims && !anyNA(meta$dim_labels) &&
               all(nzchar(meta$dim_labels)) && !anyDuplicated(meta$dim_labels),
             "SPACE_PAYLOAD_DIMENSION_IDENTITY_INVALID: dimension labels are invalid.")
  .wb_assert(identical(meta$dtype, "float64") && meta$endianness %in% c("little", "big"),
             "SPACE_PAYLOAD_NUMERIC_CONTRACT_INVALID: dtype or endianness is unsupported.")
  if (isTRUE(validate_values)) {
    chunk <- max(1L, meta$chunk_rows)
    for (start in seq.int(1L, meta$n_cells, by = chunk)) {
      rows <- start:min(meta$n_cells, start + chunk - 1L)
      values <- rhdf5::h5read(path, "coordinates", index = list(rows, seq_len(meta$n_dims)))
      .wb_assert(!anyNA(values) && all(is.finite(values)),
                 "SPACE_PAYLOAD_VALUES_INVALID: coordinate payload contains non-finite values.")
    }
  }
  sha <- if (isTRUE(verify_hash)) .wb_prov_sha256_file(path) else NA_character_
  if (!is.null(expected)) {
    value <- function(x) { x <- as.character(x %||% "")[1L]; if (is.na(x)) "" else x }
    .wb_assert(identical(meta$schema_version, value(expected$schema_version)) &&
                 identical(meta$dtype, value(expected$dtype)) &&
                 identical(meta$endianness, value(expected$endianness)) &&
                 identical(meta$chunk_rows, as.integer(expected$chunk_rows)[1L]) &&
                 identical(meta$chunk_dims, as.integer(expected$chunk_dims)[1L]),
               "SPACE_PAYLOAD_REGISTRY_MISMATCH: payload storage metadata differs from registry.")
    .wb_assert(identical(meta$space_id, value(expected$space_id)),
               "SPACE_PAYLOAD_REGISTRY_MISMATCH: payload space_id differs from registry.")
    .wb_assert(identical(meta$n_cells, as.integer(expected$n_cells)[1L]) &&
                 identical(meta$n_dims, as.integer(expected$n_dims)[1L]),
               "SPACE_PAYLOAD_REGISTRY_MISMATCH: payload shape differs from registry.")
    .wb_assert(identical(.wb_prov_sha256_object(meta$cell_ids), value(expected$cell_ids_sha256)),
               "SPACE_PAYLOAD_CELL_ORDER_MISMATCH: ordered cell identity hash differs from registry.")
    .wb_assert(identical(meta$dim_labels,
                         as.character(jsonlite::fromJSON(value(expected$dim_labels_json)))),
               "SPACE_PAYLOAD_DIMENSION_IDENTITY_INVALID: dimension labels differ from registry.")
    if (isTRUE(verify_hash)) {
      .wb_assert(identical(tolower(sha), tolower(value(expected$content_sha256))),
                 "SPACE_PAYLOAD_CONTENT_HASH_MISMATCH: payload bytes differ from registry identity.")
    }
    .wb_assert(identical(value(expected$content_identity_scheme), .wb_space_payload_content_scheme()),
               "SPACE_PAYLOAD_IDENTITY_SCHEME_INVALID: registry content identity scheme is unsupported.")
  }
  c(meta, list(content_sha256 = sha))
}

.wb_space_payload_registry_row <- function(bundle, space_id, required = TRUE) {
  .wb_ensure_space_payloads_table(bundle$con)
  row <- DBI::dbGetQuery(bundle$con, "SELECT * FROM space_payloads WHERE space_id = ?;",
                         params = list(as.character(space_id)[1L]))
  if (isTRUE(required)) .wb_assert(nrow(row) == 1L,
                                   paste0("SPACE_PAYLOAD_REGISTRY_MISSING: ", space_id))
  row
}

.wb_space_payload_path <- function(bundle, registry, must_exist = TRUE) {
  rel <- as.character(registry$path[[1L]])
  status <- .wb_path_status(bundle$dir, rel,
                            expected_type = "file", must_exist = must_exist,
                            purpose = "dense-space payload")
  # Session overlays link immutable committed leaves into a private tree. The
  # only accepted escape is the identical relative path under the explicitly
  # bound staging source; arbitrary links remain fail-closed.
  if (!isTRUE(status$ok) && identical(status$code, "PATH_SYMLINK_ESCAPE") &&
      nzchar(as.character(bundle$staging_source_dir %||% "")[1L])) {
    source <- .wb_path_status(bundle$staging_source_dir, rel, expected_type = "file",
                              must_exist = must_exist, purpose = "session source dense-space payload")
    candidate <- file.path(bundle$dir, rel)
    resolved_candidate <- normalizePath(candidate, winslash = "/", mustWork = must_exist)
    if (isTRUE(source$ok) && identical(resolved_candidate, source$absolute)) return(source$absolute)
  }
  .wb_assert(isTRUE(status$ok), paste0(status$code, ": invalid dense-space payload path."))
  status$absolute
}

.wb_space_payload_write <- function(bundle, space_id, coords, source = "analysis",
                                    description = NULL, overwrite = FALSE,
                                    provenance_identity = NULL,
                                    authenticated_replace = FALSE) {
  .wb_assert_bundle_writable(bundle, "dense-space payload mutation")
  .wb_space_payload_require_runtime()
  mat <- .wb_space_payload_normalize(coords)
  cells <- rownames(mat)
  dims <- colnames(mat)
  canonical <- as.character(DBI::dbGetQuery(
    bundle$con,
    "SELECT cell_id FROM cells WHERE cell_id IN (SELECT value FROM json_each(?));",
    params = list(jsonlite::toJSON(as.list(cells), auto_unbox = TRUE))
  )$cell_id)
  .wb_assert(length(canonical) == length(cells) && setequal(canonical, cells),
             "Dense-space payload contains cells outside the canonical bundle universe.")

  root <- file.path(bundle$dir, "space_payloads")
  pending_root <- file.path(root, ".pending")
  dir.create(pending_root, recursive = TRUE, showWarnings = FALSE)
  .wb_assert(dir.exists(pending_root), "Failed to create dense-space pending directory.")
  file_name <- .wb_space_payload_file_name(bundle, space_id)
  pending <- file.path(pending_root, file_name)
  final_rel <- file.path("space_payloads", file_name)
  final <- file.path(bundle$dir, final_rel)
  published <- FALSE
  registered <- FALSE
  on.exit({
    if (file.exists(pending)) unlink(pending, force = TRUE)
    if (isTRUE(published) && !isTRUE(registered) && file.exists(final)) unlink(final, force = TRUE)
  }, add = TRUE)

  chunk_rows <- min(nrow(mat), 1024L)
  chunk_dims <- min(ncol(mat), 16L)
  .wb_assert(isTRUE(rhdf5::h5createFile(pending)), "Failed to create dense-space HDF5 payload.")
  rhdf5::h5createDataset(pending, "coordinates", dims = dim(mat),
                         chunk = c(chunk_rows, chunk_dims), storage.mode = "double", level = 0L)
  rhdf5::h5write(mat, pending, "coordinates")
  rhdf5::h5write(cells, pending, "cell_ids")
  rhdf5::h5write(dims, pending, "dim_labels")
  endian <- if (.Platform$endian == "little") "little" else "big"
  h5 <- rhdf5::H5Fopen(pending)
  on.exit(if (!is.null(h5)) try(rhdf5::H5Fclose(h5), silent = TRUE), add = TRUE)
  rhdf5::h5writeAttribute(.wb_space_payload_schema(), h5, "schema_version")
  rhdf5::h5writeAttribute(as.character(space_id)[1L], h5, "space_id")
  rhdf5::h5writeAttribute(as.integer(nrow(mat)), h5, "n_cells")
  rhdf5::h5writeAttribute(as.integer(ncol(mat)), h5, "n_dims")
  rhdf5::h5writeAttribute("float64", h5, "dtype")
  rhdf5::h5writeAttribute(endian, h5, "endianness")
  rhdf5::h5writeAttribute(as.integer(chunk_rows), h5, "chunk_rows")
  rhdf5::h5writeAttribute(as.integer(chunk_dims), h5, "chunk_dims")
  rhdf5::H5Fclose(h5)
  h5 <- NULL

  inspected <- .wb_space_payload_validate_file(pending, verify_hash = TRUE, validate_values = TRUE)
  row <- data.frame(
    space_id = as.character(space_id)[1L], path = final_rel,
    schema_version = .wb_space_payload_schema(), n_cells = nrow(mat), n_dims = ncol(mat),
    cell_ids_sha256 = .wb_prov_sha256_object(cells),
    dim_labels_json = jsonlite::toJSON(as.character(dims), auto_unbox = FALSE),
    dtype = "float64", endianness = endian, chunk_rows = chunk_rows, chunk_dims = chunk_dims,
    content_sha256 = inspected$content_sha256,
    content_identity_scheme = .wb_space_payload_content_scheme(),
    provenance_identity = as.character(provenance_identity %||% source)[1L],
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), stringsAsFactors = FALSE
  )

  .wb_with_bundle_writer_lock(bundle, operation = "dense-space payload publication", code = {
    existing <- DBI::dbGetQuery(bundle$con, "SELECT * FROM spaces WHERE space_id = ?;",
                                params = list(space_id))
    if (nrow(existing) && !isTRUE(overwrite)) {
      stop("space_id already exists: ", space_id, " (set overwrite=TRUE to replace)", call. = FALSE)
    }
    if (nrow(existing) && !isTRUE(authenticated_replace))
      .wb_entity_assert_replaceable(bundle, "space", space_id,
        action = "overwrite")
    .wb_assert(isTRUE(file.rename(pending, final)), "Failed atomic publication of dense-space payload.")
    published <<- TRUE
    old_path <- if (nrow(existing)) {
      old <- DBI::dbGetQuery(bundle$con, "SELECT path FROM space_payloads WHERE space_id = ?;",
                             params = list(space_id))
      if (nrow(old)) as.character(old$path[[1L]]) else ""
    } else ""
    ok <- FALSE
    on.exit(if (!isTRUE(ok) && file.exists(final)) unlink(final, force = TRUE), add = TRUE)
    hook <- getOption("scworkbench.space_payload_publication_hook", NULL)
    if (is.function(hook)) hook(bundle, row)
    write_registry <- function() {
      if (nrow(existing)) {
        DBI::dbExecute(bundle$con, "DELETE FROM space_payloads WHERE space_id = ?;",
                       params = list(space_id))
        DBI::dbExecute(bundle$con,
          "UPDATE spaces SET source=?, dims=?, storage=?, description=? WHERE space_id=?;",
          params = list(source, as.integer(ncol(mat)), .wb_space_payload_storage(),
                        description %||% space_id, space_id))
      } else {
        DBI::dbExecute(bundle$con,
          "INSERT INTO spaces(space_id,source,dims,storage,description) VALUES(?,?,?,?,?);",
          params = list(space_id, source, as.integer(ncol(mat)), .wb_space_payload_storage(),
                        description %||% space_id))
      }
      .wb_db_append_chunked(bundle$con, "space_payloads", row)
    }
    collector <- getOption("scworkbench.space_payload_transaction_collector", NULL)
    if (is.environment(collector)) write_registry() else DBI::dbWithTransaction(bundle$con, write_registry())
    ok <- TRUE
    registered <<- TRUE
    old_abs <- ""
    if (nzchar(old_path) && !identical(old_path, final_rel)) {
      old_status <- .wb_path_status(bundle$dir, old_path, expected_type = "file", must_exist = FALSE,
                                    purpose = "superseded dense-space payload")
      if (isTRUE(old_status$ok)) old_abs <- old_status$absolute
    }
    if (is.environment(collector)) {
      collector$new <- unique(c(collector$new, final))
      if (nzchar(old_abs)) collector$retire <- unique(c(collector$retire, old_abs))
    } else if (nzchar(old_abs) && file.exists(old_abs)) {
      unlink(old_abs, force = TRUE)
    }
  })
  invisible(row)
}

.wb_space_payload_read <- function(bundle, space_id, cells = NULL, dims = NULL,
                                   drop_missing = FALSE) {
  .wb_space_payload_require_runtime()
  registry <- .wb_space_payload_registry_row(bundle, space_id)
  path <- .wb_space_payload_path(bundle, registry, must_exist = TRUE)
  meta <- .wb_space_payload_validate_file(path, expected = registry, verify_hash = FALSE,
                                          validate_values = FALSE)
  all_cells <- meta$cell_ids
  requested_cells <- if (is.null(cells)) {
    canonical <- wb_cells(bundle, cell_set = "all")
    canonical[canonical %in% all_cells]
  } else as.character(cells)
  rows <- match(requested_cells, all_cells)
  if (isTRUE(drop_missing)) {
    keep <- !is.na(rows); rows <- rows[keep]; requested_cells <- requested_cells[keep]
  } else {
    .wb_assert(!anyNA(rows), "Some requested cells are absent from this space payload.")
  }
  requested_dims <- if (is.null(dims)) seq_len(meta$n_dims) else as.integer(dims)
  .wb_assert(length(requested_dims) > 0L && !anyNA(requested_dims) &&
               all(requested_dims >= 1L & requested_dims <= meta$n_dims) && !anyDuplicated(requested_dims),
             "Requested dense-space dimensions are invalid.")
  if (!length(rows)) {
    out <- matrix(numeric(), nrow = 0L, ncol = length(requested_dims))
  } else {
    row_unique <- sort(unique(rows)); dim_unique <- sort(unique(requested_dims))
    block <- rhdf5::h5read(path, "coordinates", index = list(row_unique, dim_unique))
    block <- matrix(as.numeric(block), nrow = length(row_unique), ncol = length(dim_unique))
    out <- block[match(rows, row_unique), match(requested_dims, dim_unique), drop = FALSE]
  }
  rownames(out) <- requested_cells
  colnames(out) <- meta$dim_labels[requested_dims]
  attr(out, "scworkbench_payload_read") <- list(
    rows_read = length(unique(rows)), dims_read = length(unique(requested_dims)),
    values_read = length(unique(rows)) * length(unique(requested_dims)),
    total_values = meta$n_cells * meta$n_dims, path = as.character(registry$path[[1L]])
  )
  out
}

.wb_space_payload_summary <- function(bundle, space_id, verify_hash = FALSE,
                                      workspace = NULL, staging_bundle = NULL) {
  registry <- .wb_space_payload_registry_row(bundle, space_id)
  path <- if (!is.null(workspace) || !is.null(staging_bundle)) {
    .wb_prov_resolve_payload_location(
      bundle, as.character(registry$path[[1L]]), workspace = workspace,
      staging_bundle = staging_bundle, kind = "dense-space payload", id = space_id
    )
  } else .wb_space_payload_path(bundle, registry, must_exist = TRUE)
  meta <- .wb_space_payload_validate_file(path, expected = registry,
                                          verify_hash = verify_hash, validate_values = FALSE)
  lower <- rep(Inf, meta$n_dims); upper <- rep(-Inf, meta$n_dims); finite <- TRUE
  for (start in seq.int(1L, meta$n_cells, by = max(1L, meta$chunk_rows))) {
    rows <- start:min(meta$n_cells, start + max(1L, meta$chunk_rows) - 1L)
    block <- rhdf5::h5read(path, "coordinates", index = list(rows, seq_len(meta$n_dims)))
    block <- matrix(as.numeric(block), nrow = length(rows), ncol = meta$n_dims)
    finite <- finite && !anyNA(block) && all(is.finite(block))
    lower <- pmin(lower, apply(block, 2L, min))
    upper <- pmax(upper, apply(block, 2L, max))
  }
  list(registry = registry, meta = meta, cells = meta$cell_ids,
       finite = finite, nondegenerate = meta$n_cells > 1L && all(upper > lower),
       complete = TRUE)
}

.wb_space_payload_delete <- function(bundle, space_id) {
  row <- .wb_space_payload_registry_row(bundle, space_id, required = FALSE)
  if (!nrow(row)) return(invisible(FALSE))
  path <- .wb_space_payload_path(bundle, row, must_exist = FALSE)
  DBI::dbExecute(bundle$con, "DELETE FROM space_payloads WHERE space_id = ?;", params = list(space_id))
  if (file.exists(path)) unlink(path, force = TRUE)
  invisible(TRUE)
}

.wb_space_payload_merge_write <- function(bundle, space_id, coords, source = "attach",
                                          description = NULL, overwrite_cells = TRUE) {
  incoming <- .wb_space_payload_normalize(coords)
  exists <- DBI::dbGetQuery(bundle$con, "SELECT space_id FROM spaces WHERE space_id = ?;",
                            params = list(space_id))
  if (!nrow(exists)) {
    return(.wb_space_payload_write(bundle, space_id, incoming, source = source,
                                   description = description, overwrite = FALSE,
                                   provenance_identity = source))
  }
  current <- .wb_as_coord_matrix(wb_space(bundle, space_id))
  .wb_assert(ncol(current) == ncol(incoming),
             "Dense-space merge dimension count differs from the registered payload.")
  colnames(incoming) <- colnames(current)
  overlap <- intersect(rownames(current), rownames(incoming))
  .wb_assert(isTRUE(overwrite_cells) || !length(overlap),
             "Dense-space merge contains existing cells and overwrite_cells=FALSE.")
  combined <- rbind(current[!rownames(current) %in% rownames(incoming), , drop = FALSE], incoming)
  .wb_space_payload_write(bundle, space_id, combined, source = source,
                          description = description, overwrite = TRUE,
                          provenance_identity = source)
}
