# Ordinary legacy content is distinct from authority to bind a graph source.
.graph_legacy_fixture <- function(root, pre_descriptor = FALSE) {
  archive <- "tests/fixtures/graph_legacy_object_fa929.tar.gz"
  expected <- "tests/fixtures/graph_legacy_object_fa929_expected.rds"
  stopifnot(digest::digest(file=archive,algo="sha256",serialize=FALSE)==
    "9e569729324d17575273245d05964fb361d83ac467e462e2e0864e4966ce11bc",
    digest::digest(file=expected,algo="sha256",serialize=FALSE)==
    "07227a46a348215f8301070897da62b7d14e7062dee62b552382f4a8a153fae3")
  if (pre_descriptor) {
    archive <- "tests/fixtures/graph_legacy_object_fa47.tar.gz"
    expected <- "tests/fixtures/graph_legacy_object_fa47_expected.rds"
    stopifnot(digest::digest(file=archive,algo="sha256",serialize=FALSE)==
      "9e3d0723a1ca9baa489ae446e7e14785b9b14fd6b0f6134d27aef668bf174d5d",
      digest::digest(file=expected,algo="sha256",serialize=FALSE)==
      "2c6fcc01501909577d2137d8cae556a5cc9636d2c74510551bf622dfd948e0d2")
  }
  utils::untar(archive,exdir=root)
  list(path=file.path(root,"authentic.bundle"),expected=readRDS(expected))
}

test_graph_authentic_legacy_object_content_load_contract <- function() {
  root <- tempfile("legacy_object_content_");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  for (pre_descriptor in c(FALSE, TRUE)) {
    case_root <- file.path(root,if(pre_descriptor) "pre_descriptor" else "ordered_descriptor")
    dir.create(case_root)
    fixture <- .graph_legacy_fixture(case_root,pre_descriptor)
    b <- wb_open_bundle(fixture$path)
    tryCatch({
      loaded <- wb_art_load(b,fixture$expected$id)
      stopifnot(identical(unclass(loaded),unclass(fixture$expected$primitive)),
        identical(scworkbench:::.wb_prov_payload_identity(b,loaded)$content_sha256,
          fixture$expected$identity$content_sha256),
        identical(DBI::dbGetQuery(b$con,"SELECT version FROM bundle_schema_migrations ORDER BY version;")$version,1:11))
      denied <- tryCatch(scworkbench:::.wb_graph_object_verify(b$con,fixture$expected$id),error=identity)
      stopifnot(inherits(denied,"wb_graph_error"),denied$code=="GRAPH_SOURCE_AUTHORITY_REQUIRED")
      if(pre_descriptor) {
        DBI::dbExecute(b$con,"UPDATE artifact_pseudotime SET pseudotime=pseudotime+1 WHERE artifact_id=? AND cell_id='c1';",params=list(fixture$expected$id))
        mutated <- tryCatch(wb_art_load(b,fixture$expected$id),error=identity)
        stopifnot(inherits(mutated,"wb_graph_error"),mutated$code=="ARTIFACT_CONTENT_IDENTITY_MISMATCH")
      }
    },finally=wb_close_bundle(b))
  }
  TRUE
}

