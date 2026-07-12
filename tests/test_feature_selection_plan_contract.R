test_feature_selection_plan_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) > 0)
  mid <- as.character(mats$matrix_id[1])

  allf <- as.character(wb_feature_ids(b, mid))
  if (length(allf) <= 10L) {
    mid <- "feature_selection_plan_contract_counts"
    allf <- paste0("feature_plan_gene_", seq_len(12L))
    if (!mid %in% as.character(wb_matrices(b)$matrix_id)) {
      cells <- wb_cells(b, cell_set = "all")
      mat <- Matrix::Matrix(
        matrix(seq_len(length(allf) * length(cells)) %% 5L,
               nrow = length(allf), dimnames = list(allf, cells)),
        sparse = TRUE
      )
      wb_attach_matrix(b, matrix_id = mid, mat = mat, layer = "counts",
                       feature_type = "gene", source = "test_feature_selection_plan_contract",
                       created_by = "test")
    }
    allf <- as.character(wb_feature_ids(b, mid))
  }
  stopifnot(length(allf) > 10L)

  # basic universe
  p0 <- list(universe = mid, rules = list())
  s0 <- wb_exec_feature_selection_plan(b, p0)
  stopifnot(identical(s0, allf))

  # feature set include + NOT
  fs_name <- "test_feature_plan_fs"
  fs_ids <- allf[seq_len(min(10L, length(allf)))]
  wb_feature_set_replace(b, feature_set = fs_name, matrix_id = mid, feature_ids = fs_ids,
                         created_by = "test", description = "test feature plan")

  p_set <- list(universe = mid, rules = list(list(type = "feature_set", sets = fs_name)))
  s_set <- wb_exec_feature_selection_plan(b, p_set)
  stopifnot(identical(s_set, fs_ids))

  p_not <- list(universe = mid, rules = list(list(type = "feature_set", sets = fs_name, negate = TRUE)))
  s_not <- wb_exec_feature_selection_plan(b, p_not)
  stopifnot(identical(s_not, setdiff(allf, fs_ids)))

  # name_match (regex)
  q <- substr(allf[1], 1, min(3, nchar(allf[1])))
  p_nm <- list(universe = mid, rules = list(list(type = "name_match", mode = "regex", query = q, ignore_case = TRUE)))
  s_nm <- wb_exec_feature_selection_plan(b, p_nm)
  stopifnot(length(s_nm) >= 1)
  stopifnot(all(grepl(q, s_nm, ignore.case = TRUE)))

  # expr_prevalence + variance (just ensure valid subsets)
  p_ep <- list(universe = mid, rules = list(list(type = "expr_prevalence", cells = "all", min = 0, max = 1)))
  s_ep <- wb_exec_feature_selection_plan(b, p_ep)
  stopifnot(length(s_ep) >= 1)
  stopifnot(all(s_ep %in% allf))

  p_var <- list(universe = mid, rules = list(list(type = "variance", cells = "all", top_n = 25)))
  s_var <- wb_exec_feature_selection_plan(b, p_var)
  stopifnot(length(s_var) >= 1)
  stopifnot(length(s_var) <= 25)
  stopifnot(all(s_var %in% allf))

  TRUE
}
