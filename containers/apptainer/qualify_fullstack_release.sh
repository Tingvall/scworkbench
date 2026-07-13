#!/usr/bin/env bash
set -euo pipefail

# Qualify a candidate image against the checked-out engine. Do not replace a
# deployed image until this non-forced package gate reports Status: OK.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMAGE_PATH="${1:?usage: qualify_fullstack_release.sh /path/to/candidate.sif [repo_root]}"
CHECKOUT="${2:-${REPO_ROOT}}"

test -f "${IMAGE_PATH}"
test -f "${CHECKOUT}/inst/ci/check_release_package.sh"

echo "==> Candidate image"
sha256sum "${IMAGE_PATH}"

echo "==> Native runtime provenance"
singularity exec --cleanenv "${IMAGE_PATH}" bash -lc '
  cat /opt/scworkbench_runtime_provenance.txt
  Rscript -e '\''cat("R=", as.character(getRversion()), "\n", sep=""); cat("BPCells=", as.character(packageVersion("BPCells")), "\n", sep=""); cat("BPCells RemoteSha=", as.character(packageDescription("BPCells")$RemoteSha), "\n", sep=""); cat("roxygen2=", as.character(packageVersion("roxygen2")), "\n", sep=""); cat("BSgenome.Hsapiens.UCSC.hg19=", as.character(packageVersion("BSgenome.Hsapiens.UCSC.hg19")), "\n", sep="")'\''
'

echo "==> GenomicRanges namespace preflight"
singularity exec --cleanenv \
  --bind "${CHECKOUT}:/work/scworkbench" \
  --pwd /work/scworkbench \
  "${IMAGE_PATH}" \
  Rscript inst/ci/check_genomicranges_runtime.R

echo "==> Declared Suggests preflight"
singularity exec --cleanenv \
  --bind "${CHECKOUT}:/work/scworkbench" \
  --pwd /work/scworkbench \
  "${IMAGE_PATH}" \
  Rscript inst/ci/check_declared_suggests.R --description DESCRIPTION

echo "==> Baked declared Suggests manifest"
singularity exec --cleanenv "${IMAGE_PATH}" \
  cat /opt/scworkbench_declared_suggests.csv

echo "==> Non-forced release gate"
singularity exec --cleanenv \
  --bind "${CHECKOUT}:/work/scworkbench" \
  --pwd /work/scworkbench \
  "${IMAGE_PATH}" \
  bash -lc 'inst/ci/check_release_package.sh'
