.wb_validate_promotion_output_contract <- function() {
  for (op in names(.wb_op_catalog())) {
    x <- wb_op_interface(op)$produces; declared_terminals <- as.character(.wb_get_op(op)$promotable %||% character())
    .wb_assert(all(declared_terminals %in% names(x)), paste0(op, ": declared terminal absent from outputs"))
    for (nm in names(x)) {
      z <- x[[nm]]; .wb_assert(nzchar(z$output_name) && nzchar(z$primitive_kind), paste0(op, ": invalid output ", nm))
      .wb_assert(z$durability_role %in% c("terminal_artifact","materialization"), paste0(op, ": invalid durability role"))
      .wb_assert(identical(isTRUE(z$promotable_directly), nm %in% declared_terminals), paste0(op, ": promotability mismatch"))
      .wb_assert(identical(z$durability_role, if(nm %in% declared_terminals) "terminal_artifact" else "materialization"), paste0(op, ": durability mismatch"))
      .wb_assert(length(z$materialized_by_terminals) > 0L && all(z$materialized_by_terminals %in% declared_terminals), paste0(op, ": stranded materialization ", nm))
      if (nm %in% declared_terminals) .wb_assert(identical(as.character(z$materialized_by_terminals), nm), paste0(op, ": terminal route mismatch"))
    }
  }; TRUE
}
