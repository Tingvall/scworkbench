.engine_prov_file_hash_fixture <- function(bytes) {
  path <- tempfile("provenance_file_hash_")
  con <- file(path, "wb")
  tryCatch(writeBin(bytes, con), finally = close(con))
  path
}

test_engine_provenance_file_sha256_digest_parity_contract <- function() {
  payloads <- list(raw(), as.raw(0L), as.raw(c(0L, 255L, 13L, 10L, 128L)),
    charToRaw(enc2utf8("identity_雪_é\n")))
  for (n in c(65535L, 65536L, 65537L, 131073L, 16777216L))
    payloads[[length(payloads) + 1L]] <- rep(as.raw(0:255), length.out = n)
  for (bytes in payloads) {
    path <- .engine_prov_file_hash_fixture(bytes)
    actual <- scworkbench:::.wb_prov_sha256_file(path)
    expected <- digest::digest(file = path, algo = "sha256")
    stopifnot(identical(actual, expected), is.character(actual), length(actual) == 1L,
      is.null(attributes(actual)), grepl("^[0-9a-f]{64}$", actual))
    unlink(path)
  }
  # File identity authenticates compressed carrier bytes, never an implicitly
  # decompressed stream. This must also hold for zero-byte scientific content.
  for (bytes in list(raw(), rep(as.raw(0:255), 1024L))) {
    path <- tempfile("provenance_compressed_payload_", fileext = ".gz")
    con <- gzfile(path, "wb")
    tryCatch(writeBin(bytes, con), finally = close(con))
    actual <- scworkbench:::.wb_prov_sha256_file(path)
    stopifnot(identical(actual, digest::digest(file = path, algo = "sha256")),
      !identical(actual, digest::digest(bytes, algo = "sha256", serialize = FALSE)))
    unlink(path)
  }
  TRUE
}

test_engine_provenance_file_sha256_actual_mutation_contract <- function() {
  path <- .engine_prov_file_hash_fixture(rep(as.raw(0:255), 513L))
  on.exit(unlink(path), add = TRUE)
  initial <- scworkbench:::.wb_prov_sha256_file(path)
  con <- file(path, "r+b")
  tryCatch({ seek(con, where = 65536, origin = "start"); writeBin(as.raw(99L), con) },
    finally = close(con))
  mutated <- scworkbench:::.wb_prov_sha256_file(path)
  stopifnot(!identical(initial, mutated),
    identical(mutated, digest::digest(file = path, algo = "sha256")))
  TRUE
}

test_engine_provenance_file_sha256_missing_and_directory_contract <- function() {
  missing <- tempfile("missing_provenance_payload_")
  directory <- tempfile("directory_provenance_payload_"); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  for (path in c(missing, directory)) {
    failure <- tryCatch(scworkbench:::.wb_prov_sha256_file(path), error = identity)
    stopifnot(inherits(failure, "error"),
      grepl(paste0("Missing payload file for SHA-256: ", path),
        conditionMessage(failure), fixed = TRUE))
  }
  TRUE
}

test_engine_provenance_file_sha256_stream_fault_cleanup_contract <- function() {
  path <- .engine_prov_file_hash_fixture(as.raw(0:255))
  on.exit(unlink(path), add = TRUE)
  ns <- asNamespace("openssl"); original <- get("sha256", ns)
  observed <- NULL
  replacement <- function(x, key = NULL) {
    observed <<- x
    stopifnot(inherits(x, "connection"), identical(readBin(x, "raw", n = 1L), as.raw(0L)))
    stop("PROVENANCE_STREAM_READ_FAULT")
  }
  unlockBinding("sha256", ns); assign("sha256", replacement, ns); lockBinding("sha256", ns)
  restore <- function() {
    unlockBinding("sha256", ns); assign("sha256", original, ns); lockBinding("sha256", ns)
  }
  on.exit(restore(), add = TRUE, after = FALSE)
  failure <- tryCatch(scworkbench:::.wb_prov_sha256_file(path), error = identity)
  closed <- tryCatch(!isOpen(observed), error = function(e) TRUE)
  stopifnot(inherits(failure, "error"),
    identical(conditionMessage(failure), "PROVENANCE_STREAM_READ_FAULT"), closed)
  # Restore before successful retry; the owned failed descriptor remains closed.
  restore()
  stopifnot(identical(scworkbench:::.wb_prov_sha256_file(path),
    digest::digest(file = path, algo = "sha256")))
  TRUE
}

test_engine_provenance_file_sha256_open_fault_contract <- function() {
  path <- .engine_prov_file_hash_fixture(as.raw(1L))
  on.exit(unlink(path), add = TRUE)
  # Deterministic unreadable/open-error probe even under a privileged test user.
  # Only this local function copy is altered; namespace and backend stay intact.
  probe <- scworkbench:::.wb_prov_sha256_file
  environment(probe) <- list2env(list(file = function(...) stop("PROVENANCE_OPEN_DENIED")),
    parent = environment(probe))
  before <- showConnections(all = TRUE)
  failure <- tryCatch(probe(path), error = identity)
  stopifnot(inherits(failure, "error"),
    identical(conditionMessage(failure), "PROVENANCE_OPEN_DENIED"),
    identical(before, showConnections(all = TRUE)))
  TRUE
}
