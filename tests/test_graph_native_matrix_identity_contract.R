test_graph_native_matrix_overlapping_fragment_getter_parity_contract <- function() {
  root <- tempfile("graph_native_overlap_")
  bundle <- wb_init_bundle(root)
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("c2", "c1"); features <- c("g2", "g1")
  wb_define_cells(bundle, cells)
  original <- Matrix::Matrix(matrix(1:4, 2L, dimnames = list(features, cells)), sparse = TRUE)
  wb_attach_matrix(bundle, "native", original)
  # Existing durable bundles may contain overlaps even though current
  # registration rejects creating them. Use an explicit legacy fixture.
  fragment <- wb_matrix_fragments(bundle, "native")
  DBI::dbExecute(bundle$con, "UPDATE matrix_fragments SET created_at='2000-01-01' WHERE matrix_id='native';")
  newer <- fragment
  newer$fragment_id <- "legacy_newer"
  newer$path <- "matrices/legacy_newer"
  newer$created_at <- "2000-01-02"
  BPCells::write_matrix_dir(Matrix::Matrix(as.matrix(original) + 10, sparse = TRUE),
    dir = file.path(root, newer$path[[1L]]))
  DBI::dbAppendTable(bundle$con, "matrix_fragments", newer)
  for (kind in c("feature", "cell")) {
    membership <- paste0("matrix_fragment_", kind, "s")
    rows <- DBI::dbGetQuery(bundle$con, paste0("SELECT * FROM ", membership,
      " WHERE fragment_id=?;"), params = list(fragment$fragment_id[[1L]]))
    rows$fragment_id <- newer$fragment_id[[1L]]
    DBI::dbAppendTable(bundle$con, membership, rows)
  }
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(bundle, "native", policy)),
    identical(as.matrix(wb_matrix_read_features(bundle, "native", features, cells)),
      as.matrix(original + 10)),
    identical(as.matrix(wb_matrix_read_features(bundle, "native", features, cells, prefer_newest = FALSE)),
      as.matrix(original)))
  fields <- c("matrix_id", "storage", "n_features", "n_cells", "feature_ids_json", "cell_ids_json",
    "source", "description")
  fragments <- wb_matrix_fragments(bundle, "native")
  rows <- lapply(seq_len(nrow(fragments)), function(i) list(
    fragment = as.list(fragments[i, fields, drop = FALSE]),
    payload_sha256 = scworkbench:::.wb_prov_file_tree_sha256(file.path(root, fragments$path[[i]]))))
  expected <- list(scheme = "scworkbench.content.matrix.fragment-tree.v2", sha256 =
    scworkbench:::.wb_prov_sha256_object(list(kind = "matrix", matrix_id = "native", fragments = rows)))
  stopifnot(identical(expected, scworkbench:::.wb_graph_native_matrix_identity(bundle, "native", policy)))
  TRUE
}

test_graph_native_matrix_incremental_text_and_axis_contract <- function() {
  root <- tempfile("graph_native_byte_reader_"); dir.create(root)
  path <- file.path(root, "source.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(root, recursive = TRUE)}, add = TRUE)
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "CREATE TABLE matrix_fragments(cell_ids_json TEXT,source TEXT);")
  budgets <- scworkbench:::.wb_graph_budgets(list(partition_bytes = 128L))
  values <- c("", "a東京😀é", paste0("a", strrep("東京😀\\\n\t\001é", 800L)))
  for (value in c(values, NA_character_)) {
    DBI::dbExecute(con, "DELETE FROM matrix_fragments;")
    DBI::dbExecute(con, "INSERT INTO matrix_fragments VALUES(?,NULL);", params = list(value))
    before <- digest::digest(file = path, algo = "sha256", serialize = FALSE)
    observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
    tokens <- character()
    scworkbench:::.wb_graph_native_text(con, 1L, "cell_ids_json",
      function(token) tokens <<- c(tokens, token), budgets, observer)
    observer$finish(); observer$close()
    stopifnot(identical(paste0(tokens, collapse = ""),
      as.character(enc2utf8(jsonlite::serializeJSON(value, digits = NA)))),
      identical(before, digest::digest(file = path, algo = "sha256", serialize = FALSE)))
  }
  arrays <- c(' [ "cell_2", "東京😀", "quote\\\"name", "\\u0061", "\\ud83d\\ude00" ] ', "[]")
  for (array in arrays) {
    DBI::dbExecute(con, "UPDATE matrix_fragments SET cell_ids_json=?;", params = list(array))
    observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
    reader <- scworkbench:::.wb_matrix_native_axis_reader(con, 1L, "cell_ids_json", budgets, observer)
    actual <- character()
    repeat {value <- reader$next_id(); if (is.null(value)) break; actual <- c(actual, value)}
    observer$finish(); observer$close()
    stopifnot(identical(actual, as.character(unlist(jsonlite::fromJSON(array, simplifyVector = FALSE)))))
  }
  for (array in c('["a",]', '["a"] garbage', '[1]', '["unterminated', '["\\ud800"]',
    paste0('["', strrep("x", 1541L), '"]'))) {
    DBI::dbExecute(con, "UPDATE matrix_fragments SET cell_ids_json=?;", params = list(array))
    observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
    error <- tryCatch({reader <- scworkbench:::.wb_matrix_native_axis_reader(con,
      1L, "cell_ids_json", budgets, observer); repeat {if (is.null(reader$next_id())) break}; NULL}, error = identity)
    observer$close()
    if (!inherits(error, "wb_graph_error")) cat("NATIVE_AXIS_NEGATIVE_UNEXPECTED", array,
      paste(class(error), collapse = ","), "\n")
    stopifnot(inherits(error, "wb_graph_error"))
  }
  DBI::dbExecute(con, "UPDATE matrix_fragments SET cell_ids_json='[\"old\"]';")
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  observer$column(1L, "cell_ids_json")
  DBI::dbExecute(con, "UPDATE matrix_fragments SET cell_ids_json='[\"new\"]';")
  error <- tryCatch(observer$finish(), error = identity)
  observer$close()
  stopifnot(inherits(error, "wb_graph_error"), grepl("source changed", conditionMessage(error), fixed = TRUE))
  TRUE
}

