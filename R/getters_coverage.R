#' Cells with complete coordinates for a space
#'
#' Returns canonical cell IDs with non-missing coordinates for every requested
#' dimension. When `dims` is omitted, all registered dimensions are required.
#' For wide 2D spaces, dimension 1 tests `x`, dimension 2 tests `y`, and
#' requesting both requires both coordinates.
#'
#' @param bundle scworkbench bundle handle.
#' @param space_id Space identifier.
#' @param dims Optional unique positive integer vector of required dimensions.
#'
#' @return Character vector of canonical `cell_id` values with complete
#'   coordinates, in bundle order.
#' @export
wb_cells_with_space <- function(bundle, space_id, dims = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  .wb_assert(is.character(space_id) && length(space_id) == 1L && !is.na(space_id) && nzchar(space_id),
             "space_id must be a single non-empty string")
  con <- bundle$con
  row <- wb_spaces(bundle)
  row <- row[row$space_id == space_id, , drop = FALSE]
  .wb_assert(nrow(row) == 1L, paste0("Unknown space_id: ", space_id))

  n_dims <- as.integer(row$dims[[1]])
  .wb_assert(length(n_dims) == 1L && !is.na(n_dims) && n_dims >= 2L,
             paste0("Space '", space_id, "' has invalid registered dimensions."))
  if (is.null(dims)) dims <- seq_len(n_dims)
  dims_num <- suppressWarnings(as.numeric(dims))
  .wb_assert(length(dims_num) > 0L && !anyNA(dims_num) && all(is.finite(dims_num)) &&
               all(dims_num == floor(dims_num)),
             "dims must contain finite integers")
  dims <- as.integer(dims_num)
  .wb_assert(!anyDuplicated(dims), "dims must not contain duplicates")
  .wb_assert(all(dims >= 1L & dims <= n_dims),
             paste0("dims for space '", space_id, "' must be between 1 and ", n_dims, "."))

  if (identical(as.character(row$storage[[1]]), .wb_space_payload_storage())) {
    payload <- .wb_space_payload_registry_row(bundle, space_id)
    path <- .wb_space_payload_path(bundle, payload, must_exist = TRUE)
    meta <- .wb_space_payload_validate_file(path, expected = payload, verify_hash = FALSE)
    have <- meta$cell_ids
  } else if (identical(as.character(row$storage[[1]]), "wide:space_2d")) {
    .wb_assert(all(dims %in% 1:2), paste0("Wide 2D space '", space_id, "' only provides dimensions 1 and 2."))
    complete_clause <- if (identical(dims, 1L)) {
      "x IS NOT NULL"
    } else if (identical(dims, 2L)) {
      "y IS NOT NULL"
    } else {
      "x IS NOT NULL AND y IS NOT NULL"
    }
    have <- DBI::dbGetQuery(
      con,
      paste0("SELECT cell_id FROM space_2d WHERE space_id = ? AND ", complete_clause, ";"),
      params = list(space_id)
    )$cell_id
  } else {
    cl <- .wb_sql_in_clause(dims)
    q <- paste0(
      "SELECT cell_id FROM space_coords ",
      "WHERE space_id = ? AND dim ", cl$sql, " AND value IS NOT NULL ",
      "GROUP BY cell_id HAVING COUNT(DISTINCT dim) = ?;"
    )
    have <- DBI::dbGetQuery(con, q, params = c(list(space_id), cl$params, length(dims)))$cell_id
  }

  canonical <- wb_cells(bundle, cell_set = "all")
  unknown <- setdiff(as.character(have), canonical)
  .wb_assert(!length(unknown), paste0("Space '", space_id, "' contains unknown cell IDs: ", paste(head(unknown, 10L), collapse = ", ")))
  canonical[canonical %in% have]
}

