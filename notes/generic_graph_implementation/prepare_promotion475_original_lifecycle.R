args <- commandArgs(TRUE)
stopifnot(length(args)==1L,!file.exists(args[[1L]]))
original <- readRDS("/tmp/scwb-graph-native-long-axis-90000-development/measurement-9a11d1f.rds")
fixture <- original
fixture$core_library <- "/tmp/scwb-graph-forge-promotion-metadata-476.ld91mtp4/library"
.libPaths(c(fixture$core_library,.libPaths()))
library(scworkbench,lib.loc=fixture$core_library)
stopifnot(fixture$source_axis_count==90000L,fixture$source_axis_utf8_bytes==18258618L,
  identical(fixture$source_bundle,original$source_bundle),
  identical(fixture$seed_graph_artifact_id,original$seed_graph_artifact_id),
  identical(fixture$source_axis_artifact_id,original$source_axis_artifact_id),
  identical(fixture$pack_identity,original$pack_identity),
  identical(fixture$pack_library,original$pack_library),
  identical(normalizePath(find.package("scworkbench")),
    normalizePath(file.path(fixture$core_library,"scworkbench"))))
body_sha <- function(name)digest::digest(paste(deparse(body(getFromNamespace(
  name,"scworkbench"))),collapse="\n"),algo="sha256",serialize=FALSE)
checkpoint <- list(name="promotion475_original90000_2x_development",tuple=475L,
  qualification=FALSE,
  source_ledger="notes/generic_graph_implementation/evidence/475_promotion_metadata_complete_review_tuple.sha256",
  source_ledger_sha256="4e804356310a00cad69c01fbe82f68e90564fb8a36e0db7aa2267a87e7b86e16",
  original_db_sha256=digest::digest(file=file.path(fixture$source_bundle,"db/app.sqlite"),algo="sha256"),
  source_closure_function_sha256=body_sha(".wb_graph_object_closure"),
  promotion_fingerprint_function_sha256=body_sha(".wb_promotion_runtime_fingerprint"),
  promotion_package_version_function_sha256=body_sha(".wb_promotion_package_version"),
  dll_sha256=digest::digest(file=getLoadedDLLs()[["scworkbench"]][["path"]],algo="sha256"))
stopifnot(identical(digest::digest(file=checkpoint$source_ledger,algo="sha256"),
    checkpoint$source_ledger_sha256),
  identical(checkpoint$original_db_sha256,"6b28d22214259aa2036449df48c0b5624b3851fa150cf05d7ae87c055f5f2be0"),
  identical(checkpoint$source_closure_function_sha256,"846f70d1460ef7a730dd87282281ad12264695b956c838740dc5aa39b9e8e9d9"),
  identical(checkpoint$dll_sha256,"ead7462807fb7920e924aa8995ec3ddb26ecbf87dd2c2d4b6ccf21f3b7a1bd56"))
fixture$development_checkpoint <- checkpoint
saveRDS(fixture,args[[1L]])
cat("PREPARED_PROMOTION475_ORIGINAL axes=90000 axis_utf8_bytes=18258618 unchanged_seed_pack_source=TRUE runtime=",
  find.package("scworkbench")," run_started=FALSE qualification=FALSE\n",sep="")
