test_legacy_cell_vector_contract <- function() {
  d <- tempfile("scwb_legacy_vector_")
  b <- wb_init_bundle(d, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(d, recursive = TRUE, force = TRUE) }, add = TRUE)
  wb_define_cells(b, c("c1", "c2", "c3"))

  first <- wb_attach_cell_vector(b, "smoke", c(c1 = 1, c2 = 2))
  stopifnot(identical(first$vector_id, "smoke"), identical(first$n, 2L))
  got <- wb_read_cell_vector(b, "smoke", c("c2", "c1", "c3"))
  stopifnot(isTRUE(all.equal(unname(got), c(2, 1, NA_real_))))

  wb_attach_cell_vector(b, "smoke", c(c1 = 5), overwrite = FALSE)
  got_update <- wb_read_cell_vector(b, "smoke", c("c1", "c2"))
  stopifnot(isTRUE(all.equal(unname(got_update), c(5, 2))))

  wb_attach_cell_vector(b, "smoke", data.frame(cell_id = "c3", value = 9), overwrite = TRUE)
  got_replace <- wb_read_cell_vector(b, "smoke", c("c1", "c2", "c3"))
  stopifnot(isTRUE(all.equal(unname(got_replace), c(NA_real_, NA_real_, 9))))
  reg <- DBI::dbGetQuery(b$con, "SELECT value_type FROM cell_vectors WHERE vector_id = ?;", params = list("smoke"))
  stopifnot(nrow(reg) == 1L, identical(as.character(reg$value_type), "numeric"))
  TRUE
}