#' Cells available for a given matrix
#'
#' Resolves exact matrix coverage from fragment cell identities. Legacy matrix
#' rows without fragments are accepted only when their registered cell count is
#' equal to the complete bundle universe. Fragment cell identities must be
#' disjoint within one logical matrix.
#'
#' @param bundle scworkbench bundle handle.
#' @param matrix_id Matrix identifier.
#'
#' @return Character vector of `cell_id` in canonical order, or empty if
#'   `matrix_id` is unknown.
#' @export
wb_cells_with_matrix <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && !is.na(matrix_id) && nzchar(matrix_id),
             "matrix_id must be a single non-empty string")
  con <- bundle$con
  .wb_assert(.wb_table_exists(con, "matrices"), "matrices table not found in SQLite")
  row <- DBI::dbGetQuery(con, "SELECT matrix_id, n_cells FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  if (!nrow(row)) return(character(0))

  canonical <- wb_cells(bundle, cell_set = "all")
  frags <- tryCatch(wb_matrix_fragments(bundle, matrix_id), error = function(e) data.frame())
  if (!nrow(frags)) {
    .wb_assert(!is.na(row$n_cells[[1]]) && as.integer(row$n_cells[[1]]) == length(canonical),
               paste0("Matrix '", matrix_id, "' has no recoverable fragment cell identities; exact coverage cannot be established."))
    return(canonical)
  }

  have <- character(0)
  for (i in seq_len(nrow(frags))) {
    raw <- frags$cell_ids_json[[i]]
    ids <- character(0)
    if (!is.null(raw) && !is.na(raw) && nzchar(raw)) {
      ids <- tryCatch(as.character(jsonlite::fromJSON(raw)), error = function(e) character(0))
    }
    if (!length(ids) && .wb_table_exists(con, "matrix_fragment_cells")) {
      ids <- DBI::dbGetQuery(
        con, "SELECT cell_id FROM matrix_fragment_cells WHERE fragment_id = ? ORDER BY rowid;",
        params = list(as.character(frags$fragment_id[[i]]))
      )$cell_id
    }
    .wb_assert(length(ids) > 0L, paste0("Matrix fragment '", frags$fragment_id[[i]], "' has no recoverable cell identities."))
    .wb_assert(!anyNA(ids) && all(nzchar(ids)), paste0("Matrix fragment '", frags$fragment_id[[i]], "' has missing cell identities."))
    .wb_assert(!anyDuplicated(ids), paste0("Matrix fragment '", frags$fragment_id[[i]], "' has duplicate cell identities."))
    unknown <- setdiff(ids, canonical)
    .wb_assert(!length(unknown), paste0("Matrix fragment '", frags$fragment_id[[i]], "' contains unknown cell IDs: ", paste(head(unknown, 10L), collapse = ", ")))
    repeated <- intersect(have, ids)
    .wb_assert(!length(repeated),
               paste0("Matrix '", matrix_id, "' contains cell IDs in multiple fragments: ",
                      paste(head(repeated, 10L), collapse = ", ")))
    have <- c(have, ids)
  }
  canonical[canonical %in% have]
}

.wb_coverage_ordered_intersect <- function(x, y) x[x %in% y]

.wb_coverage_validate_ids <- function(ids, canonical, label, allow_duplicates = FALSE) {
  ids <- as.character(ids)
  .wb_assert(!anyNA(ids) && all(nzchar(ids)), paste0(label, " contains missing or empty cell IDs."))
  if (!isTRUE(allow_duplicates)) {
    .wb_assert(!anyDuplicated(ids), paste0(label, " contains duplicate cell IDs."))
  }
  unknown <- setdiff(unique(ids), canonical)
  .wb_assert(!length(unknown), paste0(label, " contains unknown cell IDs: ", paste(head(unknown, 10L), collapse = ", ")))
  unique(ids)
}

