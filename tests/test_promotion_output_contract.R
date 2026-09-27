test_promotion_output_contract <- function() {
  stopifnot(isTRUE(.wb_validate_promotion_output_contract()))
  slingshot <- wb_op_interface("slingshot_adopt")$produces
  stopifnot(length(slingshot) > 0L,
    all(vapply(slingshot, function(output)
      all(c("output_name", "primitive_kind", "durability_role",
        "promotable_directly", "materialized_by_terminals") %in%
        names(output)), logical(1))),
    !any(c("scvi_train", "model_bound_latent_union") %in% wb_list_ops()))
  zero_root <- tempfile("scwb_zero_")
  zero_bundle <- wb_init_bundle(zero_root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(zero_bundle), silent = TRUE)
    unlink(zero_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  no_outputs <- wb_new_run("slingshot_adopt",
    inputs = list(parents = character()), outputs = list())
  session <- wb_session_new()
  session$runs <- setNames(list(no_outputs), no_outputs$run_id)
  session$head_run_id <- no_outputs$run_id
  zero <- try(wb_session_promote_current(zero_bundle, session), silent = TRUE)
  stopifnot(inherits(zero, "try-error"),
    grepl("zero promotable terminal", as.character(zero)))
  terminal <- function() wb_new_run("slingshot_adopt",
    inputs = list(parents = character()), outputs = list(
      adoption_summary = wb_prim_obs_table(data.frame(x = 1),
        table_type = "slingshot_adopt_summary")))
  first <- terminal()
  second <- terminal()
  session2 <- wb_session_new()
  session2$runs <- setNames(list(first, second),
    c(first$run_id, second$run_id))
  session2$head_run_id <- second$run_id
  missing_run <- try(wb_session_promote_current(zero_bundle, session2,
    outputs = list(wb_ref_run("missing", "adoption_summary"))),
    silent = TRUE)
  stopifnot(inherits(missing_run, "try-error"),
    grepl("absent session run", as.character(missing_run)))
  missing_terminal <- try(wb_session_promote_current(zero_bundle, session2,
    outputs = list(wb_ref_run(first$run_id, "selected_features"))),
    silent = TRUE)
  stopifnot(inherits(missing_terminal, "try-error"),
    grepl("absent from run", as.character(missing_terminal)))
  TRUE
}
