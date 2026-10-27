.matrix_selection_fixture <- function(root, values = NULL) {
  b <- wb_init_bundle(root)
  if (is.null(values)) values <- matrix(c(0,2:12),3,
    dimnames=list(paste0("g",1:3),paste0("c",1:4)))
  wb_define_cells(b,colnames(values))
  wb_attach_matrix(b,"one",Matrix::Matrix(values,sparse=TRUE))
  wb_attach_matrix(b,"many",Matrix::Matrix(values,sparse=TRUE))
  template <- wb_matrix_fragments(b,"many")
  # Controlled layout fixture for public getters: replace the physical full
  # block with two disjoint fragments of the same logical matrix. This is not
  # a claim that repeated attach mutates an immutable logical matrix identity.
  for (table in c("matrix_fragment_cells","matrix_fragment_features"))
    DBI::dbExecute(b$con,paste0("DELETE FROM ",table," WHERE fragment_id=?"),
      params=list(template$fragment_id[[1]]))
  DBI::dbExecute(b$con,"DELETE FROM matrix_fragments WHERE matrix_id='many'")
  for (i in 1:2) {
    cols <- split(seq_len(ncol(values)),rep(1:2,length.out=ncol(values)))[[i]]
    v <- values[,cols,drop=FALSE]; row <- template
    row$fragment_id <- paste0("piece",i); row$path <- paste0("matrices/piece",i)
    row$n_cells <- ncol(v); row$cell_ids_json <- jsonlite::toJSON(colnames(v))
    BPCells::write_matrix_dir(methods::as(methods::as(Matrix::Matrix(v,sparse=TRUE),
      "generalMatrix"),"CsparseMatrix"),dir=file.path(root,row$path[[1]]))
    DBI::dbAppendTable(b$con,"matrix_fragments",row)
  }
  list(bundle=b,values=values)
}

test_matrix_repeated_axes_layout_contract <- function() {
  root <- tempfile("matrix_repeats_"); fixture <- .matrix_selection_fixture(root)
  b <- fixture$bundle; x <- fixture$values
  on.exit({wb_close_bundle(b);unlink(root,recursive=TRUE)},add=TRUE)
  fs <- list(rownames(x),rev(rownames(x)),c("g3","g1","g3"),character())
  cs <- list(colnames(x),rev(colnames(x)),c("c4","c1","c4"),character())
  for (id in c("one","many")) for (f in fs) for (c in cs) {
    expected <- x[f,c,drop=FALSE]
    # Matrix deliberately uses NULL dimnames on zero-length axes.
    if (!length(f)) rownames(expected) <- NULL
    if (!length(c)) colnames(expected) <- NULL
    actual <- wb_slice(b,id,f,c)
    dense <- wb_matrix_read_features(b,id,f,c,missing="NA")
    if (!length(f) && !length(c)) {
      # Sparse Matrix omits an all-NULL dimnames attribute on 0x0 matrices.
      dimnames(expected) <- NULL; dimnames(dense) <- NULL
    }
    stopifnot(inherits(actual,"sparseMatrix"), identical(as.matrix(actual),expected),
      identical(as.matrix(wb_matrix_read_features(b,id,f,c)),expected),
      identical(dense,expected))
  }
  for (id in c("one","many")) {
    stopifnot(inherits(try(wb_slice(b,id,"unknown","c1"),silent=TRUE),"try-error"),
      inherits(try(wb_slice(b,id,"g1","unknown"),silent=TRUE),"try-error"))
    z <- wb_matrix_read_features(b,id,c("unknown","g1","unknown"),c("c1","unknown","c1"))
    n <- wb_matrix_read_features(b,id,c("unknown","g1","unknown"),c("c1","unknown","c1"),missing="NA")
    stopifnot(all(z[c(1,3),]==0),all(z[,2]==0),z[2,1]==0,
      all(is.na(n[c(1,3),])),all(is.na(n[,2])),identical(n[2,c(1,3)],c(c1=0,c1=0)))
  }
  TRUE
}

test_matrix_missing_na_preallocation_guard_contract <- function() {
  root <- tempfile("matrix_guard_"); fixture <- .matrix_selection_fixture(root)
  b <- fixture$bundle;x<-fixture$values
  old <- options(scworkbench.max_dense_materialize_mb=.00001)
  on.exit({options(old);wb_close_bundle(b);unlink(root,recursive=TRUE)},add=TRUE)
  # Both allocations are forbidden during the refusal probe. A guard error
  # must occur before the output matrix() or dense block as.matrix() call.
  trace("matrix",where=baseenv(),print=FALSE,tracer=quote(stop("DENSE_ALLOCATION_ATTEMPTED")))
  trace("as.matrix",where=baseenv(),print=FALSE,tracer=quote(stop("DENSE_CONVERSION_ATTEMPTED")))
  tryCatch({
    error <- tryCatch(wb_matrix_read_features(b,"one",rownames(x),colnames(x),missing="NA"),error=identity)
    stopifnot(inherits(error,"error"),grepl("Refusing dense materialization",conditionMessage(error),fixed=TRUE))
  },finally={untrace("matrix",where=baseenv());untrace("as.matrix",where=baseenv())})
  for (id in c("one","many")) {
    stopifnot(inherits(wb_matrix_read_features(b,id,rownames(x),colnames(x)),"sparseMatrix"))
    options(scworkbench.max_dense_materialize_mb=1)
    f<-c("g3","g1","g3");c<-c("c4","c1","c4")
    stopifnot(identical(wb_matrix_read_features(b,id,f,c,missing="NA"),x[f,c]))
    options(scworkbench.max_dense_materialize_mb=.00001)
  }
  for (dims in list(c(.Machine$integer.max,.Machine$integer.max),c(1e308,1e308)))
    stopifnot(inherits(try(scworkbench:::.wb_matrix_read_dense_guard(dims[1],dims[2]),silent=TRUE),"try-error"))
  TRUE
}