.wb_coverage_model_cells <- function(bundle, primitive) {
  engine <- tolower(as.character(primitive$engine %||% "")[1])
  if (engine %in% c("peakvi", "scvi")) return(NULL)

  cells <- primitive$cells %||% NULL
  obj <- primitive$model_obj %||% NULL
  if (is.null(cells) && !is.null(obj)) {
    if (inherits(obj, "SlingshotDataSet")) {
      cells <- rownames(methods::slot(obj, "reducedDim"))
    } else {
      cells <- tryCatch(colnames(obj), error = function(e) NULL)
    }
  }
  if (!is.null(cells) && length(cells)) return(as.character(cells))

  associated <- as.character(primitive$in_space_id %||% primitive$model_space_id %||% "")[1]
  if (nzchar(associated) && associated %in% wb_spaces(bundle)$space_id) {
    return(wb_cells_with_space(bundle, associated))
  }
  NULL
}

.wb_coverage_dims <- function(name, kind, primitive, inputs) {
  if (identical(kind, "space_2d")) return(1:2)
  specific <- inputs[[paste0(name, "_dims")]] %||% NULL
  if (!is.null(specific)) return(specific)
  if (name %in% c("space", "fit_space", "in_space") && !is.null(inputs$dims)) return(inputs$dims)
  primitive$dims %||% NULL
}

.wb_primitive_cell_coverage <- function(bundle, name, kind, primitive, inputs, mode = "cell_indexed") {
  canonical <- wb_cells(bundle, cell_set = "all")
  if (mode %in% c("reference_only", "reference_only_explicit_query_space")) {
    return(list(cells = NULL, source_id = NULL, dims = NULL))
  }

  cells <- NULL
  source_id <- NULL
  dims <- NULL
  if (kind == "matrix") {
    source_id <- as.character(primitive$matrix_id)[1]
    cells <- wb_cells_with_matrix(bundle, source_id)
    .wb_assert(length(cells) > 0L, paste0("Resolved matrix input '", name, "' has no registered cell coverage."))
  } else if (kind %in% c("space", "space_2d")) {
    source_id <- as.character(primitive$space_id)[1]
    dims <- .wb_coverage_dims(name, kind, primitive, inputs)
    cells <- wb_cells_with_space(bundle, source_id, dims = dims)
  } else if (kind == "cell_vector") {
    .wb_assert(length(primitive$cell_id) == length(primitive$value), paste0("Resolved cell_vector input '", name, "' has inconsistent row lengths."))
    cells <- .wb_coverage_validate_ids(primitive$cell_id, canonical, paste0("Resolved cell_vector input '", name, "'"))
  } else if (kind %in% c("cell_vector_family", "relation_family")) {
    .wb_assert(length(primitive$key) == length(primitive$cell_id), paste0("Resolved ", kind, " input '", name, "' has inconsistent row lengths."))
    cells <- .wb_coverage_validate_ids(primitive$cell_id, canonical, paste0("Resolved ", kind, " input '", name, "'"), allow_duplicates = TRUE)
    pairs <- paste(as.character(primitive$key), as.character(primitive$cell_id), sep = "\r")
    .wb_assert(!anyDuplicated(pairs), paste0("Resolved ", kind, " input '", name, "' contains duplicate key/cell rows."))
  } else if (kind %in% c("obs_table", "feature_table")) {
    tbl <- primitive$table %||% data.frame()
    if (is.data.frame(tbl) && "cell_id" %in% names(tbl)) {
      cells <- .wb_coverage_validate_ids(tbl$cell_id, canonical, paste0("Resolved ", kind, " input '", name, "'"), allow_duplicates = TRUE)
    }
  } else if (kind == "model_ref") {
    source_id <- as.character(primitive$artifact_id %||% primitive$model_space_id %||% "")[1]
    cells <- .wb_coverage_model_cells(bundle, primitive)
    .wb_assert(!is.null(cells) && length(cells) > 0L,
               paste0("Resolved model_ref input '", name, "' has no recoverable fitted-cell or associated-space coverage."))
    cells <- .wb_coverage_validate_ids(cells, canonical, paste0("Resolved model_ref input '", name, "'"))
  } else if (kind == "space_path_family") {
    ids <- unique(as.character(primitive$space_id %||% character(0)))
    ids <- ids[!is.na(ids) & nzchar(ids)]
    .wb_assert(length(ids) == 1L, paste0("Resolved space_path_family input '", name, "' must reference exactly one analytical space."))
    source_id <- ids[[1]]
    dims <- unique(as.integer(primitive$dim %||% integer(0)))
    cells <- wb_cells_with_space(bundle, source_id, dims = if (length(dims)) dims else NULL)
  }
  list(cells = cells, source_id = source_id, dims = dims)
}

