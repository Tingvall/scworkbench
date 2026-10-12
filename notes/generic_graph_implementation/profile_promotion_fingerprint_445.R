# Focused allocation diagnostic; not lifecycle or qualification evidence.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
lib <- "/tmp/scwb-graph-forge-duplicate-sensitive-444.ps0av2oi/library"
.libPaths(c(lib, .libPaths()))
library(scworkbench, lib.loc = lib)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(lib, "scworkbench"))),
  identical(digest::digest(file=getLoadedDLLs()[["scworkbench"]][["path"]],
    algo="sha256"), "ead7462807fb7920e924aa8995ec3ddb26ecbf87dd2c2d4b6ccf21f3b7a1bd56"))
reference <- new.env(parent=baseenv())
sys.source("R/promotion_transitive.R", envir=reference)
fn <- getFromNamespace(".wb_promotion_runtime_fingerprint", "scworkbench")
stopifnot(identical(body(fn), body(reference$.wb_promotion_runtime_fingerprint)),
  identical(formals(fn), formals(reference$.wb_promotion_runtime_fingerprint)))
status <- function() readLines("/proc/self/status")
before <- status()
namespaces_before <- loadedNamespaces()
profile <- paste0(args[[1L]], ".allocations")
stopifnot(!file.exists(profile), !file.exists(paste0(args[[1L]], ".rds")))
Rprofmem(profile, threshold=1048576)
value <- fn()
Rprofmem(NULL)
after <- status()
namespaces_after <- loadedNamespaces()
saveRDS(list(value=value, before=before, after=after,
  namespaces_before=namespaces_before, namespaces_after=namespaces_after,
  function_sha256=digest::digest(paste(deparse(body(fn)), collapse="\n"),
    algo="sha256", serialize=FALSE), qualification=FALSE), paste0(args[[1L]], ".rds"))
cat("FINGERPRINT_ONLY_BEFORE", paste(before[grepl("^(VmRSS|VmHWM):", before)], collapse=" "), "\n")
cat("FINGERPRINT_ONLY_AFTER", paste(after[grepl("^(VmRSS|VmHWM):", after)], collapse=" "), "\n")
cat("FINGERPRINT_ONLY_NEW_NAMESPACES", paste(setdiff(namespaces_after,
  namespaces_before), collapse=","), "\n")
print(value)
