# Lexical, same-promotion observations only. No workspace/session/cache slot.
.wb_promotion_table_observable <- function(prim) {
  exists("C_scwb_promotion_table_observable", inherits = TRUE) &&
    isTRUE(.Call(C_scwb_promotion_table_observable, prim))
}

.wb_promotion_table_observed_identity <- function(observed, prim) {
  if (is.null(observed) || !.wb_promotion_table_observable(prim) ||
      !identical(prim, observed$primitive, num.eq = FALSE, single.NA = FALSE,
        attrib.as.set = FALSE)) return(NULL)
  observed$identity
}