test_graph_native_matrix_physical_and_membership_verification_contract <- function() {
  root <- tempfile("graph_native_physical_")
  bundle <- wb_init_bundle(root)
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1"); features <- c("gene_2", "gene_1")
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "native", Matrix::Matrix(matrix(1:6, 2L,
    dimnames = list(features, cells)), sparse = TRUE))
  budgets <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(bundle, "native", budgets)))
  anchor <- DBI::dbGetQuery(bundle$con, paste0("SELECT o.snapshot_id ",
    scworkbench:::.wb_graph_matrix_producer_query()), params = list("native"))
  stopifnot(nrow(anchor) == 1L)
  producer <- scworkbench:::.wb_graph_matrix_producer(bundle, "native", anchor$snapshot_id[[1L]], budgets)
  payload <- scworkbench:::.wb_graph_native_matrix_identity(bundle, "native", budgets)
  stopifnot(identical(producer[c("scheme", "sha256")], payload))
  fragment <- wb_matrix_fragments(bundle, "native")
  payload <- file.path(root, fragment$path[[1L]])
  names_path <- file.path(payload, "row_names")
  original <- readBin(names_path, "raw", n = file.info(names_path)$size)
  writeBin(raw(), names_path)
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(bundle, "native", budgets)))
  writeBin(charToRaw("foreign\ngene_1\n"), names_path)
  error <- tryCatch(scworkbench:::.wb_matrix_bounded_source_verify(bundle, "native", budgets), error = identity)
  stopifnot(inherits(error, "wb_graph_error"), grepl("Present BPCells names", conditionMessage(error), fixed = TRUE))
  writeBin(original, names_path)
  DBI::dbExecute(bundle$con, "UPDATE matrix_fragments SET feature_ids_json='[\"gene_1\",\"gene_2\"]' WHERE matrix_id='native';")
  error <- tryCatch(scworkbench:::.wb_matrix_bounded_source_verify(bundle, "native", budgets), error = identity)
  stopifnot(inherits(error, "wb_graph_error"))
  DBI::dbExecute(bundle$con, "UPDATE matrix_fragments SET feature_ids_json='[\"gene_2\",\"gene_2\"]' WHERE matrix_id='native';")
  writeBin(raw(), names_path)
  error <- tryCatch(scworkbench:::.wb_matrix_bounded_source_verify(bundle, "native", budgets), error = identity)
  stopifnot(inherits(error, "wb_graph_error"), grepl("Duplicate/reordered", conditionMessage(error), fixed = TRUE))
  TRUE
}

