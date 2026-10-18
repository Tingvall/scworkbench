# Qualification-only expected peer, supplied independently of runtime discovery.
# Publication/release defaults remain the tracked composite release pin.
.operation_pack_test_peer_pin <- function(release_pin,
    candidate_pin = Sys.getenv("SCWORKBENCH_TEST_PYBENCH_COMMIT", "")) {
  valid <- function(value) is.character(value) && length(value) == 1L &&
    !is.na(value) && grepl("^[0-9a-f]{40}$", value)
  stopifnot(valid(release_pin), is.character(candidate_pin),
    length(candidate_pin) == 1L, !is.na(candidate_pin))
  if (!nzchar(candidate_pin)) return(release_pin)
  stopifnot(valid(candidate_pin))
  candidate_pin
}
