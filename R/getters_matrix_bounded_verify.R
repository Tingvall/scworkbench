# Physical matrix authority belongs to the getter layer. Observe each original
# fragment and complete logical membership without constructing an axis vector.
.wb_matrix_axis_page_rows <- function(budgets, source_sql = "", params = list()) {
  # The native axis parser admits <=256 UTF-8 bytes per ID. Reserve copied
  # strings, list/parameter/ordinal/result carriers and SQL text BEFORE fetching
  # a page. Tiny policies retain the existing single-row carrier, not a new
  # resource rejection. Never allocate a schedule proportional to axis length.
  fixed <- 4096 + 4 * nchar(source_sql, type = "bytes") +
    sum(vapply(params, function(value) 128 +
      if (is.character(value)) 8 * sum(nchar(value, type = "bytes")) else 64,
      numeric(1)))
  as.integer(max(1, min(128L, budgets$partition_rows,
    floor((budgets$partition_bytes - fixed) / 2048),
    floor((900L - length(params)) / 2L))))
}

.wb_matrix_axis_membership_verify <- function(con, cursor, source, budgets, message) {
  page <- .wb_matrix_axis_page_rows(budgets, source$sql, source$params)
  repeat {
    # This cursor is over the exclusively owned scratch axes, populated only
    # by the admitted native parser. It cannot acquire an oversized source ID
    # between admission and fetch.
    ids <- DBI::dbFetch(cursor, page)
    if (!nrow(ids)) break
    if (page == 1L) {
      missing <- !nrow(DBI::dbGetQuery(con, paste0("SELECT 1 FROM (", source$sql,
        ") WHERE axis_id=? LIMIT 1;"), params = c(source$params, list(ids$axis_id[[1L]]))))
    } else {
      # Keep the actual source expression on the LEFT of equality. A VALUES
      # membership set/IN clause with competing affinity or collation would
      # change SQLite semantics. Explicit ordinals preserve first-missing order
      # and EXISTS avoids multiplying rows for a nonunique source selector.
      sql <- paste0("WITH requested(ordinal,axis_id) AS (VALUES ",
        paste(rep("(?,?)", nrow(ids)), collapse = ","),
        ") SELECT requested.ordinal FROM requested WHERE NOT EXISTS (SELECT 1 FROM (",
        source$sql, ") actual WHERE actual.axis_id=requested.axis_id LIMIT 1) ",
        "ORDER BY requested.ordinal LIMIT 1;")
      parameters <- vector("list", 2L * nrow(ids))
      for (i in seq_len(nrow(ids))) {
        parameters[[2L * i - 1L]] <- i
        parameters[[2L * i]] <- ids$axis_id[[i]]
      }
      missing <- nrow(DBI::dbGetQuery(con, sql,
        params = c(parameters, source$params))) > 0L
    }
    .wb_graph_require(!missing, "GRAPH_SOURCE_PAYLOAD_INVALID", message)
  }
  invisible(TRUE)
}