test_graph_native_matrix_tree_identity_contract <- function() {
  root <- tempfile("graph_native_matrix_tree_")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  payload <- file.path(root, "payload")
  dir.create(payload)
  dir.create(file.path(payload, "empty"))
  dir.create(file.path(payload, "sub"))
  names <- c("z", "A", "a", "é", "e\u0301", 'quote"name', "line\nbreak")
  for (i in seq_along(names)) writeBin(charToRaw(paste0("value", i)), file.path(payload, names[[i]]))
  writeBin(as.raw(1:20), file.path(payload, "sub", "x"))
  stopifnot(file.symlink(file.path(payload, "sub"), file.path(payload, "loop")),
    file.symlink(file.path(payload, "A"), file.path(payload, "internal_leaf")))
  budgets <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  original_locale <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", original_locale), add = TRUE)
  bundle <- structure(list(dir = root), class = "scworkbench_bundle")
  for (locale in unique(c("C", "C.UTF-8", original_locale))) {
    if (!nzchar(suppressWarnings(Sys.setlocale("LC_COLLATE", locale)))) next
    expected <- sort(as.character(fs::dir_ls(payload, recurse = TRUE, type = "any",
      all = TRUE, follow = FALSE)))
    actual <- scworkbench:::.wb_graph_native_tree_entries(payload, budgets)
    if (!identical(actual, expected)) {
      cat("NATIVE_TREE_ORDER_MISMATCH", locale, "\n")
      print(data.frame(actual = c(actual, rep(NA_character_, max(0L, length(expected) - length(actual)))),
        expected = c(expected, rep(NA_character_, max(0L, length(actual) - length(expected))))))
    }
    stopifnot(identical(actual, expected), identical(
      scworkbench:::.wb_graph_native_tree_hash(bundle, "payload", budgets),
      scworkbench:::.wb_prov_file_tree_sha256(payload)))
    cat("GRAPH_NATIVE_TREE_PARITY", locale, length(actual), "entries\n")
  }
  # No enumeration is accepted merely because a whole directory was allocated
  # and inspected afterwards. Charge is enforced in native readdir before growth.
  native <- get("C_scwb_graph_source_directory", asNamespace("scworkbench"))
  rejected <- tryCatch(.Call(native, payload, 100), error = identity)
  stopifnot(inherits(rejected, "error"),
    startsWith(conditionMessage(rejected), "GRAPH_RESOURCE_EXCEEDED:"))
  fd_count <- function() length(list.files("/proc/self/fd"))
  before <- fd_count()
  for (i in seq_len(30L)) try(.Call(native, payload, 100), silent = TRUE)
  stopifnot(fd_count() == before,
    identical(scworkbench:::.wb_graph_native_tree_entries(payload, budgets),
      sort(as.character(fs::dir_ls(payload, recurse = TRUE, type = "any", all = TRUE, follow = FALSE)))))
  writeBin(as.raw(21), file.path(payload, "sub", "x"))
  mutated <- scworkbench:::.wb_graph_native_tree_hash(bundle, "payload", budgets)
  stopifnot(identical(mutated, scworkbench:::.wb_prov_file_tree_sha256(payload)))
  outside <- file.path(root, "outside")
  writeBin(as.raw(1), outside)
  stopifnot(file.symlink(outside, file.path(payload, "escape")))
  escaped <- tryCatch(scworkbench:::.wb_graph_native_tree_hash(bundle, "payload", budgets), error = identity)
  stopifnot(inherits(escaped, "wb_graph_error"),
    grepl("unauthorized escaped entry", conditionMessage(escaped), fixed = TRUE))
  TRUE
}

test_graph_native_matrix_streaming_text_identity_contract <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE matrix_fragments (cell_ids_json TEXT);")
  budgets <- scworkbench:::.wb_graph_budgets()
  values <- list(NA_character_, "", ' [ "cell_2", "cell_10" ] ',
    paste(rep(c("東京", "\001", "\n", "\t", '"', "\\", "é", "e\u0301"), 4000L), collapse = ""))
  for (value in values) {
    DBI::dbExecute(con, "DELETE FROM matrix_fragments;")
    DBI::dbExecute(con, "INSERT INTO matrix_fragments VALUES(?);", params = list(value))
    tokens <- character()
    scworkbench:::.wb_graph_native_text(con, 1L, "cell_ids_json",
      function(token) tokens <<- c(tokens, token), budgets)
    # Whole-string assembly is only the independent, small test oracle.
    if (!identical(paste0(tokens, collapse = ""), as.character(enc2utf8(jsonlite::serializeJSON(value, digits = NA))))) {
      actual <- charToRaw(paste0(tokens, collapse = ""))
      expected <- charToRaw(enc2utf8(jsonlite::serializeJSON(value, digits = NA)))
      different <- which(actual[seq_len(min(length(actual), length(expected)))] !=
        expected[seq_len(min(length(actual), length(expected)))])
      cat("NATIVE_TEXT_MISMATCH", "value_length", nchar(value), "actual", length(actual),
        "expected", length(expected), "first_difference", head(different, 1L), "\n")
      print(head(tokens, 2L))
    }
    stopifnot(identical(paste0(tokens, collapse = ""),
      as.character(enc2utf8(jsonlite::serializeJSON(value, digits = NA)))))
  }
  TRUE
}

