# Frozen pre-migration PeakVI recipient fixture

`phase6_peakvi_old_core_historical.bundle.tar.gz` was generated with
`phase6_peakvi_old_core_historical_build.R` from the independently accepted
pre-migration core commit `d624cfd0cc1b84440681967fc30a214004e2c591`.
It contains one promoted historical `peakvi_fit` model artifact and a fitted
space, finalized before freezing. SHA-256:
`4b7ab3996986cd69c3040c257332a9c19ba0e3245e772f5a1ed13508a6fa9c26`.

The ownership regression unpacks a disposable copy and uses only read-only
getters, provenance inspection, artifact loading, and recipient validation.
It compares the complete copied bundle filesystem fingerprint before and
after. The archived fixture is not rewritten by tests.
