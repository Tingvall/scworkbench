test_relative_bundle_writer_lock_identity_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE) ||
      !requireNamespace("Matrix", quietly = TRUE)) {
    return(contract_test_skip("BPCells and Matrix are required for relative-path 10x ingestion"))
  }

  repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  root <- tempfile("scwb_relative_lock_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  prior <- setwd(root)
  on.exit(setwd(prior), add = TRUE)

  target_id <- function(path) scworkbench:::.wb_writer_lock_target(path)
  lock_path <- function(path) scworkbench:::.wb_writer_lock_path(path)
  residue <- function(path) {
    parent <- dirname(target_id(path))
    stem <- paste0(".", basename(target_id(path)), ".scworkbench-writer-lock")
    entries <- list.files(parent, all.files = TRUE, no.. = TRUE)
    entries[startsWith(entries, stem)]
  }

  # Fresh relative, absolute, nested, dot/parent, and tilde spellings all have
  # absolute identities before creation.  Creation cannot change the key.
  relative <- "relative.bundle"
  absolute <- file.path(root, relative)
  before <- target_id(relative)
  stopifnot(identical(before, normalizePath(absolute, winslash = "/", mustWork = FALSE)),
            identical(before, target_id(absolute)), scworkbench:::.wb_path_is_absolute(before))
  b <- wb_init_bundle(relative)
  stopifnot(identical(before, target_id(relative)), identical(before, target_id(b)),
            isTRUE(wb_validate_bundle(relative)))
  wb_close_bundle(b)
  stopifnot(!isTRUE(wb_bundle_writer_lock_info(relative)$locked), !length(residue(relative)))

  absolute_fresh <- file.path(root, "absolute.bundle")
  absolute_before <- target_id(absolute_fresh)
  ba <- wb_init_bundle(absolute_fresh)
  wb_close_bundle(ba)
  stopifnot(identical(absolute_before, target_id(absolute_fresh)), isTRUE(wb_validate_bundle(absolute_fresh)))

  nested <- file.path("missing", "parents", "nested.bundle")
  nested_before <- target_id(nested)
  bn <- wb_init_bundle(nested)
  wb_close_bundle(bn)
  stopifnot(identical(nested_before, target_id(nested)), isTRUE(wb_validate_bundle(nested)))

  dotted <- file.path("spelling", ".", "child", "..", "same.bundle")
  direct <- file.path("spelling", "same.bundle")
  stopifnot(identical(target_id(dotted), target_id(direct)))
  outer <- scworkbench:::.wb_bundle_writer_lock_acquire(dotted, operation = "outer spelling")
  inner <- scworkbench:::.wb_bundle_writer_lock_acquire(target_id(direct), operation = "inner spelling")
  stopifnot(identical(outer$key, inner$key), isTRUE(wb_bundle_writer_lock_info(direct)$held_by_current_process))
  stopifnot(isTRUE(scworkbench:::.wb_bundle_writer_lock_release(inner)),
            isTRUE(wb_bundle_writer_lock_info(dotted)$locked))
  stopifnot(isTRUE(scworkbench:::.wb_bundle_writer_lock_release(outer)), !length(residue(direct)))

  tilde_probe <- file.path("~", paste0(".scworkbench-lock-probe-", Sys.getpid()))
  stopifnot(identical(target_id(tilde_probe),
                      file.path(normalizePath(path.expand("~"), winslash = "/", mustWork = TRUE),
                                basename(tilde_probe))))

  # Existing symlinked ancestors resolve to their physical parent.  Alias and
  # physical spellings share both the key and sibling coordination path.
  real_parent <- file.path(root, "physical_parent")
  alias_parent <- file.path(root, "alias_parent")
  dir.create(real_parent)
  if (.Platform$OS.type != "windows") {
    stopifnot(isTRUE(file.symlink(real_parent, alias_parent)))
    via_alias <- file.path(alias_parent, "symlink.bundle")
    physical <- file.path(real_parent, "symlink.bundle")
    stopifnot(identical(target_id(via_alias), target_id(physical)),
              identical(lock_path(via_alias), lock_path(physical)),
              startsWith(lock_path(via_alias), paste0(normalizePath(real_parent), "/")))
    bs <- wb_init_bundle(via_alias)
    wb_close_bundle(bs)
    stopifnot(isTRUE(wb_validate_bundle(physical)), !length(residue(physical)))
  }

  # A failure after acquisition retires exactly its own lock and never writes a
  # manifest claiming a committed bundle.
  failed_target <- file.path(root, "forced_failure.bundle")
  writeLines("blocks directory creation", failed_target)
  failed <- try(wb_init_bundle(failed_target), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), !file.exists(file.path(failed_target, "manifest.json")),
            !isTRUE(wb_bundle_writer_lock_info(failed_target)$locked), !length(residue(failed_target)))

  # Relative and absolute spellings contend across independent R processes.
  contention <- "contended.bundle"
  ready <- file.path(root, "worker.ready")
  release <- file.path(root, "worker.release")
  done <- file.path(root, "worker.done")
  log <- file.path(root, "worker.log")
  worker <- file.path(root, "relative_lock_worker.R")
  writeLines(c(
    "args <- commandArgs(trailingOnly=TRUE)",
    "repo <- args[[1]]; root <- args[[2]]; ready <- args[[3]]; release <- args[[4]]; done <- args[[5]]",
    "devtools::load_all(repo, quiet=TRUE); setwd(root)",
    "lock <- scworkbench:::.wb_bundle_writer_lock_acquire('contended.bundle', operation='relative subprocess', timeout_seconds=2)",
    "writeLines('ready', ready); while (!file.exists(release)) Sys.sleep(0.02)",
    "stopifnot(isTRUE(scworkbench:::.wb_bundle_writer_lock_release(lock)))",
    "writeLines('done', done)"
  ), worker, useBytes = TRUE)
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    c(worker, repo, root, ready, release, done),
                    stdout = log, stderr = log, wait = FALSE)
  stopifnot(identical(as.integer(status), 0L))
  wait_for <- function(path, timeout = 20) {
    start <- proc.time()[["elapsed"]]
    while (!file.exists(path)) {
      if (proc.time()[["elapsed"]] - start > timeout) stop("Timed out waiting for subprocess: ", path)
      Sys.sleep(0.02)
    }
  }
  wait_until <- function(predicate, label, timeout = 20) {
    start <- proc.time()[["elapsed"]]
    while (!isTRUE(predicate())) {
      if (proc.time()[["elapsed"]] - start > timeout) stop("Timed out waiting for ", label)
      Sys.sleep(0.02)
    }
  }
  wait_for(ready)
  blocked <- try(scworkbench:::.wb_bundle_writer_lock_acquire(
    file.path(root, contention), operation = "absolute contender", timeout_seconds = 0
  ), silent = TRUE)
  stopifnot(inherits(blocked, "try-error"), grepl("Timed out", as.character(blocked), fixed = TRUE))
  writeLines("release", release)
  wait_for(done)
  wait_until(function() !isTRUE(wb_bundle_writer_lock_info(contention)$locked),
             "subprocess lock release")
  stopifnot(!isTRUE(wb_bundle_writer_lock_info(contention)$locked), !length(residue(contention)))

  # The public 10x constructor promotes through the same relative identity and
  # leaves a reopenable, validated bundle with no staging/lock quarantine.
  input <- file.path(root, "tenx_input")
  dir.create(input)
  matrix_path <- file.path(input, "sample_matrix.mtx")
  barcodes_path <- file.path(input, "sample_barcodes.tsv")
  features_path <- file.path(input, "sample_features.tsv")
  counts <- Matrix::Matrix(c(1, 0, 2, 3, 1, 0), nrow = 3L, ncol = 2L, sparse = TRUE,
                           dimnames = list(c("gene1", "gene2", "gene3"), c("AAAC-1", "TTTG-1")))
  Matrix::writeMM(counts, matrix_path)
  writeLines(colnames(counts), barcodes_path)
  utils::write.table(data.frame(rownames(counts), rownames(counts), "Gene Expression"),
                     features_path, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
  sample_table <- data.frame(sample_id = "sample", matrix_path = matrix_path,
                             barcodes_path = barcodes_path, features_path = features_path,
                             stringsAsFactors = FALSE)
  tenx_relative <- "relative_10x.bundle"
  bt <- wb_bundle_from_10x_mtx(input, tenx_relative, sample_table = sample_table,
                               overwrite = TRUE, emit_report_artifact = FALSE)
  stopifnot(identical(wb_cells(bt, "core"), c("sample:AAAC-1", "sample:TTTG-1")))
  wb_close_bundle(bt)
  reopened <- wb_open_bundle(file.path(root, tenx_relative), validate = TRUE)
  stopifnot(isTRUE(wb_validate_bundle(reopened$dir)), "RNA_counts" %in% wb_matrices(reopened)$matrix_id)
  wb_close_bundle(reopened)
  siblings <- list.files(root, all.files = TRUE, no.. = TRUE)
  stopifnot(!file.exists(file.path(root, tenx_relative, "INGEST_FAILED.json")),
            !any(grepl("relative_10x[.]bundle_staging", siblings)),
            !any(grepl("scworkbench-writer-lock", siblings, fixed = TRUE)))
  TRUE
}
