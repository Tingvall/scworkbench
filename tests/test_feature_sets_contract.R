test_feature_sets_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(nrow(mats) > 0)
  mid <- as.character(mats$matrix_id[1])

  feats <- wb_feature_ids(b, matrix_id = mid)
  stopifnot(length(feats) >= 3)
  picks <- unique(as.character(feats[1:3]))

  nm <- ".__test_feature_set_contract__."
  direct <- try(wb_feature_set_replace(
    b, feature_set = nm, matrix_id = mid, feature_ids = picks
  ), silent = TRUE)
  stopifnot(inherits(direct, "try-error"))

  wb_feature_set_import_table(
    bundle = b, matrix_id = mid,
    table = data.frame(
      feature_set = nm, feature_id = picks, namespace = "user",
      organism = "human", origin = "imported",
      description = "feature set contract test", stringsAsFactors = FALSE
    ),
    created_by = "test", strict = TRUE, is_readonly = FALSE
  )

  got <- wb_feature_set_get(b, feature_set = nm, matrix_id = mid)
  stopifnot(identical(got, picks))

  tbl <- wb_feature_sets(b, matrix_id = mid)
  stopifnot(is.data.frame(tbl), nrow(tbl) >= 1)
  row <- tbl[tbl$feature_set == nm, , drop = FALSE]
  stopifnot(nrow(row) == 1)
  stopifnot(as.integer(row$n_features[1]) == length(picks))
  stopifnot(identical(as.character(row$namespace[1]), "user"))
  stopifnot(identical(as.character(row$organism[1]), "human"))
  stopifnot(identical(as.character(row$origin[1]), "imported"))

  info <- wb_feature_set_info(b, feature_set = nm, matrix_id = mid)
  stopifnot(nrow(info) == 1)
  stopifnot(identical(as.character(info$feature_set[1]), nm))

  # strict=FALSE should silently drop unknown features
  wb_feature_set_import_table(
    bundle = b, matrix_id = mid,
    table = data.frame(
      feature_set = nm, feature_id = c(picks[1], ".__missing_feature__."),
      description = "non-strict drop unknown", stringsAsFactors = FALSE
    ),
    created_by = "test", strict = FALSE, is_readonly = FALSE
  )
  got2 <- wb_feature_set_get(b, feature_set = nm, matrix_id = mid)
  stopifnot(identical(got2, picks[1]))

  # import table (long format)
  nm2 <- ".__test_feature_set_import__."
  imp <- data.frame(
    feature_set = c(nm2, nm2),
    feature_id = picks[1:2],
    namespace = "go_bp",
    organism = "human",
    source_id = "GO:12345",
    source_version = "vtest",
    origin = "imported",
    stringsAsFactors = FALSE
  )
  imp_out <- wb_feature_set_import_table(
    bundle = b,
    matrix_id = mid,
    table = imp,
    created_by = "test",
    strict = TRUE
  )
  stopifnot(is.data.frame(imp_out), nrow(imp_out) >= 1)
  got_imp <- wb_feature_set_get(b, feature_set = nm2, matrix_id = mid)
  stopifnot(identical(got_imp, picks[1:2]))
  info_imp <- wb_feature_set_info(b, feature_set = nm2, matrix_id = mid)
  stopifnot(nrow(info_imp) == 1)
  stopifnot(identical(as.character(info_imp$namespace[1]), "go_bp"))
  stopifnot(identical(as.character(info_imp$origin[1]), "imported"))

  # import named list (single namespace for all sets)
  nm3 <- ".__test_feature_set_list_a__."
  nm4 <- ".__test_feature_set_list_b__."
  imp_list <- list()
  imp_list[[nm3]] <- picks[1:2]
  imp_list[[nm4]] <- picks[2:3]
  imp_out2 <- wb_feature_set_import_list(
    bundle = b,
    matrix_id = mid,
    sets = imp_list,
    namespace = "msigdb_h",
    organism = "human",
    source_version = "vtest2",
    created_by = "test",
    strict = TRUE,
    origin = "imported",
    is_readonly = TRUE
  )
  stopifnot(is.data.frame(imp_out2), nrow(imp_out2) >= 2)
  info3 <- wb_feature_set_info(b, feature_set = nm3, matrix_id = mid)
  stopifnot(nrow(info3) == 1)
  stopifnot(identical(as.character(info3$namespace[1]), "msigdb_h"))
  stopifnot(identical(as.character(info3$source_id[1]), nm3))
  stopifnot(identical(as.integer(info3$is_readonly[1]), 1L))

  err <- try(
    wb_feature_set_import_table(
      bundle = b, matrix_id = mid,
      table = data.frame(
        feature_set = nm, feature_id = c(picks[1], ".__missing_feature__."),
        stringsAsFactors = FALSE
      ), strict = TRUE, is_readonly = FALSE
    ),
    silent = TRUE
  )
  stopifnot(inherits(err, "try-error"))

  delete_err <- try(wb_feature_set_delete(b, feature_set = nm, matrix_id = mid), silent = TRUE)
  stopifnot(inherits(delete_err, "try-error"))

  TRUE
}
