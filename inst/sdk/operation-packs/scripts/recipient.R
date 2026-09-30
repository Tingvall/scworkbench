args <- commandArgs(TRUE)
library(scworkbench)
fingerprint <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  paths <- paths[!dir.exists(file.path(root, paths))]
  list(paths = paths, hashes = unname(vapply(file.path(root, paths),
    function(x) digest::digest(file = x, algo = "sha256"), character(1))))
}
before <- fingerprint(args[[1L]])
stopifnot(!args[[2L]] %in% wb_list_ops())
bundle <- wb_open_bundle(args[[1L]], read_only = TRUE)
stopifnot(isTRUE(wb_validate_bundle(args[[1L]], read_only = TRUE)))
artifacts <- wb_art_list(bundle)
stopifnot(nrow(artifacts) >= 2L)
for (id in artifacts$artifact_id) stopifnot(inherits(wb_art_load(bundle, id), "wb_primitive"))
wb_close_bundle(bundle)
stopifnot(identical(before, fingerprint(args[[1L]])))
copy <- tempfile("sdk-missing-pack-"); dir.create(copy)
stopifnot(all(file.copy(list.files(args[[1L]], full.names = TRUE, all.files = TRUE,
  no.. = TRUE), copy, recursive = TRUE)))
bundle <- wb_open_bundle(copy)
state <- wb_operation_pack_sdk_state(bundle)
failure <- tryCatch(wb_session_run_op(wb_session_new(), bundle, args[[2L]],
  inputs = list(matrix = "counts", cell_set = "all", min_cells = 1L)), error = identity)
stopifnot(inherits(failure, "error"), identical(state, wb_operation_pack_sdk_state(bundle)))
wb_close_bundle(bundle)
cat("RECIPIENT_READ_ONLY_VALID; PACK_FREE_INSPECTION; MISSING_PACK_REJECTED; FINGERPRINT_UNCHANGED\n")
