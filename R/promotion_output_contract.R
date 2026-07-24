.wb_validate_promotion_output_contract <- function() {
  for (op in names(.wb_op_catalog())) {
    x <- wb_op_interface(op)$produces; terminals <- names(Filter(function(z) isTRUE(z$promotable_directly), x))
    for (nm in names(x)) {
      z <- x[[nm]]; .wb_assert(nzchar(z$output_name) && nzchar(z$primitive_kind), paste0(op, ": invalid output ", nm))
      .wb_assert(z$durability_role %in% c("terminal_artifact","materialization"), paste0(op, ": invalid durability role"))
      .wb_assert(identical(isTRUE(z$promotable_directly), nm %in% terminals), paste0(op, ": promotability mismatch"))
      .wb_assert(length(z$materialized_by_terminals) > 0L && all(z$materialized_by_terminals %in% terminals), paste0(op, ": stranded materialization ", nm))
    }
  }; TRUE
}
