test_session_input_ref_ergonomics_contract <- function() {
  s <- wb_session_new()

  ft <- wb_prim_feature_table(
    table = data.frame(feature_id = "g1", score = 1, stringsAsFactors = FALSE),
    table_type = "dummy"
  )

  r <- wb_new_run(
    op_name = "dummy_source",
    inputs = list(
      cell_set = "all",
      effective_n = 1L,
      parents = character(0),
      provenance_refs = list(),
      user_inputs = list()
    ),
    params = list(),
    outputs = list(feature_table = ft),
    notes = "source run for resolver ergonomics test"
  )

  s <- wb_session_add_run(s, r)
  ref <- wb_ref_run(r$run_id, "feature_table")

  rr_inline <- .wb_resolve_input(
    bundle = list(),
    session = s,
    name = "feature_table",
    expected_kind = "feature_table",
    inputs = list(feature_table = ref)
  )

  rr_suffix <- .wb_resolve_input(
    bundle = list(),
    session = s,
    name = "feature_table",
    expected_kind = "feature_table",
    inputs = list(feature_table_ref = ref)
  )

  stopifnot(.wb_is_primitive(rr_inline$value))
  stopifnot(.wb_is_primitive(rr_suffix$value))
  stopifnot(identical(as.character(rr_inline$value$kind), "feature_table"))
  stopifnot(identical(as.character(rr_suffix$value$kind), "feature_table"))
  stopifnot(identical(rr_inline$parents, r$run_id))
  stopifnot(identical(rr_suffix$parents, r$run_id))
  stopifnot(identical(rr_inline$prov_refs, list()))
  stopifnot(identical(rr_suffix$prov_refs, list()))
  stopifnot(identical(rr_inline$value$table, rr_suffix$value$table))

  TRUE
}