.wb_matrix_bounded_source_verify <- function(bundle, matrix_id, budgets) {
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore <- .wb_graph_aggregate_connection_budget(list(con), budgets)
  on.exit(restore(), add = TRUE)
  observer <- .wb_matrix_native_byte_observer(con)
  .wb_graph_require(!is.null(observer), "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
    "Native matrix source verification requires a durable SQLite byte reader.")
  on.exit(observer$close(), add = TRUE)
  path <- tempfile("scwb_graph_identity_axes_", fileext = ".sqlite")
  axes <- DBI::dbConnect(RSQLite::SQLite(), path, bigint = "character")
  on.exit({DBI::dbDisconnect(axes); unlink(path)}, add = TRUE)
  DBI::dbExecute(axes, "PRAGMA cache_size=-64;")
  DBI::dbExecute(axes, "PRAGMA temp_store=FILE;")
  DBI::dbExecute(axes, paste0("CREATE TABLE axes(kind TEXT,fragment TEXT,axis_id TEXT,ordinal INTEGER,",
    "PRIMARY KEY(kind,fragment,axis_id),UNIQUE(kind,fragment,ordinal));"))
  DBI::dbExecute(axes, "CREATE INDEX union_axis ON axes(kind,axis_id);")
  after <- NULL; fragments <- "0"
  repeat {
    # Selectors and dimensions are admitted in SQL before decoding; never fetch
    # either source axis JSON through RSQLite's ordinary whole-TEXT carrier.
    row <- DBI::dbGetQuery(con, paste0("SELECT rowid,fragment_id,path,storage,n_features,n_cells ",
      "FROM matrix_fragments WHERE matrix_id=? ", if (is.null(after)) "" else "AND rowid>? ", "AND ",
      "COALESCE(octet_length(fragment_id),0)+COALESCE(octet_length(path),0)+",
      "COALESCE(octet_length(storage),0)+512<=? ORDER BY rowid LIMIT 1;"),
      params = c(list(matrix_id), if (is.null(after)) list() else list(after), list(budgets$partition_bytes)))
    if (!nrow(row)) {
      hidden <- DBI::dbGetQuery(con,
        paste0("SELECT 1 FROM matrix_fragments WHERE matrix_id=? ",
          if (is.null(after)) "" else "AND rowid>? ", "LIMIT 1;"),
        params = c(list(matrix_id), if (is.null(after)) list() else list(after)))
      .wb_graph_require(!nrow(hidden), "GRAPH_RESOURCE_EXCEEDED", "Matrix fragment selector exceeds admission.")
      break
    }
    after <- bit64::as.integer64(row$rowid[[1L]])
    .wb_graph_require(identical(row$storage[[1L]], "bpcells"),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Native matrix storage is unsupported.")
    root <- .wb_bundle_path_require(bundle, row$path[[1L]], expected_type = "directory",
      purpose = "native matrix fragment")
    header <- .wb_matrix_bounded_storage_header(root, budgets)
    declared <- suppressWarnings(as.numeric(c(row$n_features[[1L]], row$n_cells[[1L]])))
    .wb_graph_require(length(declared) == 2L && all(is.finite(declared)) &&
      identical(header$dimensions, declared), "GRAPH_SOURCE_PAYLOAD_INVALID",
      "Declared matrix dimensions differ from physical BPCells shape.")
    for (kind in c("feature", "cell")) {
      names_path <- header[[paste0(kind, "_names")]]
      .wb_graph_require(file.exists(names_path) && !is.na(file.info(names_path)$size),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "BPCells axis names file is missing.")
      named <- file.info(names_path)$size > 0
      names_reader <- if (named) .wb_matrix_bounded_line_reader(names_path, budgets) else NULL
      read_axis <- function() {
        on.exit(if (!is.null(names_reader)) names_reader$close(), add = TRUE)
        reader <- .wb_matrix_native_axis_reader(con, after, paste0(kind, "_ids_json"), budgets, observer)
        count <- "0"; buffer <- list()
        flush <- function() {
          if (!length(buffer)) return(invisible(NULL))
          records <- data.frame(kind = kind, fragment = row$fragment_id[[1L]],
            axis_id = vapply(buffer, `[[`, character(1), "id"),
            ordinal = bit64::as.integer64(vapply(buffer, `[[`, character(1), "ordinal")))
          tryCatch(DBI::dbAppendTable(axes, "axes", records), error = function(error)
            .wb_graph_error("GRAPH_SOURCE_PAYLOAD_INVALID", "Duplicate/reordered native fragment axis."))
          buffer <<- list()
          .wb_graph_spill_admit(budgets, path)
        }
        repeat {
          id <- reader$next_id()
          if (is.null(id)) break
          if (named) .wb_graph_require(identical(names_reader$next_line(), id),
            "GRAPH_SOURCE_PAYLOAD_INVALID", "Present BPCells names disagree with declared ordered axis.")
          buffer[[length(buffer) + 1L]] <- list(id = id, ordinal = count)
          count <- .wb_graph_add_count(count, 1L)
          if (length(buffer) >= min(budgets$partition_rows,
            max(1L, floor(budgets$partition_bytes / 2048)))) flush()
        }
        flush()
        .wb_graph_require(count == as.character(declared[[if (kind == "feature") 1L else 2L]]) &&
          (!named || is.null(names_reader$next_line())), "GRAPH_SOURCE_PAYLOAD_INVALID",
          "Matrix axis count differs from declared shape or present names.")
        membership <- paste0("matrix_fragment_", if (kind == "feature") "features" else "cells")
        n <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", membership,
          " WHERE fragment_id=?;"), params = list(row$fragment_id[[1L]]))$n[[1L]]
        .wb_graph_require(as.character(n) == count, "GRAPH_SOURCE_PAYLOAD_INVALID",
          "Native fragment membership count differs from declared axis.")
        cursor <- DBI::dbSendQuery(axes,
          "SELECT axis_id FROM axes WHERE kind=? AND fragment=? ORDER BY ordinal;",
          params = list(kind, row$fragment_id[[1L]]))
        source <- list(sql = paste0("SELECT ", kind, "_id axis_id FROM ", membership,
          " WHERE fragment_id=?"), params = list(row$fragment_id[[1L]]))
        tryCatch(.wb_matrix_axis_membership_verify(con, cursor, source, budgets,
          "Declared axis differs from actual fragment membership."),
          finally = DBI::dbClearResult(cursor))
      }
      read_axis()
    }
    fragments <- .wb_graph_add_count(fragments, 1L)
  }
  .wb_graph_require(fragments != "0", "GRAPH_SOURCE_UNAVAILABLE", "Matrix source has no native fragments.")
  matrix <- DBI::dbGetQuery(con, "SELECT n_features,n_cells FROM matrices WHERE matrix_id=?;",
    params = list(matrix_id))
  .wb_graph_require(nrow(matrix) == 1L && is.numeric(matrix$n_features) && is.numeric(matrix$n_cells),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "Logical matrix dimensions are absent or not numeric.")
  for (kind in c("feature", "cell")) {
    # Existing getters resolve overlapping cell fragments with prefer_newest.
    # Authenticate every fragment and the complete logical union; graph source
    # verification must not impose a new disjoint-fragment validity rule.
    query <- .wb_graph_source_axis_query(bundle, list(kind = "matrix", source_id = matrix_id), kind)
    n <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM (", query$sql, ");"),
      params = query$params)$n[[1L]]
    native_n <- DBI::dbGetQuery(axes,
      "SELECT COUNT(DISTINCT axis_id) n FROM axes WHERE kind=?;", params = list(kind))$n[[1L]]
    .wb_graph_require(as.character(n) == as.character(native_n),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Logical matrix axis count differs from native fragment union.")
    .wb_graph_require(as.character(native_n) == as.character(matrix[[paste0("n_", if (kind == "feature") "features" else "cells")]][[1L]]),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Logical matrix dimensions differ from complete native axes.")
    cursor <- DBI::dbSendQuery(axes, "SELECT DISTINCT axis_id FROM axes WHERE kind=? ORDER BY axis_id;",
      params = list(kind))
    tryCatch(.wb_matrix_axis_membership_verify(con, cursor, query, budgets,
      "Logical matrix membership differs from native fragment union."),
      finally = DBI::dbClearResult(cursor))
    .wb_graph_spill_admit(budgets, path)
  }
  observer$finish()
  invisible(TRUE)
}
