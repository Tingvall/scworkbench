test_attach_adapters_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  all_cells <- wb_cells(b, cell_set = "all")
  if (length(all_cells) < 3) return(contract_test_skip("Fixture has fewer than three cells."))
  ids <- all_cells[1:3]

  md <- data.frame(
    any_id = ids,
    attach_test_col = c("a", "b", "c"),
    stringsAsFactors = FALSE
  )
  sp2d <- data.frame(
    id_col = ids,
    x = c(10, 11, 12),
    y = c(20, 21, 22),
    stringsAsFactors = FALSE
  )
  sphd <- data.frame(
    id_col = ids,
    PC1 = c(1, 2, 3),
    PC2 = c(4, 5, 6),
    PC3 = c(7, 8, 9),
    stringsAsFactors = FALSE
  )

  v <- wb_attach_validate(
    bundle = b,
    metadata = md,
    spaces = list(space_attach_test = sp2d),
    strict = FALSE
  )
  stopifnot(is.list(v), isTRUE(v$valid))
  stopifnot(v$n_existing >= 3)

  nrm <- wb_attach_normalize(
    bundle = b,
    metadata = md,
    spaces = list(space_attach_test = sp2d)
  )
  stopifnot(is.list(nrm))
  stopifnot(is.data.frame(nrm$metadata), "cell_id" %in% names(nrm$metadata))

  nrm_hd <- wb_attach_normalize(bundle = b, spaces = list(space_attach_hd_test = sphd))
  stopifnot(
    is.data.frame(nrm_hd$spaces$space_attach_hd_test),
    identical(names(nrm_hd$spaces$space_attach_hd_test), c("cell_id", "dim", "value")),
    identical(as.character(unique(nrm_hd$spaces$space_attach_hd_test$cell_id)), as.character(ids))
  )

  dry <- wb_attach_apply(
    bundle = b,
    metadata = md,
    spaces = list(space_attach_test = sp2d),
    validate_only = TRUE
  )
  stopifnot(is.list(dry), isTRUE(dry$validated))

  res <- wb_attach_apply(
    bundle = b,
    metadata = md,
    spaces = list(space_attach_test = sp2d),
    source = "test_attach",
    created_by = "test",
    apply_mode = "atomic",
    emit_report_artifact = TRUE
  )
  stopifnot(is.list(res))
  rep <- attr(res, "attach_report", exact = TRUE)
  stopifnot(is.list(rep), identical(as.character(rep$apply_mode), "atomic"))
  aid <- attr(res, "attach_report_artifact_id", exact = TRUE)
  if (is.null(aid)) aid <- ""
  aid <- as.character(aid)[1]
  stopifnot(nzchar(aid))
  p <- wb_art_load(b, artifact_id = aid, expected_kind = "obs_table")
  stopifnot(identical(as.character(p$table_type), "attach_report"))
  stopifnot(is.data.frame(p$table), nrow(p$table) >= 1)

  wb_attach_space(
    b,
    space_id = "space_attach_hd_test",
    coords = sphd,
    source = "test_attach",
    created_by = "test"
  )
  hd <- wb_space(b, "space_attach_hd_test", cells = ids)
  stopifnot(
    is.matrix(hd),
    identical(rownames(hd), as.character(ids)),
    identical(dim(hd), c(length(ids), 3L)),
    isTRUE(all.equal(unname(hd), unname(as.matrix(sphd[, -1, drop = FALSE]))))
  )

  TRUE
}