.wb_typed_effective_cells <- function(bundle, cell_set, inputs, resolved, requirements,
                                      op_name, min_cells = 10L, coverage_modes = list()) {
  canonical <- wb_cells(bundle, cell_set = "all")
  explicit <- !is.null(inputs$cell_ids)
  requested <- if (explicit) {
    ids <- as.character(inputs$cell_ids)
    .wb_assert(length(ids) > 0L, "inputs$cell_ids provided but empty.")
    .wb_coverage_validate_ids(ids, canonical, "inputs$cell_ids")
  } else {
    wb_cells(bundle, cell_set = cell_set)
  }
  .wb_assert(length(requested) > 0L, paste0("Op '", op_name, "' requested an empty cell universe."))

  current <- requested
  per_input <- list()
  for (name in names(resolved)) {
    kind <- as.character(requirements[[name]])[1]
    mode <- as.character(coverage_modes[[name]] %||% "cell_indexed")[1]
    if (identical(mode, "model_associated_unless_query_space")) {
      mode <- if ("in_space" %in% names(resolved)) {
        "reference_only_explicit_query_space"
      } else {
        "cell_indexed"
      }
    }
    cov <- .wb_primitive_cell_coverage(bundle, name, kind, resolved[[name]], inputs, mode = mode)
    before <- length(current)
    if (!is.null(cov$cells)) current <- .wb_coverage_ordered_intersect(current, cov$cells)
    after <- length(current)
    per_input[[name]] <- list(
      kind = kind,
      required = name %in% names(.wb_op(op_name)$requires %||% list()),
      coverage_mode = if (is.null(cov$cells) && identical(mode, "cell_indexed")) "not_cell_indexed" else mode,
      source_id = cov$source_id,
      dims = if (is.null(cov$dims)) NULL else as.integer(cov$dims),
      available_n = if (is.null(cov$cells)) NA_integer_ else length(cov$cells),
      input_n = before,
      overlap_n = after,
      dropped_n = before - after
    )
  }

  diagnostics <- list(
    schema_version = "scworkbench.effective_cell_coverage.v1",
    requested_source = if (explicit) "cell_ids" else "cell_set",
    cell_set = as.character(cell_set)[1],
    requested_n = length(requested),
    per_input = per_input,
    effective_n = length(current),
    dropped_n = length(requested) - length(current),
    percent = round(100 * length(current) / length(requested), 1)
  )

  min_cells <- as.integer(min_cells)
  if (length(current) < min_cells) {
    detail <- if (length(per_input)) paste(vapply(names(per_input), function(nm) {
      x <- per_input[[nm]]
      paste0("    ", nm, " (", x$kind, "): ", x$overlap_n, "/", x$input_n,
             if (!is.na(x$available_n)) paste0("; available=", x$available_n) else "")
    }, character(1)), collapse = "\n") else "    (no cell-indexed typed inputs)"
    stop(paste0("Op '", op_name, "' cannot run:\n  requested cells: ", length(requested),
                "\n  effective cells: ", length(current), "\n  minimum cells: ", min_cells,
                "\n  typed input coverage:\n", detail), call. = FALSE)
  }
  list(cells = current, diagnostics = diagnostics)
}

