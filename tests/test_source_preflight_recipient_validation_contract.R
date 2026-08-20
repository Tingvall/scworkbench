.source_contract_identity <- function(paths, accession="GSE270605") {
  list(dataset_name="GSE270605-style fixture", inputs=lapply(seq_along(paths), function(i) {
    wb_source_input(
      path=paths[[i]], uri=paste0("https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM8348nnn/", accession, "/suppl/library_", i, ".tsv.gz"),
      source_id=paste0("library_", i), accession=accession, role=if (i %% 3L == 1L) "matrix" else if (i %% 3L == 2L) "barcodes" else "features",
      format="10x_mtx", scope="public_file", bundled=FALSE, accession_derived=TRUE
    )
  }))
}

test_source_preflight_zero_write_contract <- function() {
  source_root <- tempfile("scwb_source_files_"); dir.create(source_root)
  on.exit(unlink(source_root, recursive=TRUE, force=TRUE), add=TRUE)
  paths <- file.path(source_root, paste0("library_", seq_len(29L), ".tsv.gz"))
  for (i in seq_along(paths)) writeBin(as.raw((seq_len(257L) + i) %% 255L), paths[[i]])
  identity <- .source_contract_identity(paths)
  checked <- wb_source_preflight(identity)
  stopifnot(isTRUE(checked$valid), length(checked$inputs)==29L,
            all(vapply(checked$inputs, function(x) identical(x$sha256, wb_source_sha256(x$path)), logical(1))))

  base <- checked$source_identity$inputs[[1L]]
  cases <- list(
    malformed_sha=utils::modifyList(base, list(sha256="bad", checksum="bad")),
    conflicting_aliases=utils::modifyList(base, list(checksum=paste(rep("0",64L),collapse=""))),
    missing_accession=utils::modifyList(base, list(accession="")),
    missing_role=utils::modifyList(base, list(role="")),
    missing_format=utils::modifyList(base, list(format="")),
    missing_file=utils::modifyList(base, list(path=file.path(source_root,"missing"))),
    checksum_mismatch=utils::modifyList(base, list(sha256=paste(rep("f",64L),collapse=""),checksum=paste(rep("f",64L),collapse=""))),
    malformed_uri=utils::modifyList(base, list(uri="https://ftp.ncbi.nlm.nih.gov/geo/samples/GSM8348nnn//suppl/file", accession_derived=TRUE))
  )
  expected <- c("SOURCE_CHECKSUM_MALFORMED","SOURCE_CHECKSUM_ALIASES_CONFLICT","SOURCE_ACCESSION_MISSING","SOURCE_ROLE_MISSING","SOURCE_FORMAT_MISSING","SOURCE_FILE_MISSING","SOURCE_CHECKSUM_MISMATCH","SOURCE_URI_MALFORMED")
  for (i in seq_along(cases)) {
    got <- wb_source_preflight(list(inputs=list(cases[[i]])), strict=FALSE)
    stopifnot(!isTRUE(got$valid), expected[[i]] %in% got$diagnostics$code)
  }
  duplicate <- wb_source_preflight(list(inputs=list(base,base)),strict=FALSE)
  stopifnot("SOURCE_ID_DUPLICATE" %in% duplicate$diagnostics$code)

  target <- file.path(tempfile("scwb_zero_write_parent_"),"bundle.scwb")
  malformed <- list(inputs=list(cases$malformed_uri))
  err <- try(wb_bundle_from_10x_mtx("unused", target, source_identity=malformed),silent=TRUE)
  stopifnot(inherits(err,"try-error"), !dir.exists(target), !dir.exists(dirname(target)))
  TRUE
}