test_graph_object_proof_removal_content_and_authority_contract <- function() {
  root <- tempfile("object_proof_removal_");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  b <- wb_init_bundle(file.path(root,"modern.bundle"))
  wb_define_cells(b,c("c3","c1","c4","c2"))
  primitive <- wb_prim_cell_vector_family(c("K2","K1","K2","K1"),
    c("c4","c3","c2","c1"),c(4,1.5,2.5,3),value_type="continuous",meta=list(label="retained content"))
  run <- wb_new_run("metadata_cell_vector",inputs=list(),outputs=list(vector=primitive))
  promoted <- wb_promote_analysis(b,stats::setNames(list(run),run$run_id),head_run_id=run$run_id,outputs="vector")
  id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(identical(unclass(wb_art_load(b,id)),unclass(primitive)))
  wb_close_bundle(b)
  remove_all <- function(con) {
    DBI::dbExecute(con,"DELETE FROM artifact_object_metadata_chunks WHERE artifact_id=?;",params=list(id))
    DBI::dbExecute(con,"DELETE FROM artifact_object_payload_meta WHERE artifact_id=?;",params=list(id))
    DBI::dbExecute(con,"UPDATE prov_run_outputs SET retained_payload_identity_json=NULL WHERE artifact_id=?;",params=list(id))
    DBI::dbExecute(con,"UPDATE artifact_pseudotime SET payload_ordinal=NULL WHERE artifact_id=?;",params=list(id))
  }
  cases <- c("header","chunks","ordinals","retained_certificate","all","all_value",
    "all_metadata","all_order","all_missing_content","all_unsupported_scheme")
  for(case in cases) {
    path <- file.path(root,paste0(case,".bundle"));fs::dir_copy(file.path(root,"modern.bundle"),path)
    current <- wb_open_bundle(path)
    tryCatch({
      con <- current$con
      if(startsWith(case,"all"))remove_all(con)
      else if(case=="header") {
        DBI::dbExecute(con,"DELETE FROM artifact_object_metadata_chunks WHERE artifact_id=?;",params=list(id))
        DBI::dbExecute(con,"DELETE FROM artifact_object_payload_meta WHERE artifact_id=?;",params=list(id))
      }
      else if(case=="chunks")DBI::dbExecute(con,"DELETE FROM artifact_object_metadata_chunks WHERE artifact_id=?;",params=list(id))
      else if(case=="ordinals")DBI::dbExecute(con,"UPDATE artifact_pseudotime SET payload_ordinal=NULL WHERE artifact_id=?;",params=list(id))
      else DBI::dbExecute(con,"UPDATE prov_run_outputs SET retained_payload_identity_json=NULL WHERE artifact_id=?;",params=list(id))
      if(case=="all_value")DBI::dbExecute(con,"UPDATE artifact_pseudotime SET pseudotime=pseudotime+1 WHERE artifact_id=? AND cell_id='c4';",params=list(id))
      if(case %in% c("all_metadata","all_order")) {
        provenance <- jsonlite::fromJSON(DBI::dbGetQuery(con,"SELECT provenance_json FROM artifacts WHERE artifact_id=?;",params=list(id))$provenance_json[[1]],simplifyVector=FALSE)
        if(case=="all_metadata")provenance$primitive_payload$meta_r_json <- jsonlite::serializeJSON(list(label="mutated"),digits=NA)
        else provenance$primitive_payload$row_order <- rev(provenance$primitive_payload$row_order)
        DBI::dbExecute(con,"UPDATE artifacts SET provenance_json=? WHERE artifact_id=?;",params=list(jsonlite::toJSON(provenance,auto_unbox=TRUE,null="null"),id))
      }
      if(case=="all_missing_content")DBI::dbExecute(con,"UPDATE prov_run_outputs SET content_sha256=NULL WHERE artifact_id=?;",params=list(id))
      if(case=="all_unsupported_scheme")DBI::dbExecute(con,"UPDATE prov_run_outputs SET content_identity_scheme='unsupported.object.identity' WHERE artifact_id=?;",params=list(id))
      observed <- tryCatch(wb_art_load(current,id),error=identity)
      if(case=="all")stopifnot(identical(unclass(observed),unclass(primitive)))
      else stopifnot(inherits(observed,"error"))
      graph_source <- tryCatch(scworkbench:::.wb_graph_object_verify(con,id),error=identity)
      stopifnot(inherits(graph_source,"wb_graph_error"))
    },finally=wb_close_bundle(current))
  }
  original <- wb_open_bundle(file.path(root,"modern.bundle"),read_only=TRUE)
  stopifnot(identical(unclass(wb_art_load(original,id)),unclass(primitive)))
  wb_close_bundle(original)
  TRUE
}