test_graph_native_matrix_fragment_identity_contract <- function() {
  root <- tempfile("graph_native_matrix_fragments_")
  dir.create(root)
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit({DBI::dbDisconnect(con); unlink(root, recursive = TRUE)}, add = TRUE)
  bundle <- structure(list(dir = root, con = con), class = "scworkbench_bundle")
  DBI::dbExecute(con, paste0("CREATE TABLE matrix_fragments (fragment_id TEXT, matrix_id TEXT, ",
    "storage TEXT,path TEXT,n_features INTEGER,n_cells INTEGER,feature_ids_json TEXT,",
    "cell_ids_json TEXT,source TEXT,created_at TEXT,description TEXT);"))
  fields <- c("matrix_id", "storage", "n_features", "n_cells", "feature_ids_json",
    "cell_ids_json", "source", "description")
  for (i in seq_len(3L)) {
    dir.create(file.path(root, paste0("fragment", i)))
    writeBin(charToRaw(paste0("payload", i)), file.path(root, paste0("fragment", i), "data"))
    DBI::dbExecute(con, "INSERT INTO matrix_fragments VALUES(?,?,?,?,?,?,?,?,?,?,?);", params = list(
      paste0("f", i), "matrix_a", "bpcells_dir", paste0("fragment", i), 1L, i,
      ' [ "gene_2" ] ', paste(rep(' [ "cell_2", "cell_10" ] ', 1000L), collapse = ""),
      if (i == 1L) NA_character_ else if (i == 2L) "" else "東京\n", "same_created_at", "description"))
  }
  oracle <- function() {
    fragments <- wb_matrix_fragments(bundle, "matrix_a")
    rows <- lapply(seq_len(nrow(fragments)), function(i) list(
      fragment = as.list(fragments[i, fields, drop = FALSE]),
      payload_sha256 = scworkbench:::.wb_prov_file_tree_sha256(file.path(root, fragments$path[[i]]))))
    list(scheme = "scworkbench.content.matrix.fragment-tree.v2", sha256 =
      scworkbench:::.wb_prov_sha256_object(list(kind = "matrix", matrix_id = "matrix_a", fragments = rows)))
  }
  first <- scworkbench:::.wb_graph_native_matrix_identity(bundle, "matrix_a")
  stopifnot(identical(first, oracle()))
  for (late in list(bit64::as.integer64("2147483648"), 2.5, NA_integer_)) {
    DBI::dbExecute(con, "UPDATE matrix_fragments SET n_cells=? WHERE fragment_id='f3';", params = list(late))
    stopifnot(identical(scworkbench:::.wb_graph_native_matrix_identity(bundle, "matrix_a"), oracle()))
  }
  DBI::dbExecute(con, "UPDATE matrix_fragments SET n_cells=2147483648 WHERE fragment_id='f2';")
  DBI::dbExecute(con, "UPDATE matrix_fragments SET n_cells=2.5 WHERE fragment_id='f3';")
  mixed <- tryCatch(scworkbench:::.wb_graph_native_matrix_identity(bundle, "matrix_a"), error = identity)
  stopifnot(inherits(mixed, "wb_graph_error"),
    grepl("order-dependent native RSQLite coercion", conditionMessage(mixed), fixed = TRUE))
  DBI::dbExecute(con, "UPDATE matrix_fragments SET n_cells=1;")
  DBI::dbExecute(con, "UPDATE matrix_fragments SET created_at=? WHERE fragment_id='f3';",
    params = list(strrep("x", 262145L)))
  oversized_key <- tryCatch(scworkbench:::.wb_graph_native_matrix_identity(bundle, "matrix_a"), error = identity)
  stopifnot(inherits(oversized_key, "wb_graph_error"),
    grepl("sort key exceeds admission", conditionMessage(oversized_key), fixed = TRUE))
  DBI::dbExecute(con, "UPDATE matrix_fragments SET created_at='same_created_at';")
  before <- scworkbench:::.wb_graph_native_matrix_identity(bundle, "matrix_a")
  writeBin(charToRaw("changed"), file.path(root, "fragment1", "data"))
  after <- scworkbench:::.wb_graph_native_matrix_identity(bundle, "matrix_a")
  stopifnot(!identical(before, after), identical(after, oracle()))
  TRUE
}

