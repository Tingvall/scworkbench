test_operation_pack_test_peer_pin_contract <- function() {
  env <- new.env(parent = baseenv())
  sys.source("tests/helpers/operation_pack_test_peer_pin.R", env)
  pin <- env$.operation_pack_test_peer_pin
  release <- "e724f55f709c5f1f3e99e1afc5cf83301c7a86bd"
  candidate <- "0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e"
  stopifnot(identical(pin(release, ""), release),
    identical(pin(release, candidate), candidate))
  for (bad in list("auto", "HEAD", substr(candidate, 1L, 39L),
      paste0(candidate, "0"), toupper(candidate), NA_character_,
      c(candidate, release), 1)) {
    stopifnot(inherits(tryCatch(pin(release, bad), error = identity), "error"))
  }
  # Expected state must not be derived from the observed attestation: even a
  # well-formed caller pin still rejects an independently observed wrong peer.
  expected <- pin(release, candidate)
  stopifnot(inherits(tryCatch(stopifnot(identical(release, expected)),
    error = identity), "error"))
  TRUE
}
