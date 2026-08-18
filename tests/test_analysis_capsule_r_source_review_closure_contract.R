test_analysis_capsule_r_source_review_closure_contract <- function() {
  fixture<-file.path(Sys.getenv("SCWORKBENCH_SOURCE_ROOT",unset="."),"tests","fixtures","honeybee","build_evidence_and_figures.R")
  stopifnot(file.exists(fixture),wb_source_sha256(fixture)=="3ec990b7155ecb5f67ed2dd7fd9759f14cd2dc4288b0f6f05d1e09f245a12a52")
  bytes_before<-readBin(fixture,"raw",n=file.info(fixture)$size)
  reviewed<-scworkbench:::.wb_capsule_r_registered_ops(fixture,wb_list_ops())
  stopifnot(!length(reviewed),identical(bytes_before,readBin(fixture,"raw",n=file.info(fixture)$size)))

  work<-tempfile("capsule_r_review_");dir.create(work);on.exit(unlink(work,recursive=TRUE,force=TRUE),add=TRUE)
  ordinary<-file.path(work,"ordinary.R")
  writeLines(c(
    "f <- function(x, column, row) { x[, column]; x[row, ]; x[] }",
    "formula <- response ~ nested(a + b)",
    "message <- \"pca_fit and wb_op_pca_fit() are prose\"",
    "# wb_session_run_op(s, b, op_name='umap_fit') is a comment"
  ),ordinary)
  stopifnot(!length(scworkbench:::.wb_capsule_r_registered_ops(ordinary,wb_list_ops())))
  bypasses<-list(
    "wb_session_run_op(s,b,op_name='pca_fit')",
    "wb_session_run_op(s,b,'umap_fit')",
    "scworkbench::wb_session_run_op(s,b,op_name='scvi_train')",
    "scworkbench:::wb_op_pca_fit(b)"
  )
  expected<-c("pca_fit","umap_fit","scvi_train","pca_fit")
  for(i in seq_along(bypasses)) {
    path<-file.path(work,paste0("bypass",i,".R"));writeLines(bypasses[[i]],path)
    stopifnot(expected[[i]]%in%scworkbench:::.wb_capsule_r_registered_ops(path,wb_list_ops()))
  }
  bad<-file.path(work,"bad.R");writeLines("x <- function(",bad)
  parse_error<-try(scworkbench:::.wb_capsule_r_registered_ops(bad,wb_list_ops()),silent=TRUE)
  stopifnot(inherits(parse_error,"try-error"),inherits(attr(parse_error,"condition"),"scworkbench_capsule_source_review_error"),
            attr(parse_error,"condition")$code=="CAPSULE_R_SOURCE_PARSE_FAILED")

  for(alias in c("R","r","Rscript","R_source"))stopifnot(scworkbench:::.wb_capsule_language(alias,"evidence.R")=="R")
  contradictory<-try(scworkbench:::.wb_capsule_language("Python","evidence.R"),silent=TRUE)
  unsupported<-try(scworkbench:::.wb_capsule_language("R-ish","evidence.txt"),silent=TRUE)
  stopifnot(attr(contradictory,"condition")$code=="CAPSULE_SOURCE_LANGUAGE_CONTRADICTION",
            attr(unsupported,"condition")$code=="CAPSULE_SOURCE_LANGUAGE_UNSUPPORTED")

  for(alias in c("R","r","Rscript","R_source")) {
    root<-file.path(work,paste0("bundle_",alias));b<-wb_init_bundle(root,overwrite=TRUE);wb_define_cells(b,c("c1","c2"))
    output<-file.path(work,paste0("out_",alias,".txt"));writeLines("reviewed terminal evidence",output)
    cap<-wb_capsule_register(
      b,paste0("reviewed-",alias),inputs=list(cells=wb_ref_metadata_field("core:cell_id")),
      script=ordinary,outputs=list(report=list(path=output,role="report",media_type="text/plain")),
      purpose="custom_terminal_summary",rationale="terminal source-review fixture",
      catalog_review=list(catalog_identity="scworkbench.operation_catalog",catalog_version="0.1.0",reviewed_at="2026-08-18T00:00:00Z",decision="retain_as_capsule"),
      language=alias
    )
    stopifnot(cap$language=="R",cap$assurance_level=="content_registered",cap$execution_mode=="externally_executed",cap$replay_status=="not_verified")
    wb_close_bundle(b)
  }
  TRUE
}
