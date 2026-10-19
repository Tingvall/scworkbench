# Literal old392 transient_usage body. The namespace is supplied by each test,
# not reconstructed from the new classifier or derived from its result.
.engine_spill_old392_usage <- function(path = "",budgets=.wb_graph_budgets()) {
  journal_paths <- paste0(path, c("-wal", "-journal", "-shm"))
  journal <- file.info(journal_paths)$size
  # SQLite unlinks temporary sort/spill files while their descriptors are
  # still open. Directory inventories alone would silently omit these bytes.
  # Procfs is used only inside core resource accounting; never exposed to packs.
  temp_bytes <- 0; owned_bytes <- 0; inventory <- numeric(); temporary_ids <- character()
  fd_root <- "/proc/self/fd"
  .wb_graph_require(dir.exists(fd_root), "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
    "Bounded graph SQLite runtime requires Linux procfs for unlinked temporary spill accounting.")
  if (dir.exists(fd_root)) {
    allowance <- .wb_graph_fd_metadata_reservation(budgets)
    names <- tryCatch(.Call(C_scwb_graph_source_directory,fd_root,allowance),error=function(error) {
      code <- if(startsWith(conditionMessage(error),"GRAPH_RESOURCE_EXCEEDED:"))
        "GRAPH_RESOURCE_EXCEEDED" else "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE"
      .wb_graph_error(code,conditionMessage(error))
    })
    used <- names[[2L]]
    for(name in names[[1L]]) {
      fd <- file.path(fd_root,name)
      link <- target <- NULL
      link <- tryCatch(.Call(C_scwb_graph_readlink,fd,allowance-used),error=function(error) {
        code <- if(startsWith(conditionMessage(error),"GRAPH_RESOURCE_EXCEEDED:"))
          "GRAPH_RESOURCE_EXCEEDED" else "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE"
        .wb_graph_error(code,conditionMessage(error))
      })
      if(is.null(link))next
      # Only one readlink result remains live. The directory names and owned
      # inode inventory survive the loop; unrelated visited paths do not.
      target <- link[[1L]]; link_charge <- link[[2L]]
      temporary <- grepl("(^|/)(etilqs_|scwb_graph_tokens_|scwb_graph_identity_|scwb_object_meta_)",target,useBytes=TRUE)
      if(!temporary && !grepl("(^|/)scwb_graph_stage_",target,useBytes=TRUE))next
      # Reserve a bounded stat/identity slot before constructing its R carrier.
      .wb_graph_require(used + link_charge + 2048 <= allowance,
        "GRAPH_RESOURCE_EXCEEDED", "Owned spill identity metadata exceeds bounded admission.")
      identity <- .wb_graph_file_identity(fd)
      size <- suppressWarnings(file.info(fd)$size)
      if(is.na(identity) || is.na(size))next
      before <- inventory[identity]
      if(is.na(before)) {
        # Includes names, inventory/temporary-ID vectors and their update copies.
        charge <- 1024 + 16 * (nchar(identity, type = "bytes") + 1)
        .wb_graph_require(used + link_charge + 2048 + charge <= allowance,
          "GRAPH_RESOURCE_EXCEEDED", "Owned spill inventory exceeds bounded admission.")
        used <- used + charge
        before <- 0
      }
      inventory[identity] <- max(size,before)
      if(temporary && !identity %in% temporary_ids)temporary_ids <- c(temporary_ids,identity)
    }
    owned_bytes <- sum(inventory)
    temp_bytes <- sum(inventory[temporary_ids])
  }
  usage <- list(journal_bytes = sum(journal[!is.na(journal)]), temporary_bytes = temp_bytes,
    owned_spill_bytes=owned_bytes,
    temporary_accounting = if (dir.exists(fd_root)) "procfs_open_descriptors" else "unavailable")
  attr(usage,"wb_graph_owned_spill_inventory") <- inventory
  usage
}

.engine_spill_old_kind <- function(target) {
  temporary <- grepl("(^|/)(etilqs_|scwb_graph_tokens_|scwb_graph_identity_|scwb_object_meta_)", target, useBytes = TRUE)
  if (temporary) 1L else if (grepl("(^|/)scwb_graph_stage_", target, useBytes = TRUE)) 2L else 0L
}

.engine_spill_fixture_inventory <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE))
  info <- file.info(paths); links <- Sys.readlink(paths)
  paths <- paths[(!is.na(info$isdir) & !info$isdir) | (!is.na(links) & nzchar(links))]
  setNames(vapply(paths, function(path) {
    link <- Sys.readlink(path)
    if (!is.na(link) && nzchar(link)) paste0("symlink:", link) else digest::digest(file = path, algo = "sha256")
  }, ""), substring(paths, nchar(root) + 2L))
}

