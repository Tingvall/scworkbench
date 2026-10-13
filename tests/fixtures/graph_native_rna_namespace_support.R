# Core test setup only: preserve a preexisting namespace only with exact source bytes.
graph_native_rna_fixture_source <- function() {
  root <- Sys.getenv("SCWORKBENCH_SCWBRNA_ROOT", unset = ".ci/scwbRNA")
  if (!nzchar(root) || !dir.exists(root))
    stop("Set SCWORKBENCH_SCWBRNA_ROOT to the pinned scwbRNA checkout, or run bash inst/ci/checkout_graph_rna_fixture.sh.")
  root <- normalizePath(root, mustWork = TRUE)
  head <- system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE)
  if (!is.null(attr(head, "status")) ||
      !identical(head, "151dd29211b219343dce6247c5e48fc932b4c83d"))
    stop("Graph RNA fixture requires scwbRNA commit 151dd29211b219343dce6247c5e48fc932b4c83d.")
  dirty <- system2("git", c("-C", shQuote(root), "status", "--porcelain"), stdout = TRUE)
  if (!is.null(attr(dirty, "status")) || length(dirty))
    stop("Graph RNA fixture requires a clean scwbRNA checkout.")
  root
}

graph_native_rna_fixture_library <- function(library_dir, namespaces_before) {
  if (!"scwbRNA" %in% namespaces_before) return(library_dir)
  files <- c("R/scwbRNA.rdb", "R/scwbRNA.rdx", "NAMESPACE", "scworkbench/operation-pack.json")
  hashes <- function(root) vapply(files, function(file) {
    path <- file.path(root, file)
    stopifnot(file.exists(path), !dir.exists(path))
    digest::digest(file = path, algo = "sha256", serialize = FALSE)
  }, character(1))
  installed <- normalizePath(file.path(library_dir, "scwbRNA"), mustWork = TRUE)
  existing <- normalizePath(getNamespaceInfo(asNamespace("scwbRNA"), "path"), mustWork = TRUE)
  stopifnot(identical(hashes(installed), hashes(existing)))
  dirname(existing)
}
