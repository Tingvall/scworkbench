#'@export roxygen
wb_set_cell_set_style <- function(bundle,
                                  cell_set,
                                  shape = NULL,
                                  size = NULL,
                                  alpha = NULL,
                                  stroke = NULL,
                                  outline = NULL,
                                  fill_mode = c("auto","color","fill"),
                                  label = NULL,
                                  description = NULL,
                                  created_by = NULL) {

  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")

  # ---- scalar coercers (DBI params must be length-1) ----
  .scalar_chr <- function(x) {
    if (is.null(x) || length(x) == 0) return(NA_character_)
    x <- as.character(x)
    if (!length(x) || !nzchar(x[1])) return(NA_character_)
    x[1]
  }
  .scalar_int <- function(x) {
    if (is.null(x) || length(x) == 0) return(NA_integer_)
    as.integer(x[1])
  }
  .scalar_num <- function(x) {
    if (is.null(x) || length(x) == 0) return(NA_real_)
    as.numeric(x[1])
  }

  fill_mode <- match.arg(fill_mode)

  # ---- normalize ----
  cell_set    <- .scalar_chr(cell_set)
  label       <- .scalar_chr(label)
  outline     <- .scalar_chr(outline)
  description <- .scalar_chr(description)
  created_by  <- .scalar_chr(created_by)

  shape  <- .scalar_int(shape)
  size   <- .scalar_num(size)
  alpha  <- .scalar_num(alpha)
  stroke <- .scalar_num(stroke)

  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  con <- bundle$con
  #.wb_ensure_cell_set_styles_table(con)

  sql <- "
    INSERT INTO cell_set_styles(
      cell_set, label, shape, size, alpha, stroke, outline, fill_mode,
      created_at, created_by, description
    ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(cell_set) DO UPDATE SET
      label=excluded.label,
      shape=excluded.shape,
      size=excluded.size,
      alpha=excluded.alpha,
      stroke=excluded.stroke,
      outline=excluded.outline,
      fill_mode=excluded.fill_mode,
      created_at=excluded.created_at,
      created_by=excluded.created_by,
      description=excluded.description;
  "

  DBI::dbExecute(con, sql, params = list(
    cell_set,
    label,
    shape,
    size,
    alpha,
    stroke,
    outline,
    fill_mode,
    created_at,
    created_by,
    description
  ))

  invisible(TRUE)
}

#'@export roxygen
wb_get_cell_set_style <- function(bundle, cell_set) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")

  con <- bundle$con
  #.wb_ensure_cell_set_styles_table(con)

  df <- DBI::dbGetQuery(
    con,
    "SELECT cell_set, label, shape, size, alpha, stroke, outline, fill_mode, created_at, created_by, description
     FROM cell_set_styles
     WHERE cell_set = ?;",
    params = list(as.character(cell_set))
  )

  if (nrow(df) == 0) return(NULL)

  # Canonicalize types (so smoketests can use identical())
  df$cell_set    <- as.character(df$cell_set)
  df$label       <- as.character(df$label)
  df$outline     <- as.character(df$outline)
  df$fill_mode   <- as.character(df$fill_mode)
  df$created_at  <- as.character(df$created_at)
  df$created_by  <- as.character(df$created_by)
  df$description <- as.character(df$description)

  # Integers: DB may return numeric; force integer with NA-safe conversion
  df$shape <- ifelse(is.na(df$shape), NA_integer_, as.integer(df$shape))

  # Numerics: force double
  df$size   <- ifelse(is.na(df$size),   NA_real_, as.numeric(df$size))
  df$alpha  <- ifelse(is.na(df$alpha),  NA_real_, as.numeric(df$alpha))
  df$stroke <- ifelse(is.na(df$stroke), NA_real_, as.numeric(df$stroke))

  df[1, , drop = FALSE]
}

