# Compatibility metadata for operations extracted from the historical core
# catalog. This mapping is used only to produce a useful missing-pack error.

.wb_operation_pack_migrated_map <- function() {
  c(
    de_wilcox = "scwbstatistics::de_wilcox",
    markers_topn = "scwbstatistics::markers_topn",
    cell_vector_assoc = "scwbstatistics::cell_vector_assoc",
    cell_vector_association = "scwbstatistics::cell_vector_association",
    cell_vector_compare = "scwbstatistics::cell_vector_compare",
    feature_trend_spearman = "scwbstatistics::feature_trend_spearman"
  )
}

.wb_operation_name_resolve <- function(op_name) {
  op_name <- as.character(op_name)[1]
  catalog <- .wb_operation_catalog()
  if (op_name %in% names(catalog)) return(op_name)
  if (!grepl("::", op_name, fixed = TRUE)) {
    candidates <- names(catalog)[endsWith(names(catalog), paste0("::", op_name))]
    if (length(candidates) == 1L) return(candidates[[1]])
    if (length(candidates) > 1L) .wb_operation_pack_abort(
      "OPERATION_PACK_OPERATION_AMBIGUOUS",
      paste0("Unqualified operation '", op_name, "' matches multiple active packs: ",
        paste(sort(candidates, method = "radix"), collapse = ", "), ". Use a qualified name."),
      operation = op_name, candidates = sort(candidates, method = "radix"),
      class = "wb_operation_pack_ambiguous")
    target <- unname(.wb_operation_pack_migrated_map()[op_name])
    if (length(target) && !is.na(target)) .wb_operation_pack_abort(
      "OPERATION_PACK_REQUIRED",
      paste0("Operation '", op_name, "' moved to '", target,
        "'. Install and explicitly activate scwbStatistics."),
      operation = op_name, required_operation = target, namespace = "scwbstatistics",
      class = "wb_operation_pack_unavailable")
  }
  if (grepl("::", op_name, fixed = TRUE)) {
    namespace <- strsplit(op_name, "::", fixed = TRUE)[[1]][1]
    .wb_operation_pack_abort("OPERATION_PACK_REQUIRED",
      paste0("Operation '", op_name, "' requires its exact compatible operation pack."),
      operation = op_name, namespace = namespace,
      class = "wb_operation_pack_unavailable")
  }
  op_name
}

.wb_operation_pack_params_transport <- function(value) {
  if (is.factor(value)) value <- as.character(value)
  if (is.atomic(value) && !length(value)) return(list())
  if (is.atomic(value) && length(value) > 1L) return(unname(as.list(value)))
  if (is.list(value)) {
    out <- lapply(value, .wb_operation_pack_params_transport)
    if (!is.null(names(value))) names(out) <- names(value)
    return(out)
  }
  value
}
