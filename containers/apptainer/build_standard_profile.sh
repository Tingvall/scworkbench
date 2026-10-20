#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 5 ]]; then
  echo "Usage: bash $0 BASE_SIF OUTPUT_SIF PYBENCH_SOURCE PACK_ROOT NEW_CONTEXT" >&2
  echo "Set SCWB_PREPARE_ONLY=1 to prepare without building." >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "${SCRIPT_DIR}/../.." && pwd)"
for command in git jq sha256sum realpath sed; do
  command -v "${command}" >/dev/null || { echo "Missing ${command}" >&2; exit 1; }
done
BASE="$(realpath "$1")"
OUTPUT="$(realpath -m "$2")"
PYBENCH="$(realpath "$3")"
PACKS="$(realpath "$4")"
CONTEXT="$(realpath -m "$5")"
[[ -f "${BASE}" && ! -e "${OUTPUT}" && ! -e "${CONTEXT}" ]] || {
  echo "Base must exist; output and context must be new paths." >&2; exit 1;
}
[[ "${BASE}" != *[[:space:]]* ]] || {
  echo "Use a base SIF path without whitespace (definition From field)." >&2; exit 1;
}
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) echo "Unsupported native architecture: $(uname -m)" >&2; exit 1 ;;
esac
if [[ ${SCWB_PREPARE_ONLY:-0} != 1 ]]; then
  ENGINE="${SCWB_CONTAINER_ENGINE:-}"
  if [[ -z "${ENGINE}" ]]; then
    ENGINE="$(command -v apptainer || command -v singularity || true)"
  fi
  [[ -n "${ENGINE}" ]] || { echo "Missing apptainer/singularity" >&2; exit 1; }
fi
PROFILE="${CORE}/inst/standard_profile/profile.json"
CORE_COMMIT="$(git -C "${CORE}" rev-parse HEAD)"
PYBENCH_COMMIT="$(jq -r .pybench_source_commit "${PROFILE}")"
[[ -z "$(git -C "${CORE}" status --porcelain)" &&
   -z "$(git -C "${PYBENCH}" status --porcelain)" &&
   "$(git -C "${PYBENCH}" rev-parse HEAD)" == "${PYBENCH_COMMIT}" ]] || {
  echo "Core/PyBench must be clean; PyBench HEAD must match profile.json." >&2; exit 1;
}
read -r PROFILE_SHA _ < <(sha256sum "${PROFILE}")
read -r BASE_SHA _ < <(sha256sum "${BASE}")
mkdir -p "$(dirname "${OUTPUT}")" "$(dirname "${CONTEXT}")"
mkdir "${CONTEXT}"
mkdir "${CONTEXT}/operation_packs"
clone_pin() {
  git clone --quiet --no-local "$1" "$2"
  git -C "$2" checkout --quiet --detach "$3"
  [[ "$(git -C "$2" rev-parse HEAD)" == "$3" &&
     -z "$(git -C "$2" status --porcelain)" ]]
}
clone_pin "${CORE}" "${CONTEXT}/scworkbench" "${CORE_COMMIT}"
clone_pin "${PYBENCH}" "${CONTEXT}/pybench" "${PYBENCH_COMMIT}"
while IFS=$'\t' read -r package commit manifest_sha; do
  clone_pin "${PACKS}/${package}" "${CONTEXT}/operation_packs/${package}" "${commit}"
  read -r observed _ < <(sha256sum \
    "${CONTEXT}/operation_packs/${package}/inst/scworkbench/operation-pack.json")
  [[ "${observed}" == "${manifest_sha}" ]] || {
    echo "Wrong manifest bytes: ${package}" >&2; exit 1;
  }
done < <(jq -r '.packs[] | [.package,.source_commit,.manifest_source_sha256] | @tsv' "${PROFILE}")
[[ "$(jq '.packs | length' "${PROFILE}")" == 7 ]]

# The checked-out source determines its own build pin; no self-referential Git pin.
# Escape sed replacement metacharacters in the externally supplied base path.
BASE_ESCAPED="$(printf '%s' "${BASE}" | sed 's/[\\&|]/\\&/g')"
sed -e "s|@BASE_SIF@|${BASE_ESCAPED}|g" \
  -e "s|@BASE_SHA256@|${BASE_SHA}|g" \
  -e "s|@CORE_COMMIT@|${CORE_COMMIT}|g" \
  -e "s|@PYBENCH_COMMIT@|${PYBENCH_COMMIT}|g" \
  -e "s|@PROFILE_SHA256@|${PROFILE_SHA}|g" \
  -e "s|@ARCH@|${ARCH}|g" \
  "${SCRIPT_DIR}/standard_profile.def.in" > "${CONTEXT}/standard_profile.def"
printf 'CORE_COMMIT=%s\nPYBENCH_COMMIT=%s\nPROFILE_SHA256=%s\nBASE_SHA256=%s\nARCH=%s\n' \
  "${CORE_COMMIT}" "${PYBENCH_COMMIT}" "${PROFILE_SHA}" "${BASE_SHA}" "${ARCH}" \
  > "${CONTEXT}/build_sources.env"
echo "Pinned build context: ${CONTEXT}"
if [[ ${SCWB_PREPARE_ONLY:-0} == 1 ]]; then
  exit 0
fi
cd "${CONTEXT}"
"${ENGINE}" build --fakeroot "${OUTPUT}" standard_profile.def
"${ENGINE}" inspect --json "${OUTPUT}" > image.inspect.json
jq -e --arg core "${CORE_COMMIT}" --arg pybench "${PYBENCH_COMMIT}" \
  --arg profile "${PROFILE_SHA}" --arg arch "${ARCH}" \
  '.data.attributes.labels | .CoreCommit == $core and .PyBenchCommit == $pybench
    and .ProfileSHA256 == $profile and .Architecture == $arch' image.inspect.json
"${ENGINE}" exec --cleanenv "${OUTPUT}" Rscript --vanilla \
  /opt/scworkbench/tests/profile/profile_process.R profile \
  /usr/local/lib/R/site-library /usr/local/lib/R/site-library \
  /opt/scworkbench/inst/standard_profile/activate.R \
  /opt/standard_profile_installation_receipt.json
sha256sum "${OUTPUT}" > "${CONTEXT}/image.sha256"
echo "Standard-profile ${ARCH} SIF ready: ${OUTPUT}"
echo "Build sources and image checksum: ${CONTEXT}"
