# Core test setup only: preserve a preexisting namespace only with exact source bytes.
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
