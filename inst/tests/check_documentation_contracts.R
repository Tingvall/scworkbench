#!/usr/bin/env Rscript

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
source(file.path(root, "inst/dev/documentation_policy.R"))
policy <- scwb_documentation_policy(root)
manifest <- jsonlite::read_json(file.path(root, "docs/public_documentation_manifest.json"), simplifyVector = TRUE)
stopifnot(identical(sort(manifest$entries$path), sort(vapply(policy$entries, `[[`, character(1), "path"))))
status <- system2("Rscript", c("inst/dev/regenerate_public_docs.R", "--check"))
stopifnot(identical(status, 0L))
build_dir <- tempfile("scwb_source_build_")
dir.create(build_dir)
on.exit(unlink(build_dir, recursive = TRUE, force = TRUE), add = TRUE)
status <- local({
  old <- setwd(build_dir)
  on.exit(setwd(old), add = TRUE)
  system2("R", c("CMD", "build", root, "--no-build-vignettes"))
})
stopifnot(identical(status, 0L))
made <- list.files(build_dir, pattern = "^scworkbench_.*[.]tar[.]gz$", full.names = TRUE)
stopifnot(length(made) == 1L)
tarball <- made[[1L]]
listing <- system2("tar", c("-tzf", tarball), stdout = TRUE)
listing <- sub("^[^/]+/?", "", listing)
listing <- listing[nzchar(listing) & !endsWith(listing, "/")]
for (pattern in policy$forbidden_tarball_patterns) {
  stopifnot(!any(grepl(pattern, listing, perl = TRUE)))
}
entries <- manifest$entries
expected_source <- entries$path[entries$source_tarball %in% TRUE]
missing_source <- setdiff(expected_source, listing)
if (length(missing_source)) {
  stop("Manifest-declared source files missing from tarball: ",
       paste(missing_source, collapse = ", "), call. = FALSE)
}
excluded_source <- entries$path[!(entries$source_tarball %in% TRUE)]
unexpected_source <- intersect(excluded_source, listing)
if (length(unexpected_source)) {
  stop("Manifest-excluded files unexpectedly present in tarball: ",
       paste(unexpected_source, collapse = ", "), call. = FALSE)
}

unpack_dir <- tempfile("scwb_source_unpack_")
dir.create(unpack_dir)
on.exit(unlink(unpack_dir, recursive = TRUE, force = TRUE), add = TRUE)
utils::untar(tarball, exdir = unpack_dir)
package_root <- list.dirs(unpack_dir, recursive = FALSE, full.names = TRUE)
stopifnot(length(package_root) == 1L)
policy_manifests <- c("docs/public_documentation_manifest.json", "inst/documentation_manifest.json")
public_text <- setdiff(
  expected_source[grepl("([.](md|json|Rd|cff)$|(^|/)LICENSE([.]md)?$)", expected_source)],
  policy_manifests
)
for (path in public_text) {
  text <- paste(readLines(file.path(package_root, path), warn = FALSE), collapse = "\n")
  for (pattern in policy$forbidden_public_text_patterns) {
    if (grepl(pattern, text, perl = TRUE)) {
      stop("Forbidden public text in ", path, ": ", pattern, call. = FALSE)
    }
  }
}

library_dir <- tempfile("scwb_installed_library_"); dir.create(library_dir)
on.exit(unlink(library_dir, recursive = TRUE, force = TRUE), add = TRUE)
status <- system2("R", c("CMD", "INSTALL", "-l", library_dir, tarball))
stopifnot(identical(status, 0L))
installed_smoke <- file.path(library_dir, "scworkbench", "tests", "public_operator_smoke.R")
stopifnot(file.exists(installed_smoke))
status <- system2("Rscript", c("--vanilla", installed_smoke, "--installed"),
                  env = c(paste0("R_LIBS=", library_dir), paste0("SCWORKBENCH_EXPECTED_LIBRARY=", library_dir)))
stopifnot(identical(status, 0L))
cat("documentation source-package contract: OK\n")