test_source_scope_ingest_dag_recipient_contract <- function() {
  if (!requireNamespace("BPCells", quietly=TRUE)) return(contract_test_skip("BPCells is not installed."))
  source_root <- tempfile("scwb_sources_"); dir.create(source_root)
  paths <- file.path(source_root,paste0("source_",seq_len(29L),".dat"))
  for(i in seq_along(paths)) writeBin(as.raw((seq_len(137L)+i)%%255L),paths[[i]])
  identity <- .source_contract_identity(paths)
  root <- tempfile("scwb_source_lifecycle_"); b <- wb_init_bundle(root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(c(root,source_root),recursive=TRUE,force=TRUE)},add=TRUE)
  ids <- paste0("c",1:8); wb_define_cells(b,ids)
  # The automatic assembly run remains visible but creates no source input.
  stopifnot(any(wb_prov_bundle_dag(b)$nodes$label=="assembly_define_cells"), nrow(wb_prov_source_inputs(b))==0L)
  m <- matrix(seq_len(24L),3L,dimnames=list(paste0("g",1:3),ids))
  wb_attach_matrix(b,"RNA_counts",m,feature_type="gene",source="geo")
  .wb_ingest_report_artifact(b,"core","atomic",list(valid=TRUE),list(),list(n_cells=length(ids)),
                             source="geo",matrix_ids="RNA_counts",source_identity=identity)
  memory_identity <- list(source_type="fixture",inputs=list(wb_source_input(uri="scworkbench-ingestion://test/object",source_id="memory_object",role="source_object",format="R_object",scope="in_memory")))
  .wb_record_declared_ingestion(b,"in_memory_fixture",source="fixture",source_identity=memory_identity)
  inputs <- wb_prov_source_inputs(b)
  stopifnot(sum(inputs$scope=="public_file")==58L,length(unique(inputs$source_id[inputs$scope=="public_file"]))==29L,sum(inputs$scope=="in_memory")==1L,
            all(inputs$checksum_status[inputs$scope=="public_file"]=="checksummed"),
            identical(inputs$checksum_status[inputs$scope=="in_memory"],"nonportable_in_memory"))
  dag <- wb_prov_bundle_dag(b); kg <- wb_kg_provenance_graph(b)
  stopifnot(sum(grepl("^external_source:",dag$nodes$id))==29L,
            any(grepl("^in_memory_source:",dag$nodes$id)),
            any(kg$nodes$node_type=="ExternalSource"),any(kg$nodes$node_type=="InMemorySource"))
  wb_finalize_recipient_bundle(b); wb_close_bundle(b); b <- NULL
  unlink(source_root,recursive=TRUE,force=TRUE)
  before <- scworkbench:::.wb_prov_path_identity(root)$content_sha256
  report <- wb_bundle_validation_report(root,"recipient")
  after <- scworkbench:::.wb_prov_path_identity(root)$content_sha256
  stopifnot(isTRUE(report$ok),identical(before,after),identical(report$pre_validation_fingerprint,report$post_validation_fingerprint),
            !"EXTERNAL_SOURCE_UNVERIFIABLE" %in% report$diagnostics$code[report$diagnostics$entity_kind=="in_memory_source"])
  ro <- wb_open_bundle(root,read_only=TRUE,validate=TRUE)
  ro_inputs <- wb_prov_source_inputs(ro); ro_dag <- wb_prov_bundle_dag(ro); ro_kg <- wb_kg_provenance_graph(ro)
  stopifnot(sum(ro_inputs$scope=="public_file")==58L,length(unique(ro_inputs$source_id[ro_inputs$scope=="public_file"]))==29L,any(ro_inputs$scope=="in_memory"),
            sum(grepl("^external_source:",ro_dag$nodes$id))==29L,any(ro_kg$nodes$node_type=="InMemorySource"))
  wb_close_bundle(ro)
  TRUE
}

test_large_multifragment_recipient_bounded_contract <- function() {
  if (!requireNamespace("BPCells",quietly=TRUE)) return(contract_test_skip("BPCells is not installed."))
  root <- tempfile("scwb_large_multifragment_"); b <- wb_init_bundle(root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  ids <- paste0("c",seq_len(12000L)); wb_define_cells(b,ids,dataset_id=rep(paste0("d",1:12),each=1000L))
  features <- paste0("g",1:5)
  DBI::dbWriteTable(b$con,"matrices",data.frame(matrix_id="RNA_counts",layer="counts",feature_type="gene",n_features=5L,n_cells=12000L,storage="bpcells",path="mat/fragment_01",description="bounded multifragment fixture",stringsAsFactors=FALSE),append=TRUE)
  DBI::dbWriteTable(b$con,"features",data.frame(matrix_id="RNA_counts",feature_id=features,feature_type="gene",chr=NA_character_,start=NA_integer_,end=NA_integer_,stringsAsFactors=FALSE),append=TRUE)
  for(i in 1:12) {
    cells <- ids[((i-1L)*1000L+1L):(i*1000L)]
    m <- Matrix::Matrix(matrix(as.integer((seq_len(5000L)+i)%%17L),5L,dimnames=list(features,cells)),sparse=TRUE)
    rel <- sprintf("mat/fragment_%02d",i); BPCells::write_matrix_dir(m,file.path(root,rel))
    wb_register_matrix_fragment(b$con,"RNA_counts",rel,features,cells,source="bounded_fixture")
  }
  .wb_record_declared_ingestion(b,"bounded_multifragment_fixture",matrix_ids="RNA_counts",source="fixture")
  wb_refresh_manifest(b)
  wb_finalize_recipient_bundle(b);wb_close_bundle(b);b<-NULL
  before <- scworkbench:::.wb_prov_path_identity(root)$content_sha256
  report <- wb_bundle_validation_report(root,"recipient")
  stopifnot(isTRUE(report$ok),is.finite(report$peak_memory_mb),report$peak_memory_mb < 2048,
            nrow(report$elapsed_by_check_class)>5L,identical(before,scworkbench:::.wb_prov_path_identity(root)$content_sha256),
            identical(report$pre_validation_fingerprint,report$post_validation_fingerprint))
  TRUE
}
