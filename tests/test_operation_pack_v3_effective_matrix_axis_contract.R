test_operation_pack_v3_effective_matrix_axis_contract <- function() {
  root <- tempfile("effective-matrix-axis-"); b <- wb_init_bundle(root)
  on.exit({wb_close_bundle(b);unlink(root,recursive=TRUE)},add=TRUE)
  cells <- c("c10", "c2", "c1", "c7")
  features <- c("g2", "g1", "g3")
  wb_define_cells(b,cells,metadata=data.frame(cell_id=cells,batch=c("B","A","B","A")))
  x <- Matrix::Matrix(matrix(seq_len(12L),3L,dimnames=list(features,cells)),sparse=TRUE)
  wb_attach_matrix(b,"counts",x,feature_type="gene")
  memory <- structure(list(kind="matrix",matrix_id="counts",values=as.matrix(x),
    cell_id=cells,feature_id=features,dimensions=c(3L,4L),meta=list()),class="wb_primitive")
  bind <- scworkbench:::.wb_operation_pack_v3_bind_typed_matrix
  selected <- cells[c(4,1,3)]
  backed <- bind(b,wb_prim_matrix("counts"),selected)
  ordinary <- bind(b,memory,selected)
  stopifnot(identical(backed$cell_id,selected),identical(ordinary$cell_id,selected),
    identical(backed$dimensions,c(3L,3L)),identical(ordinary$dimensions,c(3L,3L)),
    is.null(backed$values),is.matrix(ordinary$values),
    identical(colnames(ordinary$values),selected),identical(ordinary$values,as.matrix(x[,selected,drop=FALSE])),
    identical(backed$feature_id,features),identical(memory$cell_id,cells),
    identical(bind(b,memory,character())$dimensions,c(3L,0L)))
  # The ordinary selected carrier must also issue a private typed source with
  # exactly that projection, not merely report selected dimensions.
  stage <- file.path(root,"private-source");dir.create(stage)
  declaration <- list(name="chunks",input="matrix",chunk_axis="cells",
    supported_axes=list("cells"),chunk_size_parameter="chunk_size",
    call_discipline="ordered_partition_exactly_once",empty_selection_policy="reject",
    selection=list(cells=list(policy="effective_input_axis_v1"),features=list(policy="effective_input_axis_v1")))
  descriptor <- scworkbench:::.wb_operation_pack_v2_input_descriptor("matrix",ordinary,
    list(kind="matrix",alignment="cell_and_feature_ordered"))$descriptor
  source_state <- scworkbench:::.wb_operation_pack_v2_identity_plain("scworkbench.scientific_state.v1",
    scworkbench:::.wb_manifest_registry_snapshot(b$con))
  grant <- scworkbench:::.wb_operation_pack_v3_typed_slice_grant(b,declaration,ordinary,
    descriptor,list(chunk_size=2L),selected,source_state,stage)
  projected <- scworkbench:::.wb_operation_pack_v3_private_source_validate(stage,grant)
  stopifnot(identical(grant$source_reference$source_kind,"in_memory_selected_projection"),
    identical(as.integer(dim(projected)),c(3L,3L)),
    isTRUE(all.equal(unname(as.matrix(projected)),unname(as.matrix(x[,selected,drop=FALSE])))))
  metadata_declaration <- list(matrix_input="matrix",field_parameters=list(
    list(parameter="batch_key",role="categorical",cardinality="zero_or_one")))
  metadata <- function(axis) scworkbench:::.wb_operation_pack_v3_cell_metadata_snapshot(
    b,metadata_declaration,list(matrix=backed),list(matrix=descriptor),list(batch_key="batch"),axis)
  valid <- metadata(selected)
  stopifnot(identical(unlist(valid$cell_id,use.names=FALSE),selected),
    identical(unlist(valid$fields[[1]]$values,use.names=FALSE),c("A","B","B")))
  for(bad in list(rev(selected),c(selected[1L],selected[1L],selected[3L]),c(selected[1:2],"foreign"))) {
    error <- tryCatch(metadata(bad),error=identity)
    stopifnot(inherits(error,"error"),grepl("Ordered cell metadata requires the authenticated matrix cell axis",conditionMessage(error),fixed=TRUE))
  }
  for(input in list(wb_prim_matrix("counts"),memory)) {
    stopifnot(identical(bind(b,input,cells)$cell_id,cells))
    for(bad in list(c("c10","c10"),c("c10","foreign"),c("c10",NA_character_)))
      stopifnot(inherits(try(bind(b,input,bad),silent=TRUE),"try-error"))
  }
  TRUE
}
