test_file_backed_dense_space_storage_contract <- function() {
  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    return(contract_test_skip("rhdf5 is not installed."))
  }
  root <- tempfile("scwb_dense_space_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- sprintf("cell_%03d", seq_len(240L))
  wb_define_cells(b, cells)

  make_space <- function(n_dims, ids = cells, offset = 0) {
    ans <- outer(seq_along(ids), seq_len(n_dims), function(i, j) sin(i / 13 + j) + offset)
    rownames(ans) <- ids
    colnames(ans) <- paste0("axis_", seq_len(n_dims))
    ans
  }
  expected <- list(s2 = make_space(2L), s30 = make_space(30L), s50 = make_space(50L))
  wb_add_space(b, "s2", expected$s2, source = "contract")
  wb_add_space(b, "s30", expected$s30, source = "contract")
  wb_add_space(b, "s50", expected$s50, source = "contract")
  partial_ids <- cells[c(90:121, 3:17)]
  expected$partial <- make_space(30L, partial_ids, 3)
  wb_add_space(b, "partial", expected$partial, source = "contract")

  tables <- DBI::dbListTables(b$con)
  stopifnot("space_payloads" %in% tables,
            !any(c("space_coords", "space_2d", "artifact_space_2d") %in% tables),
            nrow(DBI::dbGetQuery(b$con, "SELECT * FROM space_payloads")) == 4L,
            all(wb_spaces(b)$storage == scworkbench:::.wb_space_payload_storage()))

  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  got2 <- wb_space(b, "s2")
  stopifnot(is.data.frame(got2), identical(got2$cell_id, cells),
            isTRUE(all.equal(unname(as.matrix(got2[, c("x", "y")])), unname(expected$s2))))
  for (id in c("s30", "s50", "partial")) {
    got <- wb_space(b, id)
    expected_order <- cells[cells %in% rownames(expected[[id]])]
    stopifnot(is.matrix(got), identical(rownames(got), expected_order),
              identical(colnames(got), colnames(expected[[id]])),
              isTRUE(all.equal(as.numeric(got), as.numeric(expected[[id]][expected_order, , drop = FALSE]))))
  }

  requested <- cells[c(211:240, 1:70)]
  dims <- c(50L, 3L, 17L, 1L, 29L)
  subset <- wb_space(b, "s50", cells = requested, dims = dims)
  evidence <- attr(subset, "scworkbench_payload_read")
  stopifnot(identical(rownames(subset), requested),
            identical(colnames(subset), colnames(expected$s50)[dims]),
            isTRUE(all.equal(as.numeric(subset), as.numeric(expected$s50[requested, dims, drop = FALSE]))),
            identical(evidence$rows_read, 100L), identical(evidence$dims_read, 5L),
            identical(evidence$values_read, 500L), evidence$total_values == 12000L)
  permuted <- rev(partial_ids)
  stopifnot(identical(rownames(wb_space(b, "partial", cells = permuted, dims = c(9L, 2L))), permuted))

  options(scworkbench.space_payload_publication_hook = function(...) stop("forced payload publication fault"))
  failed <- try(scworkbench:::.wb_space_payload_write(
    b, "publication_fault", make_space(2L, offset = 100), source = "contract"
  ), silent = TRUE)
  options(scworkbench.space_payload_publication_hook = NULL)
  stopifnot(inherits(failed, "try-error"), grepl("forced payload publication fault", failed),
            !nrow(DBI::dbGetQuery(b$con, "SELECT * FROM space_payloads WHERE space_id='publication_fault'")),
            !nrow(DBI::dbGetQuery(b$con, "SELECT * FROM spaces WHERE space_id='publication_fault'")))
  pending <- list.files(file.path(root, "space_payloads", ".pending"), all.files = TRUE,
                        no.. = TRUE, recursive = TRUE)
  registered <- DBI::dbGetQuery(b$con, "SELECT path FROM space_payloads")$path
  published <- list.files(file.path(root, "space_payloads"), pattern = "[.]h5$", full.names = FALSE)
  stopifnot(!length(pending), setequal(basename(registered), published))

  stopifnot(isTRUE(wb_validate_bundle(root)))
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)
  b <- wb_open_bundle(root, read_only = TRUE)
  stopifnot(isTRUE(wb_validate_bundle(root, read_only = TRUE)),
            !file.exists(file.path(root, "db", "app.sqlite-wal")),
            !file.exists(file.path(root, "db", "app.sqlite-shm")))

  r_files <- list.files("R", pattern = "[.]R$", full.names = TRUE)
  production <- paste(vapply(r_files, function(path) paste(readLines(path, warn = FALSE), collapse = "\n"), character(1)), collapse = "\n")
  forbidden_writes <- c("INSERT\\s+INTO\\s+space_coords", "INSERT\\s+INTO\\s+space_2d",
                        "dbWriteTable\\([^\n]*space_coords", "dbWriteTable\\([^\n]*space_2d")
  stopifnot(!any(vapply(forbidden_writes, grepl, logical(1), x = production,
                        ignore.case = TRUE, perl = TRUE)))
  invisible(TRUE)
}
