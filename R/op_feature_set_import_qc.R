# Feature-set import and overlap-QC operations.

.wb_fset_token <- function(x) {
  x <- tolower(as.character(x %||% "")[1])
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) "custom" else x
}

.wb_fset_guess_collection <- function(set_id, collection = NULL, subcollection = NULL) {
  sid <- toupper(as.character(set_id %||% "")[1])
  coll <- as.character(collection %||% "")[1]
  sub <- as.character(subcollection %||% "")[1]
  if (!nzchar(coll) || !nzchar(sub)) {
    if (grepl("^HALLMARK_", sid)) {
      coll <- if (nzchar(coll)) coll else "hallmark"
      sub <- if (nzchar(sub)) sub else "hallmark"
    } else if (grepl("^REACTOME_", sid)) {
      coll <- if (nzchar(coll)) coll else "msigdb_c2"
      sub <- if (nzchar(sub)) sub else "reactome"
    } else if (grepl("^(WP_|WIKIPATHWAYS_)", sid)) {
      coll <- if (nzchar(coll)) coll else "wikipathways"
      sub <- if (nzchar(sub)) sub else "wikipathways"
    } else if (grepl("^(GOBP_|GO_BP_)", sid)) {
      coll <- if (nzchar(coll)) coll else "msigdb_c5"
      sub <- if (nzchar(sub)) sub else "go_bp"
    } else if (grepl("^(GOMF_|GO_MF_)", sid)) {
      coll <- if (nzchar(coll)) coll else "msigdb_c5"
      sub <- if (nzchar(sub)) sub else "go_mf"
    } else if (grepl("^(GOCC_|GO_CC_)", sid)) {
      coll <- if (nzchar(coll)) coll else "msigdb_c5"
      sub <- if (nzchar(sub)) sub else "go_cc"
    } else if (grepl("^KEGG_", sid)) {
      coll <- if (nzchar(coll)) coll else "msigdb_c2"
      sub <- if (nzchar(sub)) sub else "kegg"
    }
  }
  if (!nzchar(coll)) coll <- "custom"
  if (!nzchar(sub)) sub <- coll
  list(collection = coll, subcollection = sub)
}

.wb_fset_namespace <- function(base_namespace, collection, subcollection, split_by_collection) {
  base <- .wb_fset_token(base_namespace %||% "imported")
  if (!isTRUE(split_by_collection)) return(base)
  suffix <- .wb_fset_token(subcollection %||% collection %||% "")
  if (!nzchar(suffix) || identical(suffix, "custom")) return(base)
  paste(base, suffix, sep = "_")
}