test_engine_spill_classifier_literal_predicates_and_unsupported_contract <- function() {
  symbol <- get("C_scwb_graph_spill_path_kind", asNamespace("scworkbench"))
  prefixes <- c("etilqs_", "scwb_graph_tokens_", "scwb_graph_identity_", "scwb_object_meta_", "scwb_graph_stage_")
  endings <- c("", "x", " (deleted)", "\n", "\r\n", "/ordinary", "/scwb_graph_stage_child", "/etilqs_temp")
  corpus <- c("", "/", "etilqs", "xetilqs_x", "x/scwb_graph_stage", "ETILQS_x",
    "xscwb_graph_stage_x", "\netilqs_x", "x/\netilqs_x", " /etilqs_x", "x//etilqs_x",
    "x/../scwb_graph_stage_x", "x/./scwb_graph_tokens_x", "x/scwb_graph_stage_x/etilqs_t",
    "scwb_object_meta_x/scwb_graph_stage_y", "x/scwb_graph_stage_x/scwb_graph_identity_y")
  for (prefix in prefixes) for (ending in endings) for (start in c("", "/", "x/", "雪/", "\t/", "\n/", "x/\r/"))
    corpus <- c(corpus, paste0(start, prefix, ending))
  corpus <- c(corpus, vapply(seq_len(5000L), function(i) paste0(
    if (i %% 2L) "scwb_graph_stage_root/" else "ordinary/",
    prefixes[[i %% length(prefixes) + 1L]], i, if (i %% 3L) " (deleted)" else "\n"), ""))
  encoded <- c(iconv("café/etilqs_x", to = "latin1"), enc2utf8("雪/scwb_graph_stage_x"),
    paste0(rawToChar(as.raw(255L)), "/scwb_object_meta_x"))
  Encoding(encoded[[3L]]) <- "bytes"; corpus <- c(corpus, encoded)
  for (target in corpus) stopifnot(identical(.Call(symbol, target), .engine_spill_old_kind(target)))
  for (unsupported in list(NULL, character(), c("a", "b"), NA_character_, 1L, 1,
      list("etilqs_x"), structure("etilqs_x", names = "named"),
      structure("etilqs_x", class = "custom"), structure("etilqs_x", extra = TRUE)))
    stopifnot(is.null(.Call(symbol, unsupported)))
  stopifnot(identical(.Call(symbol, "scwb_graph_stage_parent/etilqs_child"), 1L),
    identical(.Call(symbol, "scwb_graph_stage_parent"), 2L), identical(.Call(symbol, "ordinary"), 0L))
  TRUE
}

test_engine_spill_readlink_actual_bytes_charge_and_fault_contract <- function() {
  if (!dir.exists("/proc/self/fd")) return(contract_test_skip("Native descriptor accounting requires Linux procfs"))
  symbol <- get("C_scwb_graph_readlink", asNamespace("scworkbench"))
  fd_count <- length(list.files("/proc/self/fd"))
  root <- tempfile("spill_readlink_fixture_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  for (i in seq_along(c("etilqs_target", "scwb_graph_stage_target", "ordinary"))) {
    target <- c("etilqs_target/雪 (deleted)", "scwb_graph_stage_target\n", "ordinary/../scwb_graph_tokens_hidden")[[i]]
    link <- file.path(root, paste0("link_", i)); stopifnot(file.symlink(target, link))
    before <- .engine_spill_fixture_inventory(root)
    charge <- 1024 + 8 * (nchar(target, type = "bytes") + 1)
    result <- .Call(symbol, link, charge)
    stopifnot(length(result) == 3L, identical(charToRaw(result[[1L]]), charToRaw(target)),
      identical(result[[2L]], charge), identical(result[[3L]], .engine_spill_old_kind(target)),
      as.numeric(object.size(result)) <= charge,
      identical(before, .engine_spill_fixture_inventory(root)))
    failed <- tryCatch(.Call(symbol, link, charge - 1), error = identity)
    stopifnot(inherits(failed, "error"), startsWith(conditionMessage(failed), "GRAPH_RESOURCE_EXCEEDED:"))
  }
  stopifnot(is.null(.Call(symbol, file.path(root, "absent"), 65536)))
  plain <- file.path(root, "plain"); writeBin(as.raw(1:5), plain)
  failed <- tryCatch(.Call(symbol, plain, 65536), error = identity)
  stopifnot(inherits(failed, "error"), startsWith(conditionMessage(failed), "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE:"))
  for (allowance in c(-1, NA_real_, Inf)) {
    failed <- tryCatch(.Call(symbol, file.path(root, "link_1"), allowance), error = identity)
    stopifnot(inherits(failed, "error"), startsWith(conditionMessage(failed), "GRAPH_RESOURCE_EXCEEDED:"))
  }
  stopifnot(length(list.files("/proc/self/fd")) == fd_count)
  TRUE
}

