#' (Advanced) Resolve a "spec" into a wb_primitive
#'
#' Accepts:
#' - wb_primitive
#' - artifact_id string (e.g. "cell_vector_...")
#' - spec list:
#'     list(type="primitive", value=<wb_primitive>)
#'     list(type="artifact",  value="<artifact_id>")
#'     list(type="session",   value=list(run_id="<rid>", output="<out_name>"))
#'
#' @param bundle scworkbench_bundle
#' @param spec object described above
#' @param runs optional list of wb_run objects named by run_id (required for type="session")
#' @param expected_kind optional kind safety (e.g. "cell_vector")
#'
#' @return A resolved `wb_primitive`, or `NULL` only for `type = "none"`.
#' @export
wb_resolve_primitive <- function(bundle, spec, runs = NULL, expected_kind = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  # Pass-through: already primitive or artifact_id
  if (.wb_is_primitive(spec) || (is.character(spec) && length(spec) == 1 && nzchar(spec))) {
    return(wb_as_primitive(bundle, spec, expected_kind = expected_kind))
  }

  # Spec object
  .wb_assert(is.list(spec) && !is.null(spec$type), "wb_resolve_primitive(): spec must be a list with $type")

  tp <- as.character(spec$type[[1]])
  if (identical(tp, "none")) return(NULL)

  if (identical(tp, "primitive")) {
    .wb_assert(!is.null(spec$value), "wb_resolve_primitive(): spec$value missing for type='primitive'")
    return(wb_as_primitive(bundle, spec$value, expected_kind = expected_kind))
  }

  if (identical(tp, "artifact")) {
    .wb_assert(is.character(spec$value) && length(spec$value) == 1 && nzchar(spec$value),
               "wb_resolve_primitive(): spec$value must be artifact_id string for type='artifact'")
    return(wb_as_primitive(bundle, spec$value, expected_kind = expected_kind))
  }

  if (identical(tp, "session")) {
    .wb_assert(!is.null(runs) && is.list(runs) && length(runs) > 0,
               "wb_resolve_primitive(): runs must be provided for type='session'")
    ref <- spec$value
    .wb_assert(is.list(ref) && nzchar(ref$run_id %||% "") && nzchar(ref$output %||% ""),
               "wb_resolve_primitive(): session ref must be list(run_id=, output=)")

    rid <- as.character(ref$run_id)
    out <- as.character(ref$output)

    .wb_assert(!is.null(names(runs)) && rid %in% names(runs),
               paste0("wb_resolve_primitive(): run_id not found in runs: ", rid))
    run <- runs[[rid]]
    .wb_assert(wb_is_run(run), "wb_resolve_primitive(): runs[[run_id]] must be wb_run")
    .wb_assert(!is.null(run$outputs) && out %in% names(run$outputs),
               paste0("wb_resolve_primitive(): output not found on run: ", out))

    prim <- run$outputs[[out]]
    .wb_assert(.wb_is_primitive(prim), "wb_resolve_primitive(): session output is not a wb_primitive")

    if (!is.null(expected_kind)) {
      .wb_assert_kind(prim, expected_kind, where = " (wb_resolve_primitive/session)")
    }
    return(prim)
  }

  stop("wb_resolve_primitive(): unknown spec$type: ", tp, call. = FALSE)
}

#' Resolve a vector reference to a named vector (names = cell_id)
#'
#' Supports:
#' - cell_vector primitive / artifact / session output
#' - cell_vector_family primitive / artifact / session output (requires key=)
#'
#' @param bundle scworkbench_bundle
#' @param x primitive | artifact_id | spec list (type=primitive/artifact/session)
#' @param runs optional runs list (needed for session specs)
#' @param cell_ids optional subset/order; if NULL uses all cells in bundle
#' @param key lineage key for cell_vector_family (e.g. "L1")
#' @param expected_kind optional: "cell_vector" or "cell_vector_family" or NULL
#'
#' @return A named vector aligned to `cell_ids`; cells absent from the source
#'   primitive have `NA` values.
#' @export
wb_resolve_cell_vector <- function(bundle, x, runs = NULL, cell_ids = NULL, key = NULL, expected_kind = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  if (is.null(cell_ids)) cell_ids <- wb_cells(bundle, cell_set = "all")
  cell_ids <- as.character(cell_ids)

  prim <- wb_resolve_primitive(bundle, x, runs = runs, expected_kind = expected_kind)

  .wb_assert(.wb_is_primitive(prim), "wb_resolve_cell_vector(): resolved object is not a wb_primitive")

  if (identical(prim$kind, "cell_vector")) {
    is_cont <- identical(prim$value_type %||% "", "continuous") || is.numeric(prim$value)
    v <- if (is_cont) as.numeric(prim$value) else as.character(prim$value)
    names(v) <- as.character(prim$cell_id)

    # subset and preserve order, NA for missing
    out <- if (is_cont) rep(NA_real_, length(cell_ids)) else rep(NA_character_, length(cell_ids))
    names(out) <- cell_ids
    hit <- intersect(cell_ids, names(v))
    out[hit] <- v[hit]
    return(out)
  }

  if (identical(prim$kind, "cell_vector_family")) {
    .wb_assert(is.character(key) && length(key) == 1 && nzchar(key),
               "wb_resolve_cell_vector(): key= is required for cell_vector_family (e.g. 'L1')")

    keep <- as.character(prim$key) == as.character(key)
    out <- rep(NA_real_, length(cell_ids))
    names(out) <- cell_ids
    if (!any(keep)) return(out)

    vv <- as.numeric(prim$value[keep])
    names(vv) <- as.character(prim$cell_id[keep])

    hit <- intersect(cell_ids, names(vv))
    out[hit] <- vv[hit]
    return(out)
  }

  stop(
    "wb_resolve_cell_vector(): expected kind cell_vector or cell_vector_family; got kind=",
    prim$kind,
    call. = FALSE
  )
}