test_graph_source_connection_budget_purity_contract <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  budgets <- scworkbench:::.wb_graph_budgets()
  state <- function() c(temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
    cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]])
  initial <- state()
  DBI::dbExecute(con, "CREATE TEMP TABLE sentinel(x INTEGER);")
  DBI::dbExecute(con, "INSERT INTO sentinel VALUES(7);")
  for (transaction in c(FALSE, TRUE)) {
    if (transaction) DBI::dbBegin(con)
    rejected <- tryCatch(scworkbench:::.wb_graph_scoped_connection_budget(con, budgets), error = identity)
    stopifnot(inherits(rejected, "wb_graph_error"), identical(state(), initial),
      identical(DBI::dbGetQuery(con, "SELECT x FROM sentinel;")$x, 7L))
    if (transaction) DBI::dbRollback(con)
  }
  DBI::dbExecute(con, "DROP TABLE sentinel;")
  restore <- scworkbench:::.wb_graph_scoped_connection_budget(con, budgets)
  stopifnot(identical(unname(state()), c(1L, -8192L)))
  DBI::dbExecute(con, "CREATE TEMP TABLE sentinel(x INTEGER);")
  DBI::dbExecute(con, "INSERT INTO sentinel VALUES(9);")
  DBI::dbBegin(con)
  inner_restore <- scworkbench:::.wb_graph_scoped_connection_budget(con, budgets)
  inner_restore()
  stopifnot(identical(DBI::dbGetQuery(con, "SELECT x FROM sentinel;")$x, 9L))
  DBI::dbRollback(con)
  before_restore <- state()
  rejected_restore <- tryCatch(restore(), error = identity)
  stopifnot(inherits(rejected_restore, "wb_graph_error"), identical(state(), before_restore),
    identical(DBI::dbGetQuery(con, "SELECT x FROM sentinel;")$x, 9L))
  # Restoration cannot drop caller TEMP data either. Dispose only this test's
  # own TEMP fixture before restoring the initial policy.
  DBI::dbExecute(con, "DROP TABLE sentinel;")
  restore()
  stopifnot(identical(state(), initial))
  TRUE
}

test_graph_native_matrix_bounded_storage_axis_contract <- function() {
  root <- tempfile("graph_native_storage_axis_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  budgets <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  values <- Matrix::Matrix(matrix(c(1, 2, 3, 4, 5, 6), nrow = 2L,
    dimnames = list(c("gene_2", "gene_1"), c("cell_2", "cell_10", "cell_1"))), sparse = TRUE)
  matrices <- list(named_col = BPCells::convert_matrix_type(values, "uint32_t"),
    named_row = BPCells::t(BPCells::convert_matrix_type(values, "double")),
    unnamed = unname(values))
  read_names <- function(path) {
    reader <- scworkbench:::.wb_matrix_bounded_line_reader(path, budgets)
    on.exit(reader$close(), add = TRUE)
    values <- character()
    repeat {value <- reader$next_line(); if (is.null(value)) break; values <- c(values, value)}
    values
  }
  for (name in names(matrices)) {
    path <- file.path(root, name)
    BPCells::write_matrix_dir(matrices[[name]], path, compress = name != "named_row")
    observed <- scworkbench:::.wb_matrix_bounded_storage_header(path, budgets)
    oracle <- BPCells::open_matrix_dir(path)
    stopifnot(identical(observed$dimensions, as.numeric(dim(oracle))),
      identical(read_names(observed$feature_names), as.character(rownames(oracle) %||% character())),
      identical(read_names(observed$cell_names), as.character(colnames(oracle) %||% character())))
    cat("GRAPH_NATIVE_STORAGE_AXIS", name, observed$storage_order, observed$version, "PASS\n")
  }
  path <- file.path(root, "names.txt")
  writeBin(charToRaw("gene_2\r\ngene_1"), path)
  stopifnot(identical(read_names(path), c("gene_2", "gene_1")))
  writeBin(charToRaw(strrep("x", 262145L)), path)
  oversized <- tryCatch(read_names(path), error = identity)
  stopifnot(inherits(oversized, "wb_graph_error"),
    oversized$code == "GRAPH_RESOURCE_EXCEEDED")
  # Scientific source names are compared by the caller when present; truly
  # unnamed BPCells remains valid and its declared ordered JSON is still hashed.
  writeBin(charToRaw("foreign\n"), file.path(root, "named_col", "row_names"))
  observed <- scworkbench:::.wb_matrix_bounded_storage_header(file.path(root, "named_col"), budgets)
  stopifnot(!identical(read_names(observed$feature_names), c("gene_2", "gene_1")))
  TRUE
}
