#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root in an R environment provisioned with every
# declared Suggests. This prevents a forced-Suggests substitute from being
# reported as a release check.
export R_LIBS="$(Rscript -e 'cat(paste(.libPaths(), collapse = .Platform$path.sep))')"
Rscript inst/ci/check_declared_suggests.R --description DESCRIPTION
Rscript -e 'stopifnot(as.character(packageVersion("roxygen2")) == "7.3.3"); devtools::document(roclets = c("rd", "namespace"), quiet = TRUE)'
Rscript inst/tests/run_contract_tests.R
R CMD build .
R CMD check --no-manual scworkbench_0.1.0.tar.gz
status="$(grep '^Status:' scworkbench.Rcheck/00check.log | tail -n 1)"
if [[ "${status}" != "Status: OK" ]]; then
  echo "Release package check did not end in Status: OK: ${status:-<missing>}" >&2
  exit 1
fi