test_engine_spill_proc_inventory_dedup_growth_and_purity_contract <- function() {
  if (!dir.exists("/proc/self/fd")) return(contract_test_skip("Native descriptor accounting requires Linux procfs"))
  old <- .engine_spill_old392_usage; environment(old) <- asNamespace("scworkbench")
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "1048576", sqlite_cache_kib = 128L,
    partition_bytes = 1024L, partition_rows = 2L, collect_bytes = 65536L))
  root <- tempfile("spill_inventory_fixture_"); dir.create(root)
  handles <- list()
  on.exit({for (handle in handles) try(close(handle), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  main <- file.path(root, "main.sqlite")
  for (i in seq_along(c("-wal", "-journal", "-shm"))) writeBin(raw(i), paste0(main, c("-wal", "-journal", "-shm")[[i]]))
  baseline <- old(main, policy)
  temp <- file.path(root, "scwb_graph_identity_owned"); writeBin(raw(4096L), temp)
  alias <- file.path(root, "scwb_graph_stage_alias"); stopifnot(file.link(temp, alias))
  symbolic <- file.path(root, "ordinary_symbolic_alias"); stopifnot(file.symlink(temp, symbolic))
  stage <- file.path(root, "scwb_graph_stage_owned"); writeBin(raw(2048L), stage)
  ordinary <- file.path(root, "ordinary"); writeBin(raw(123L), ordinary)
  handles <- list(file(temp, "r+b"), file(alias, "rb"), file(stage, "rb"), file(ordinary, "rb"), file(symbolic, "rb"))
  compare <- function() {
    before <- .engine_spill_fixture_inventory(root)
    expected <- old(main, policy); actual <- scworkbench:::.wb_graph_transient_usage(main, policy)
    stopifnot(identical(actual, expected), identical(before, .engine_spill_fixture_inventory(root)),
      actual$journal_bytes == 6, actual$owned_spill_bytes == baseline$owned_spill_bytes + 4096 + 2048,
      actual$temporary_bytes == baseline$temporary_bytes + 4096)
    actual
  }
  compare(); unlink(temp); compare()
  # Grow the still-open unlinked TEMP inode; the stage hardlink aliases it.
  seek(handles[[1L]], where = 0, origin = "end", rw = "write")
  writeBin(raw(1024L), handles[[1L]]); flush(handles[[1L]])
  before <- .engine_spill_fixture_inventory(root)
  expected <- old(main, policy); actual <- scworkbench:::.wb_graph_transient_usage(main, policy)
  stopifnot(identical(actual, expected), actual$owned_spill_bytes == baseline$owned_spill_bytes + 5120 + 2048,
    actual$temporary_bytes == baseline$temporary_bytes + 5120,
    identical(before, .engine_spill_fixture_inventory(root)))
  for (handle in handles) close(handle); handles <- list()
  after <- scworkbench:::.wb_graph_transient_usage(main, policy)
  stopifnot(identical(after, old(main, policy)), after$owned_spill_bytes == baseline$owned_spill_bytes,
    after$temporary_bytes == baseline$temporary_bytes)
  TRUE
}

test_engine_spill_legacy_adapter_and_resource_cleanup_contract <- function() {
  if (!dir.exists("/proc/self/fd")) return(contract_test_skip("Native descriptor accounting requires Linux procfs"))
  old <- .engine_spill_old392_usage; environment(old) <- asNamespace("scworkbench")
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "1048576", sqlite_cache_kib = 128L,
    partition_bytes = 1024L, partition_rows = 2L, collect_bytes = 65536L))
  baseline <- old(budgets = policy)
  path <- tempfile("scwb_graph_tokens_classifier_"); writeBin(raw(4096L), path)
  handle <- file(path, "rb")
  on.exit({try(close(handle), silent = TRUE); unlink(path)}, add = TRUE)
  # Exercise the explicit older-two-field readlink fallback without changing
  # an installed namespace or manufacturing any descriptor observation.
  actual_call <- .Call; symbol <- get("C_scwb_graph_readlink", asNamespace("scworkbench"))
  fallback <- scworkbench:::.wb_graph_transient_usage; calls <- 0L
  environment(fallback) <- list2env(list(.Call = function(name, ...) {
    result <- actual_call(name, ...)
    if (identical(name, symbol) && !is.null(result)) {calls <<- calls + 1L; result[1:2]} else result
  }), parent = asNamespace("scworkbench"))
  before <- scworkbench:::.wb_graph_transient_usage(budgets = policy)
  stopifnot(identical(fallback(budgets = policy), old(budgets = policy)), calls > 0L)
  tiny <- policy; tiny$token_bytes <- as.character(before$owned_spill_bytes - 1)
  failed <- tryCatch(scworkbench:::.wb_graph_transient_admit(tiny), error = identity)
  stopifnot(inherits(failed, "wb_graph_error"), failed$code == "GRAPH_RESOURCE_EXCEEDED",
    identical(scworkbench:::.wb_graph_transient_usage(budgets = policy), before))
  exhausted <- policy; exhausted$memory_bytes <- "1"
  failed <- tryCatch(scworkbench:::.wb_graph_transient_usage(budgets = exhausted), error = identity)
  stopifnot(inherits(failed, "wb_graph_error"), failed$code == "GRAPH_RESOURCE_EXCEEDED")
  close(handle); unlink(path)
  stopifnot(identical(scworkbench:::.wb_graph_transient_usage(budgets = policy), baseline))
  TRUE
}
