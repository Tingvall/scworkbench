#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: validate_monocle3_dependency_closure.R LOCK SNAPSHOT")
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]))),
                 "fullstack_r_dependency_lock.R"))
lock <- read_fullstack_r_dependency_lock(args[[1L]])
dependencies <- fullstack_validate_monocle3_closure(lock, args[[2L]])
cat("Pinned monocle3 dependency closure preflight OK: ", length(dependencies), " direct dependencies; ",
    length(fullstack_monocle3_closure_packages(lock)), " declared closure packages.\n", sep = "")