#' Report coverage of operation inputs for a cell set
#'
#' The preferred typed form supplies `resolved`, `requirements`, and `op_name`.
#' The legacy `space_id`/`matrix_id` input form remains available for getter
#' diagnostics.
#'
#' @param bundle scworkbench bundle handle.
#' @param cell_set Cell set selector.
#' @param inputs Named input list, optionally including explicit `cell_ids`.
#' @param resolved Optional named list of resolved typed primitives.
#' @param requirements Optional named primitive-kind declarations.
#' @param op_name Optional registered operation name for typed diagnostics.
#'
#' @return List with `requested`, `per_input`, `effective`, and `percent`.
#' @export
wb_cell_coverage <- function(bundle, cell_set, inputs = list(), resolved = NULL,
                             requirements = NULL, op_name = NULL) {
  if (!is.null(resolved)) {
    .wb_assert(!is.null(op_name) && op_name %in% wb_list_ops(), "op_name must name a registered operation for typed coverage")
    out <- .wb_typed_effective_cells(bundle, cell_set, inputs, resolved, requirements,
                                     op_name, min_cells = 0L,
                                     coverage_modes = .wb_op(op_name)$coverage %||% list())
    d <- out$diagnostics
    return(list(requested = d$requested_n, per_input = d$per_input,
                effective = d$effective_n, percent = d$percent,
                diagnostics = d, cells = out$cells))
  }

  requested <- if (!is.null(inputs$cell_ids)) unique(as.character(inputs$cell_ids)) else wb_cells(bundle, cell_set = cell_set)
  requested <- requested[!is.na(requested) & nzchar(requested)]
  current <- requested
  per_input <- list()
  if (!is.null(inputs$space_id)) {
    have <- wb_cells_with_space(bundle, inputs$space_id, inputs$dims %||% NULL)
    current <- .wb_coverage_ordered_intersect(current, have)
    per_input$space <- list(have = length(have), intersect = length(current))
  }
  if (!is.null(inputs$matrix_id)) {
    have <- wb_cells_with_matrix(bundle, inputs$matrix_id)
    current <- .wb_coverage_ordered_intersect(current, have)
    per_input$matrix <- list(have = length(have), intersect = length(current))
  }
  list(requested = length(requested), per_input = per_input, effective = length(current),
       percent = if (length(requested)) round(100 * length(current) / length(requested), 1) else 0)
}

.wb_effective_cells <- function(bundle, cell_set, inputs, op_name, min_cells = 10L) {
  resolved <- list()
  requirements <- list()
  if (!is.null(inputs$space_id)) {
    resolved$space <- wb_prim_space(inputs$space_id)
    requirements$space <- "space"
  }
  if (!is.null(inputs$matrix_id)) {
    resolved$matrix <- wb_prim_matrix(inputs$matrix_id)
    requirements$matrix <- "matrix"
  }
  if (op_name %in% wb_list_ops()) {
    op <- .wb_op(op_name)
    return(.wb_typed_effective_cells(bundle, cell_set, inputs, resolved, requirements,
                                     op_name, min_cells, op$coverage %||% list())$cells)
  }
  requested <- if (!is.null(inputs$cell_ids)) {
    ids <- as.character(inputs$cell_ids)
    .wb_assert(length(ids) > 0L, "inputs$cell_ids provided but empty.")
    .wb_coverage_validate_ids(ids, wb_cells(bundle, "all"), "inputs$cell_ids")
  } else wb_cells(bundle, cell_set)
  current <- requested
  for (nm in names(resolved)) {
    cov <- .wb_primitive_cell_coverage(bundle, nm, requirements[[nm]], resolved[[nm]], inputs)
    if (!is.null(cov$cells)) current <- .wb_coverage_ordered_intersect(current, cov$cells)
  }
  .wb_assert(length(current) >= min_cells,
             paste0("Op '", op_name, "' cannot run: effective cells ", length(current), " < min_cells ", min_cells, "."))
  current
}

.wb_resolve_effective_cells_for_op <- function(bundle, op_name, cell_set,
                                               inputs = list(), min_cells = 10L) {
  .wb_effective_cells(bundle, cell_set %||% "core", inputs, op_name, min_cells)
}
