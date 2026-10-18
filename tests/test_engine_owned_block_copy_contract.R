.wb_owned_block_test_context <- function() {
  ns <- asNamespace("scworkbench")
  helper <- get0(".wb_operation_pack_v3_deliver_owned_block",
    envir = environment(.wb_owned_block_test_context), inherits = TRUE)
  if (is.null(helper)) helper <- get(
    ".wb_operation_pack_v3_deliver_owned_block", envir = ns)
  state <- new.env(parent = ns)
  state$calls <- 0L
  state$.wb_operation_pack_v2_deep_copy <- function(value) {
    state$calls <- state$calls + 1L
    unserialize(serialize(value, NULL, version = 3L))
  }
  environment(helper) <- state
  list(deliver = helper, state = state)
}

.wb_owned_block_fixture <- function(n = 16L, kind = "matrix") {
  structure(list(kind = kind, values = matrix(as.double(seq_len(n * n)), n,
    dimnames = list(paste0("f", seq_len(n)), paste0("c", seq_len(n)))),
    cell_id = paste0("c", seq_len(n)), feature_id = paste0("f", seq_len(n)),
    dimensions = c(n, n), meta = list(label = "owned block",
      nested = list(a = 1))), class = "wb_primitive")
}

test_engine_owned_block_copy_isolation_contract <- function() {
  ctx <- .wb_owned_block_test_context()
  for (kind in c("matrix", "space")) {
    original <- .wb_owned_block_fixture(kind = kind)
    expected <- unserialize(serialize(original, NULL, version = 3L))
    first <- ctx$deliver(original)
    second <- ctx$deliver(original)
    stopifnot(identical(first, expected), identical(second, expected))
    first$values[1L, 1L] <- -1
    dimnames(first$values)[[1L]][1L] <- "changed"
    first$cell_id[1L] <- "foreign"
    first$meta$nested$a <- 999
    stopifnot(identical(original, expected), identical(second, expected),
      identical(ctx$deliver(original), expected))
    original$values[2L, 2L] <- -2
    stopifnot(identical(second, expected))
  }
  stopifnot(ctx$state$calls == 0L)
  TRUE
}

test_engine_owned_block_copy_fallback_contract <- function() {
  ctx <- .wb_owned_block_test_context()
  mutable <- new.env(parent = emptyenv()); mutable$value <- 1
  original <- .wb_owned_block_fixture()
  original$meta$nested$mutable <- mutable
  result <- ctx$deliver(original)
  stopifnot(ctx$state$calls == 1L,
    !identical(result$meta$nested$mutable, mutable))
  result$meta$nested$mutable$value <- 5
  stopifnot(mutable$value == 1)
  cases <- list(structure(list(value = 1), class = "reference_like"),
    methods::new("externalptr"), new.env(parent = emptyenv()),
    methods::getRefClass("envRefClass")$new())
  for (value in cases) {
    original <- .wb_owned_block_fixture()
    original$meta$nested$value <- value
    prior <- ctx$state$calls
    invisible(ctx$deliver(original))
    stopifnot(ctx$state$calls == prior + 1L)
  }
  # Attributes may hide mutable references just as ordinary metadata can.
  original <- .wb_owned_block_fixture()
  attr(original$values, "hidden_mutable") <- mutable
  prior <- ctx$state$calls
  result <- ctx$deliver(original)
  stopifnot(ctx$state$calls == prior + 1L,
    !identical(attr(result$values, "hidden_mutable"), mutable))
  TRUE
}

test_engine_owned_block_copy_identity_contract <- function() {
  ctx <- .wb_owned_block_test_context()
  value <- .wb_owned_block_fixture()
  identity <- scworkbench:::.wb_operation_pack_v3_matrix_slice_content
  before <- identity(value$values, value$feature_id, value$cell_id)
  delivered <- ctx$deliver(value)
  stopifnot(identical(before, identity(delivered$values,
    delivered$feature_id, delivered$cell_id)))
  # Fallback and owned paths must agree on the exact primitive representation.
  stopifnot(identical(delivered, unserialize(serialize(value, NULL,
    version = 3L))))
  TRUE
}

test_engine_owned_block_copy_resource_contract <- function() {
  ctx <- .wb_owned_block_test_context()
  for (size in c(512L, 2000L)) {
    value <- .wb_owned_block_fixture(size)
    invisible(ctx$deliver(value))
    allocation <- tempfile("owned_block_alloc_")
    on.exit(unlink(allocation), add = TRUE)
    Rprofmem(allocation)
    tryCatch(for (i in seq_len(20L)) invisible(ctx$deliver(value)),
      finally = Rprofmem(NULL))
    lines <- readLines(allocation, warn = FALSE)
    bytes <- sum(as.numeric(sub(" .*", "", lines[grepl("^[0-9]+", lines)])))
    stopifnot(bytes / 20 < 1024^2, ctx$state$calls == 0L)
  }
  TRUE
}

test_engine_owned_block_copy_typed_space_reader_contract <- function() {
  e <- environment(test_engine_owned_block_copy_typed_space_reader_contract)
  add <- get0(".wb_operation_pack_v3_add_typed_space_readers", e,
    inherits = TRUE)
  if (is.null(add)) add <- get(".wb_operation_pack_v3_add_typed_space_readers",
    asNamespace("scworkbench"))
  original <- .wb_owned_block_fixture(4L, "space")
  original$cell_id <- rownames(original$values)
  expected <- unserialize(serialize(original, NULL, version = 3L))
  id <- list(scheme = "test", sha256 = paste(rep("0", 64L), collapse = ""))
  grant <- list(name = "coordinates", requested_chunk_size = 2L,
    source_reference = list(source_reference_identity = id), grant_identity = id)
  request <- list(typed_space_grants = list(grant))
  attr(request, "operation_pack_v3_typed_space_values") <- list(
    coordinates = list(cells = original$cell_id, input = original))
  state <- new.env(parent = emptyenv())
  state$used <- FALSE; state$reader_calls <- list()
  adapter <- add(list(state = state, readers = list()), request)
  first <- adapter$readers$coordinates(original$cell_id[1:2])
  first$values[,] <- 0
  first$meta$nested$a <- -1
  second <- adapter$readers$coordinates(original$cell_id[3:4])
  stopifnot(identical(original, expected),
    identical(second$values, original$values[3:4, , drop = FALSE]),
    identical(second$meta, original$meta),
    length(state$reader_calls) == 2L)
  for (cells in list(original$cell_id[1:2], "foreign", original$cell_id)) {
    error <- tryCatch(adapter$readers$coordinates(cells), error = identity)
    stopifnot(inherits(error, "wb_operation_pack_error"))
  }
  TRUE
}
