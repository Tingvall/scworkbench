#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root in an R environment provisioned with every
# declared Suggests. The fullstack Apptainer definition installs the required
# Bioconductor genome package; this guard prevents a forced-Suggests substitute
# from being reported as a release check.
Rscript -e 'stopifnot(requireNamespace("BSgenome.Hsapiens.UCSC.hg19", quietly = TRUE))'
Rscript -e 'stopifnot(as.character(packageVersion("roxygen2")) == "7.3.3"); devtools::document(roclets = c("rd", "namespace"), quiet = TRUE)'
Rscript inst/tests/run_contract_tests.R
R CMD build .
R CMD check --no-manual scworkbench_0.1.0.tar.gz