.wb_fset_read_gmt <- function(path) {
  lines <- readLines(path, warn = FALSE)
  rows <- vector("list", length(lines))
  k <- 0L
  for (ln in lines) {
    if (!nzchar(trimws(ln))) next
    parts <- strsplit(ln, "\t", fixed = TRUE)[[1]]
    if (length(parts) < 3L) next
    set_id <- as.character(parts[[1]])
    desc <- as.character(parts[[2]])
    genes <- unique(trimws(as.character(parts[-c(1, 2)])))
    genes <- genes[nzchar(genes)]
    if (!nzchar(set_id)) next
    k <- k + 1L
    rows[[k]] <- data.frame(
      set_id = set_id,
      set_name = set_id,
      description = desc,
      gene = genes,
      stringsAsFactors = FALSE
    )
  }
  if (!k) {
    return(data.frame(
      set_id = character(0), set_name = character(0),
      description = character(0), gene = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows[seq_len(k)])
}

.wb_fset_list_to_table <- function(sets) {
  .wb_assert(is.list(sets), "sets must be a named list")
  nms <- names(sets) %||% character(0)
  .wb_assert(length(nms) == length(sets) && all(nzchar(as.character(nms))),
             "sets must be a named list")
  rows <- vector("list", length(sets))
  for (i in seq_along(sets)) {
    genes <- unique(trimws(as.character(sets[[i]] %||% character(0))))
    genes <- genes[nzchar(genes)]
    if (!length(genes)) genes <- ""
    rows[[i]] <- data.frame(
      set_id = as.character(nms[[i]]),
      set_name = as.character(nms[[i]]),
      description = NA_character_,
      gene = genes,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

.wb_fset_parse_source <- function(source_path = NULL,
                                  source_format = "auto",
                                  table = NULL,
                                  sets = NULL,
                                  set_id_col = "feature_set",
                                  set_name_col = NULL,
                                  gene_col = "feature_id",
                                  description_col = "description") {
  source_format <- tolower(as.character(source_format %||% "auto")[1])
  if (!source_format %in% c("auto", "gmt", "rds", "table", "list")) {
    stop("source_format must be one of auto, gmt, rds, table, list.", call. = FALSE)
  }

  if (!is.null(table)) {
    obj <- table
    source_format <- "table"
  } else if (!is.null(sets)) {
    obj <- sets
    source_format <- "list"
  } else {
    .wb_assert(is.character(source_path) && length(source_path) == 1 && nzchar(source_path),
               "source_path is required when table/sets are not supplied")
    .wb_assert(file.exists(source_path), paste0("source_path does not exist: ", source_path))
    if (identical(source_format, "auto")) {
      ext <- tolower(tools::file_ext(source_path))
      source_format <- if (identical(ext, "gmt")) "gmt" else if (identical(ext, "rds")) "rds" else "table"
    }
    if (identical(source_format, "gmt")) {
      obj <- .wb_fset_read_gmt(source_path)
      source_format <- "table"
      set_id_col <- "set_id"
      set_name_col <- "set_name"
      gene_col <- "gene"
      description_col <- "description"
    } else if (identical(source_format, "rds")) {
      obj <- readRDS(source_path)
      source_format <- if (is.data.frame(obj)) "table" else if (is.list(obj)) "list" else "unknown"
      .wb_assert(source_format %in% c("table", "list"),
                 "RDS source must contain a data.frame or named list")
    } else {
      obj <- utils::read.csv(source_path, stringsAsFactors = FALSE, check.names = FALSE)
      source_format <- "table"
    }
  }

  if (identical(source_format, "list")) {
    return(.wb_fset_list_to_table(obj))
  }

  .wb_assert(is.data.frame(obj), "feature-set source must resolve to a data.frame")
  tab <- obj
  if (!(set_id_col %in% names(tab)) && !(gene_col %in% names(tab))) {
    rows <- vector("list", length(tab))
    for (i in seq_along(tab)) {
      genes <- unique(trimws(as.character(tab[[i]])))
      genes <- genes[!is.na(genes) & nzchar(genes)]
      if (!length(genes)) genes <- ""
      rows[[i]] <- data.frame(
        set_id = names(tab)[[i]],
        set_name = names(tab)[[i]],
        description = NA_character_,
        gene = genes,
        stringsAsFactors = FALSE
      )
    }
    out <- do.call(rbind, rows)
    rownames(out) <- NULL
    return(out)
  }
  .wb_assert(set_id_col %in% names(tab), paste0("set_id_col missing: ", set_id_col))
  .wb_assert(gene_col %in% names(tab), paste0("gene_col missing: ", gene_col))
  out <- data.frame(
    set_id = as.character(tab[[set_id_col]]),
    set_name = if (!is.null(set_name_col) && set_name_col %in% names(tab)) as.character(tab[[set_name_col]]) else as.character(tab[[set_id_col]]),
    description = if (!is.null(description_col) && description_col %in% names(tab)) as.character(tab[[description_col]]) else NA_character_,
    gene = as.character(tab[[gene_col]]),
    stringsAsFactors = FALSE
  )
  if ("collection" %in% names(tab)) out$collection <- as.character(tab$collection)
  if ("subcollection" %in% names(tab)) out$subcollection <- as.character(tab$subcollection)
  out <- out[nzchar(out$set_id) & nzchar(out$gene), , drop = FALSE]
  rownames(out) <- NULL
  out
}

.wb_fset_recipe_raw_n <- function(recipe_json) {
  recipe_json <- as.character(recipe_json %||% "")[1]
  if (!nzchar(recipe_json) || identical(recipe_json, "NA")) return(NA_integer_)
  x <- try(jsonlite::fromJSON(recipe_json, simplifyVector = FALSE), silent = TRUE)
  if (inherits(x, "try-error") || !is.list(x)) return(NA_integer_)
  n <- suppressWarnings(as.integer(x$n_genes_raw %||% x$raw_gene_count %||% NA_integer_)[1])
  if (is.na(n)) NA_integer_ else n
}

.wb_fset_first_nonempty <- function(x, default = NA_character_) {
  x <- as.character(x %||% character(0))
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) return(as.character(default)[1])
  as.character(x[[1]])
}

#' Import Feature-Set Library Into A Bundle Namespace
#'
#' Parses GMT, RDS list/data.frame, or a direct data.frame/list source and
#' registers feature sets through the canonical bundle feature-set registry.
#' Outputs are obs_table primitives that can be promoted to make the registry
#' mutation auditable.
#'
#' @export
wb_op_feature_set_import <- function(bundle,
                                     matrix_id,
                                     source_path = NULL,
                                     source_format = "auto",
                                     table = NULL,
                                     sets = NULL,
                                     namespace,
                                     collection = NULL,
                                     subcollection = NULL,
                                     species = NULL,
                                     organism = NULL,
                                     gene_id_type = NULL,
                                     set_id_col = "feature_set",
                                     set_name_col = NULL,
                                     gene_col = "feature_id",
                                     description_col = "description",
                                     split_by_collection = FALSE,
                                     overwrite = TRUE,
                                     strict = FALSE,
                                     created_by = NULL,
                                     source_id = NULL,
                                     source_version = NULL,
                                     origin = "imported",
                                     is_readonly = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(namespace) && length(namespace) == 1 && nzchar(namespace), "namespace invalid")
  organism <- organism %||% species
  valid <- wb_feature_ids(bundle, matrix_id = matrix_id)

  tab <- .wb_fset_parse_source(
    source_path = source_path,
    source_format = source_format,
    table = table,
    sets = sets,
    set_id_col = set_id_col,
    set_name_col = set_name_col,
    gene_col = gene_col,
    description_col = description_col
  )
  .wb_assert(nrow(tab) > 0L, "No feature-set rows parsed from source.")

  set_ids <- unique(as.character(tab$set_id))
  manifest <- vector("list", length(set_ids))
  rejected <- list()
  ri <- 0L
  imported_n <- 0L
  skipped_n <- 0L
  rejected_n <- 0L
  source_label <- as.character(source_id %||% source_path %||% "direct")[1]

  for (i in seq_along(set_ids)) {
    sid <- set_ids[[i]]
    sub <- tab[as.character(tab$set_id) == sid, , drop = FALSE]
    genes_raw <- unique(trimws(as.character(sub$gene)))
    genes_raw <- genes_raw[nzchar(genes_raw)]
    genes_mapped <- intersect(genes_raw, valid)
    meta_guess <- .wb_fset_guess_collection(
      sid,
      collection = if ("collection" %in% names(sub)) sub$collection[1] else collection,
      subcollection = if ("subcollection" %in% names(sub)) sub$subcollection[1] else subcollection
    )
    ns <- .wb_fset_namespace(namespace, meta_guess$collection, meta_guess$subcollection, split_by_collection)
    desc <- .wb_fset_first_nonempty(sub$description, "")
    set_name <- .wb_fset_first_nonempty(sub$set_name, sid)
    exists_already <- nrow(wb_feature_set_info(bundle, feature_set = sid, matrix_id = matrix_id)) > 0L

    status <- "imported"
    reason <- "ok"
    if (exists_already && !isTRUE(overwrite)) {
      status <- "skipped"
      reason <- "exists_overwrite_false"
      skipped_n <- skipped_n + 1L
    } else if (!length(genes_mapped)) {
      status <- "rejected"
      reason <- "no_genes_mapped_to_matrix"
      rejected_n <- rejected_n + 1L
    } else {
      recipe <- list(
        op = "feature_set_import",
        source_path = as.character(source_path %||% NA_character_)[1],
        source_format = as.character(source_format %||% "auto")[1],
        source_id = source_label,
        source_version = as.character(source_version %||% NA_character_)[1],
        namespace_requested = as.character(namespace)[1],
        namespace_registered = ns,
        collection = meta_guess$collection,
        subcollection = meta_guess$subcollection,
        species = as.character(organism %||% NA_character_)[1],
        gene_id_type = as.character(gene_id_type %||% NA_character_)[1],
        n_genes_raw = length(genes_raw),
        n_genes_mapped_to_bundle = length(genes_mapped),
        split_by_collection = isTRUE(split_by_collection)
      )
      wb_feature_set_replace(
        bundle = bundle,
        feature_set = sid,
        matrix_id = matrix_id,
        feature_ids = genes_raw,
        created_by = created_by,
        description = desc,
        strict = strict,
        namespace = ns,
        organism = organism,
        source_id = source_label,
        source_version = source_version,
        origin = origin,
        recipe = recipe,
        is_readonly = is_readonly
      )
      imported_n <- imported_n + 1L
    }

    if (identical(status, "rejected")) {
      ri <- ri + 1L
      rejected[[ri]] <- data.frame(
        namespace = ns,
        feature_set = sid,
        set_name = set_name,
        reason = reason,
        n_genes_raw = length(genes_raw),
        n_genes_mapped_to_bundle = length(genes_mapped),
        stringsAsFactors = FALSE
      )
    }

    manifest[[i]] <- data.frame(
      namespace = ns,
      feature_set = sid,
      set_name = set_name,
      description = desc,
      collection = meta_guess$collection,
      subcollection = meta_guess$subcollection,
      matrix_id = matrix_id,
      n_genes_raw = length(genes_raw),
      n_genes_mapped_to_bundle = length(genes_mapped),
      n_genes_missing_from_bundle = length(setdiff(genes_raw, valid)),
      status = status,
      reason = reason,
      source_id = source_label,
      source_version = as.character(source_version %||% "")[1],
      organism = as.character(organism %||% "")[1],
      gene_id_type = as.character(gene_id_type %||% "")[1],
      stringsAsFactors = FALSE
    )
  }

  manifest_tbl <- do.call(rbind, manifest)
  rejected_tbl <- if (length(rejected)) do.call(rbind, rejected) else data.frame(
    namespace = character(0), feature_set = character(0), set_name = character(0),
    reason = character(0), n_genes_raw = integer(0), n_genes_mapped_to_bundle = integer(0),
    stringsAsFactors = FALSE
  )
  summary_tbl <- data.frame(
    namespace_requested = as.character(namespace)[1],
    namespaces_registered = paste(sort(unique(as.character(manifest_tbl$namespace))), collapse = ","),
    matrix_id = matrix_id,
    source_id = source_label,
    source_path = as.character(source_path %||% "")[1],
    source_format = as.character(source_format %||% "auto")[1],
    n_sets_parsed = length(set_ids),
    n_sets_imported = imported_n,
    n_sets_skipped = skipped_n,
    n_sets_rejected = rejected_n,
    n_genes_raw_total = sum(as.integer(manifest_tbl$n_genes_raw), na.rm = TRUE),
    n_genes_mapped_total = sum(as.integer(manifest_tbl$n_genes_mapped_to_bundle), na.rm = TRUE),
    split_by_collection = isTRUE(split_by_collection),
    overwrite = isTRUE(overwrite),
    stringsAsFactors = FALSE
  )

  meta <- list(
    matrix_id = matrix_id,
    namespace_requested = as.character(namespace)[1],
    source_id = source_label,
    source_path = as.character(source_path %||% "")[1],
    op = "feature_set_import"
  )

  list(
    outputs = list(
      import_summary = wb_prim_obs_table(summary_tbl, table_type = "feature_set_import_summary", entity_kind = "namespace", meta = meta),
      import_manifest = wb_prim_obs_table(manifest_tbl, table_type = "feature_set_import_manifest", entity_kind = "feature_set", meta = meta),
      rejected_sets = wb_prim_obs_table(rejected_tbl, table_type = "feature_set_import_rejected", entity_kind = "feature_set", meta = meta)
    ),
    params = list(
      matrix_id = matrix_id,
      namespace = namespace,
      source_path = as.character(source_path %||% "")[1],
      source_format = source_format,
      imported_sets = imported_n,
      rejected_sets = rejected_n,
      skipped_sets = skipped_n,
      split_by_collection = isTRUE(split_by_collection)
    )
  )
}

#' Compute Feature-Set Matrix Overlap QC
#'
#' Summarizes how registered feature sets overlap a target matrix before
#' trajectory/pathway screening.
#'
#' @export
wb_op_feature_set_overlap_qc <- function(bundle,
                                         matrix_id,
                                         namespaces = NULL,
                                         namespace = NULL,
                                         feature_sets = NULL,
                                         min_set_size = 1L,
                                         max_set_size = Inf,
                                         min_detected_fraction = 0,
                                         deduplicate_sets = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  namespaces <- unique(as.character(c(namespaces %||% character(0), namespace %||% character(0))))
  namespaces <- namespaces[nzchar(namespaces)]
  min_set_size <- as.integer(min_set_size %||% 1L)[1]
  max_set_size <- suppressWarnings(as.numeric(max_set_size %||% Inf)[1])
  min_detected_fraction <- suppressWarnings(as.numeric(min_detected_fraction %||% 0)[1])
  .wb_assert(is.finite(min_set_size) && min_set_size >= 0L, "min_set_size invalid")
  .wb_assert(is.finite(max_set_size) || is.infinite(max_set_size), "max_set_size invalid")
  .wb_assert(is.finite(min_detected_fraction) && min_detected_fraction >= 0 && min_detected_fraction <= 1,
             "min_detected_fraction must be in [0, 1]")

  info <- wb_feature_sets(bundle, matrix_id = matrix_id)
  if (length(namespaces)) info <- info[as.character(info$namespace) %in% namespaces, , drop = FALSE]
  if (!is.null(feature_sets)) info <- info[as.character(info$feature_set) %in% as.character(feature_sets), , drop = FALSE]
  .wb_assert(nrow(info) > 0L, "No feature sets match requested matrix/namespace filters.")

  valid <- wb_feature_ids(bundle, matrix_id = matrix_id)
  rows <- vector("list", nrow(info))
  signatures <- character(nrow(info))
  for (i in seq_len(nrow(info))) {
    fs <- as.character(info$feature_set[i])
    members <- wb_feature_set_get(bundle, feature_set = fs, matrix_id = matrix_id)
    mapped <- intersect(members, valid)
    raw_n <- .wb_fset_recipe_raw_n(info$recipe_json[i])
    if (is.na(raw_n)) raw_n <- as.integer(info$n_features[i])
    detected_fraction <- if (raw_n > 0L) length(mapped) / raw_n else 0
    reasons <- character(0)
    if (length(mapped) < min_set_size) reasons <- c(reasons, "below_min_set_size")
    if (length(mapped) > max_set_size) reasons <- c(reasons, "above_max_set_size")
    if (detected_fraction < min_detected_fraction) reasons <- c(reasons, "below_min_detected_fraction")
    signatures[[i]] <- paste(sort(unique(mapped)), collapse = "\r")
    rows[[i]] <- data.frame(
      namespace = as.character(info$namespace[i]),
      feature_set = fs,
      set_name = fs,
      matrix_id = matrix_id,
      n_genes_raw = as.integer(raw_n),
      n_genes_mapped_to_bundle = as.integer(info$n_features[i]),
      n_genes_detected_in_matrix = length(mapped),
      detected_fraction = detected_fraction,
      screening_status = if (length(reasons)) "exclude" else "include",
      reason = if (length(reasons)) paste(reasons, collapse = ";") else "ok",
      source_id = as.character(info$source_id[i] %||% NA_character_),
      source_version = as.character(info$source_version[i] %||% NA_character_),
      stringsAsFactors = FALSE
    )
  }
  qc_tbl <- do.call(rbind, rows)

  if (isTRUE(deduplicate_sets) && length(signatures)) {
    dup <- duplicated(signatures)
    qc_tbl$duplicate_signature <- duplicated(signatures) | duplicated(signatures, fromLast = TRUE)
    qc_tbl$duplicate_group <- match(signatures, unique(signatures))
    if (any(dup)) {
      qc_tbl$screening_status[dup] <- "exclude"
      qc_tbl$reason[dup] <- ifelse(
        qc_tbl$reason[dup] == "ok",
        "duplicate_set_after_dedup",
        paste(qc_tbl$reason[dup], "duplicate_set_after_dedup", sep = ";")
      )
    }
  } else {
    qc_tbl$duplicate_signature <- FALSE
    qc_tbl$duplicate_group <- seq_len(nrow(qc_tbl))
  }

  ns <- sort(unique(as.character(qc_tbl$namespace)))
  summary_rows <- vector("list", length(ns))
  for (i in seq_along(ns)) {
    sub <- qc_tbl[as.character(qc_tbl$namespace) == ns[[i]], , drop = FALSE]
    summary_rows[[i]] <- data.frame(
      namespace = ns[[i]],
      matrix_id = matrix_id,
      n_sets = nrow(sub),
      n_include = sum(as.character(sub$screening_status) == "include"),
      n_exclude = sum(as.character(sub$screening_status) == "exclude"),
      median_detected_fraction = stats::median(as.numeric(sub$detected_fraction), na.rm = TRUE),
      median_detected_genes = stats::median(as.integer(sub$n_genes_detected_in_matrix), na.rm = TRUE),
      min_set_size = min_set_size,
      max_set_size = if (is.infinite(max_set_size)) NA_real_ else max_set_size,
      min_detected_fraction = min_detected_fraction,
      deduplicate_sets = isTRUE(deduplicate_sets),
      stringsAsFactors = FALSE
    )
  }
  summary_tbl <- do.call(rbind, summary_rows)
  meta <- list(
    matrix_id = matrix_id,
    namespaces = ns,
    op = "feature_set_overlap_qc",
    min_set_size = min_set_size,
    max_set_size = if (is.infinite(max_set_size)) "Inf" else max_set_size,
    min_detected_fraction = min_detected_fraction,
    deduplicate_sets = isTRUE(deduplicate_sets)
  )

  list(
    outputs = list(
      overlap_qc = wb_prim_obs_table(qc_tbl, table_type = "feature_set_overlap_qc", entity_kind = "feature_set", meta = meta),
      namespace_summary = wb_prim_obs_table(summary_tbl, table_type = "feature_set_overlap_qc_summary", entity_kind = "namespace", meta = meta)
    ),
    params = meta
  )
}