#' List available vector-like things for UIs
#'
#' Returns a data.frame of choices with a stable "ref" column that you can store in plans/specs.
#'
#' ref formats:
#' - artifact:<artifact_id>                       (for artifacts types cell_vector/cell_vector_family)
#' - session:<run_id>:<output_name>               (for session outputs that are vector primitives)
#'
#' @param bundle An open scworkbench bundle.
#' @param runs Optional named or unnamed `wb_run` collection.
#' @return A data frame of stable vector source references.
#' @export
wb_list_vector_sources <- function(bundle, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  out <- list()

  # A) artifact-backed
  if (exists("wb_art_list", mode = "function")) {
    a <- wb_art_list(bundle)
    if (nrow(a)) {
      a <- a[a$type %in% c("cell_vector", "cell_vector_family"), , drop = FALSE]
      if (nrow(a)) {
        out[[length(out) + 1]] <- data.frame(
          ref = paste0("artifact:", a$artifact_id),
          kind = a$type,
          name = a$name %||% a$artifact_id,
          created_at = a$created_at,
          source = "artifact",
          stringsAsFactors = FALSE
        )
      }
    }
  }

  # B) session-backed
  if (!is.null(runs) && is.list(runs) && length(runs)) {
    if (is.null(names(runs)) || any(names(runs) == "")) {
      ids <- vapply(runs, function(r) r$run_id, character(1))
      names(runs) <- ids
    }

    for (rid in names(runs)) {
      run <- runs[[rid]]
      if (!wb_is_run(run)) next
      outs <- run$outputs %||% list()
      if (!length(outs)) next

      for (nm in names(outs)) {
        prim <- outs[[nm]]
        if (!.wb_is_primitive(prim)) next
        if (!(prim$kind %in% c("cell_vector", "cell_vector_family"))) next

        out[[length(out) + 1]] <- data.frame(
          ref = paste0("session:", rid, ":", nm),
          kind = prim$kind,
          name = paste0(run$op_name, "::", nm),
          created_at = run$created_at %||% NA_character_,
          source = "session",
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (!length(out)) {
    return(data.frame(ref=character(0), kind=character(0), name=character(0),
                      created_at=character(0), source=character(0),
                      stringsAsFactors = FALSE))
  }

  do.call(rbind, out)
}


#' (Advanced) Parse a wb_list_vector_sources() Ref into a Spec List
#'
#' Use [wb_list_vector_sources()] to discover references. This helper is for
#' client implementations that need to resolve an existing reference string.
#'
#' @param ref A length-one artifact or session reference string.
#' @return A typed reference specification list.
#' @export
wb_vector_ref_to_spec <- function(ref) {
  ref <- as.character(ref)
  .wb_assert(length(ref) == 1 && nzchar(ref), "ref must be length-1 string")

  if (startsWith(ref, "artifact:")) {
    return(list(type="artifact", value=sub("^artifact:", "", ref)))
  }
  if (startsWith(ref, "session:")) {
    parts <- strsplit(sub("^session:", "", ref), ":", fixed = TRUE)[[1]]
    .wb_assert(length(parts) >= 2, "Bad session ref; expected session:<run_id>:<output>")
    rid <- parts[1]
    out <- paste(parts[-1], collapse=":") # in case output names ever contain ':'
    return(list(type="session", value=list(run_id=rid, output=out)))
  }

  stop("Unknown ref format: ", ref, call. = FALSE)
}
