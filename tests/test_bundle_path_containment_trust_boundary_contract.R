test_bundle_path_containment_trust_boundary_contract <- function() {
  root <- tempfile("scwb_path_boundary_")
  dir.create(root, recursive=TRUE)
  on.exit(unlink(root, recursive=TRUE, force=TRUE), add=TRUE)
  bundle_dir <- file.path(root, "source.bundle")
  b <- wb_init_bundle(bundle_dir, overwrite=TRUE)
  cells <- c("c1","c2","c3")
  wb_define_cells(b, cells)
  wb_attach_space(b, "fit_space", data.frame(cell_id=cells,x=1:3,y=c(3,2,1)))
  prim <- wb_prim_model_ref("fit_space", in_space_id="fit_space", engine="monocle3")
  prim$model_type <- "monocle3"
  prim$model_obj <- list(contract="contained-model", cells=cells)
  run <- wb_new_run(
    op_name="scvi_train",
    inputs=list(cell_set="core", user_inputs=list(fit_space=wb_prim_space("fit_space")),
                execution_inputs=list(resolved=list(fit_space=wb_prim_space("fit_space")))),
    params=list(), outputs=list(model=prim)
  )
  promoted <- wb_promote_analysis(b, runs=setNames(list(run),run$run_id),
                                  head_run_id=run$run_id, fail_fast=TRUE)
  output_col <- if("output_name" %in% names(promoted$promoted)) "output_name" else "output"
  aid <- as.character(promoted$promoted$artifact_id[promoted$promoted[[output_col]]=="model"])[1]
  row <- DBI::dbGetQuery(b$con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(aid))
  rel <- as.character(row$model_path[1])
  stopifnot(isTRUE(wb_bundle_path_status(b,rel)$ok))
  stopifnot(identical(wb_bundle_path_status(b,"../escape",must_exist=FALSE)$code,"PATH_ESCAPE"))
  stopifnot(identical(wb_bundle_path_status(b,"/tmp/external",must_exist=FALSE)$code,"PATH_ABSOLUTE"))
  stopifnot(identical(wb_bundle_path_status(b,"models/missing.rds")$code,"PAYLOAD_MISSING"))
  loaded <- wb_art_load(b,aid,expected_kind="model_ref")
  stopifnot(identical(loaded$model_obj$contract,"contained-model"))
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)

  copy_bundle <- function(name) {
    destination <- file.path(root,name)
    dir.create(destination, recursive=TRUE)
    stopifnot(file.copy(bundle_dir, destination, recursive=TRUE))
    file.path(destination,basename(bundle_dir))
  }
  update_model_path <- function(path, value) {
    x <- wb_open_bundle(path)
    DBI::dbExecute(x$con,"UPDATE artifact_model_ref SET model_path=? WHERE artifact_id=?;",params=list(value,aid))
    scworkbench:::.wb_with_mutation_context(x,route="ingestion",code=wb_refresh_manifest(x))
    wb_finalize_recipient_bundle(x)
    wb_close_bundle(x)
  }

  moved <- copy_bundle("moved-parent")
  moved_bundle <- wb_open_bundle(moved,read_only=TRUE)
  moved_loaded <- wb_art_load(moved_bundle,aid,expected_kind="model_ref")
  stopifnot(identical(moved_loaded$model_obj$contract,"contained-model"))
  wb_close_bundle(moved_bundle)

  traversal <- copy_bundle("traversal")
  man_path <- file.path(traversal,"manifest.json")
  man <- jsonlite::read_json(man_path,simplifyVector=TRUE)
  man$storage$sqlite$path <- "../outside.sqlite"
  jsonlite::write_json(man,man_path,auto_unbox=TRUE,pretty=TRUE,null="null")
  report <- wb_bundle_validation_report(traversal,level="recipient")
  stopifnot("PATH_ESCAPE" %in% report$diagnostics$code)
  open_error <- tryCatch(wb_open_bundle(traversal,read_only=TRUE),error=function(e)e)
  stopifnot(inherits(open_error,"error"),grepl("PATH_ESCAPE",conditionMessage(open_error),fixed=TRUE))

  materialization_traversal <- copy_bundle("materialization-traversal")
  mt <- wb_open_bundle(materialization_traversal)
  DBI::dbExecute(mt$con,"UPDATE prov_run_outputs SET materialization_path='../external-materialization.rds' WHERE rowid=(SELECT rowid FROM prov_run_outputs ORDER BY rowid LIMIT 1);")
  scworkbench:::.wb_with_mutation_context(mt,route="ingestion",code=wb_refresh_manifest(mt))
  wb_finalize_recipient_bundle(mt)
  wb_close_bundle(mt)
  materialization_report <- wb_bundle_validation_report(materialization_traversal,level="recipient")
  stopifnot(any(materialization_report$diagnostics$code=="PATH_ESCAPE" & materialization_report$diagnostics$table=="prov_run_outputs"))

  manifest_link <- copy_bundle("manifest-link")
  external_manifest <- file.path(root,"external-manifest.json")
  file.copy(file.path(manifest_link,"manifest.json"),external_manifest)
  unlink(file.path(manifest_link,"manifest.json"),force=TRUE)
  stopifnot(file.symlink(external_manifest,file.path(manifest_link,"manifest.json")))
  manifest_link_report <- wb_bundle_validation_report(manifest_link,level="recipient")
  stopifnot("PATH_SYMLINK_ESCAPE" %in% manifest_link_report$diagnostics$code)

  outside <- file.path(root,"outside-model.rds")
  saveRDS(list(contract="external"),outside)
  absolute <- copy_bundle("absolute")
  unlink(file.path(absolute,rel),recursive=TRUE,force=TRUE)
  update_model_path(absolute,outside)
  absolute_report <- wb_bundle_validation_report(absolute,level="recipient")
  stopifnot("PATH_ABSOLUTE" %in% absolute_report$diagnostics$code)
  abs_bundle <- wb_open_bundle(absolute)
  DBI::dbExecute(abs_bundle$con,paste(
    "INSERT INTO space_models(space_id,model_type,source_space_id,dims_json,cell_set,uwot_args_json,seed,model_path,created_at,provenance_json)",
    "VALUES(?,?,?,?,?,?,?,?,?,?);"
  ),params=list("fit_space","legacy_rds","fit_space","[1,2]","all","{}",NA_integer_,outside,"2026-08-04 00:00:00","{}"))
  load_error <- tryCatch(wb_art_load(abs_bundle,aid,expected_kind="model_ref"),error=function(e)e)
  stopifnot(inherits(load_error,"error"),grepl("LEGACY_EXTERNAL_MODEL_REFERENCE",conditionMessage(load_error),fixed=TRUE))
  plan <- wb_repair_model_ref_paths(abs_bundle,dry_run=TRUE)
  stopifnot(identical(plan$action[plan$registry_table=="artifact_model_ref" & plan$entity_id==aid],"legacy_external_nonportable"))
  stopifnot(identical(plan$action[plan$registry_table=="space_models" & plan$entity_id=="fit_space"],"legacy_external_nonportable"))
  imported <- wb_repair_model_ref_paths(abs_bundle,dry_run=FALSE,import_external=TRUE)
  imported_row <- imported[imported$registry_table=="artifact_model_ref" & imported$entity_id==aid,,drop=FALSE]
  stopifnot(identical(imported_row$action,"import_legacy_external"))
  imported_space <- DBI::dbGetQuery(abs_bundle$con,"SELECT model_path FROM space_models WHERE space_id='fit_space';")$model_path[1]
  stopifnot(!scworkbench:::.wb_path_is_absolute(imported_space),isTRUE(wb_bundle_path_status(abs_bundle,imported_space)$ok))
  stored <- DBI::dbGetQuery(abs_bundle$con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(aid))$model_path[1]
  stopifnot(!scworkbench:::.wb_path_is_absolute(stored),isTRUE(wb_bundle_path_status(abs_bundle,stored)$ok))
  missing_external <- file.path(root,"never-created.rds")
  DBI::dbExecute(abs_bundle$con,"UPDATE artifact_model_ref SET model_path=? WHERE artifact_id=?;",params=list(missing_external,aid))
  failed <- tryCatch(wb_repair_model_ref_paths(abs_bundle,dry_run=FALSE,import_external=TRUE),error=function(e)e)
  stopifnot(inherits(failed,"error"))
  stopifnot(identical(DBI::dbGetQuery(abs_bundle$con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(aid))$model_path[1],missing_external))
  wb_close_bundle(abs_bundle)

  symlink_bundle <- copy_bundle("symlink")
  safe_path <- file.path(symlink_bundle,rel)
  unlink(safe_path,recursive=TRUE,force=TRUE)
  stopifnot(file.symlink(outside,safe_path))
  symlink_report <- wb_bundle_validation_report(symlink_bundle,level="recipient")
  stopifnot("PATH_SYMLINK_ESCAPE" %in% symlink_report$diagnostics$code)
  stopifnot(isFALSE(symlink_report$path_contract$unsafe_payloads_loaded))

  nested_symlink_bundle <- copy_bundle("nested-symlink")
  nested_model <- file.path(nested_symlink_bundle,rel)
  unlink(nested_model,recursive=TRUE,force=TRUE)
  dir.create(nested_model,recursive=TRUE)
  stopifnot(file.symlink(outside,file.path(nested_model,"external-state.rds")))
  nested_symlink_report <- wb_bundle_validation_report(nested_symlink_bundle,level="recipient")
  stopifnot("PATH_SYMLINK_ESCAPE" %in% nested_symlink_report$diagnostics$code)
  stopifnot(isFALSE(nested_symlink_report$path_contract$unsafe_payloads_loaded))

  corrupt <- copy_bundle("corrupt")
  writeLines("not serialized model state",file.path(corrupt,rel))
  corrupt_report <- wb_bundle_validation_report(corrupt,level="recipient")
  stopifnot(isFALSE(corrupt_report$path_contract$unsafe_payloads_loaded))
  stopifnot(!"MODEL_PAYLOAD_UNREADABLE" %in% corrupt_report$diagnostics$code)
  TRUE
}
