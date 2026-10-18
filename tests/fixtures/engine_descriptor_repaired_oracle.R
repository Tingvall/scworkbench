# Frozen unmodified descriptor algorithm from repaired core 8f53e950.
# Only its function name differs. Test-only oracle; never execution authority.
.engine_descriptor_repaired_oracle <- function(name, value, declaration,
                                                     transport_value = NULL,
                                                     g1_model_read = FALSE) {
  kind <- as.character(declaration$kind)[1]
  identity_value <- transport_value %||% unclass(value)
  # Only an explicitly declared G1 read replaces this provisional identity
  # with a verified linkage/tree grant and removes the ordinary model reader
  # before execution.  A tree manifest alone does not confer that authority:
  # without G1, model_obj remains identity-bearing if the ordinary reader can
  # deliver it (and a non-JSON value fails closed before dispatch).
  if (identical(kind, "model_ref") && isTRUE(g1_model_read))
    identity_value$model_obj <- NULL
  cells <- if (is.null(transport_value)) .wb_operation_pack_v2_primitive_cells(value) else
    unname(unlist(identity_value$cell_id %||% list(), use.names = FALSE))
  features <- if (is.null(transport_value)) .wb_operation_pack_v2_primitive_features(value) else
    unname(unlist(identity_value$feature_id %||% list(), use.names = FALSE))
  descriptor <- list(
    kind = kind, storage_profile = .wb_operation_pack_v2_input_profile(kind, value),
    reader = .wb_operation_pack_v2_reader_name(kind),
    dimensions = unname(as.list(.wb_operation_pack_v2_dimensions(value, kind))),
    alignment = as.character(declaration$alignment)[1],
    content_identity = .wb_operation_pack_v2_identity_plain(paste0("scworkbench.", kind, ".content.v1"), identity_value),
    ancestry_identity = .wb_operation_pack_v2_identity_plain("scworkbench.provenance.ancestry.v1", list(input = name, value = identity_value)),
    payload_manifest_identity = .wb_operation_pack_v2_identity_plain("scworkbench.payload.manifest.v2", list(input = name, value = identity_value))
  )
  if (kind %in% c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family", "relation_family")) {
    descriptor$cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", if (is.null(transport_value)) cells else
        identity_value$cell_id)
  }
  if (kind %in% c("matrix", "feature_table")) {
    descriptor$feature_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", if (is.null(transport_value)) features else
        identity_value$feature_id)
  }
  if (kind %in% c("cell_vector", "cell_vector_family", "relation_family", "feature_table", "obs_table", "path_2d_family", "space_path_family")) {
    descriptor$semantic_metadata_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.semantic_metadata.v2", identity_value$meta %||%
        structure(list(), names = character()))
  }
  if (kind %in% c("path_2d_family", "space_path_family")) {
    order_value <- if (kind == "path_2d_family") list(identity_value$key,
      identity_value$point) else list(identity_value$space_id,
      identity_value$path_id, identity_value$point, identity_value$dim)
    descriptor$row_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.row_order.v1", order_value)
  }
  if (kind == "space_path_family") descriptor$linked_space_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.space.content.v1", if (is.null(transport_value)) {
      sort(unique(as.character(value$space_id)), method = "radix")
    } else unname(as.list(sort(unique(as.character(unlist(identity_value$space_id,
      use.names = FALSE))), method = "radix"))))
  if (kind == "model_ref") {
    descriptor$model_linkage_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.model_linkage.v1", identity_value)
    descriptor$contained_payload_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.contained_payload.v2", identity_value)
  }
  descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.input_descriptor.v2", "descriptor excluding descriptor_identity", descriptor)
  list(name = name, reference = paste0(kind, ":", name), descriptor = descriptor)
}
