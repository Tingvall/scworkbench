args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
devtools::load_all(args[[1L]], quiet = TRUE)
main <- function() {
  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(args[[2L]],
    operation = "snapshot observation concurrent owner", timeout_seconds = 0)
  on.exit(scworkbench:::.wb_bundle_writer_lock_release(lock), add = TRUE)
  stopifnot(file.create(args[[3L]]))
  deadline <- Sys.time() + 30
  while (!file.exists(args[[4L]])) {
    if (Sys.time() > deadline) stop("Concurrent snapshot fixture release deadline")
    Sys.sleep(0.02)
  }
}
main()
