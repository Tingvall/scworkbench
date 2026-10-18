# Prospective append-local numeric token reuse

Baseline exact6c61098f9ca0a6e7d94d375743810e26e7b8bc61. Commit this ledger
before runtime edits. No measurements/qualification at this checkpoint.

Targets: >=25% faster complete realistic normalized matrix-slice identity versus
the parent, unique-random elapsed<=old*1.10+0.01s, peakRSS<=old+10%; identical
full canonical bytes/SHA and integer/error behavior. Full-workflow171 budget
MISS remains unchanged. No raised guard, source rescan or identity change.

Scope: only append_body noninteger number() call. Fixed64-slot invocation-stack
table with exact uint64 bit keys via memcpy, valid flags and successful unchanged
number() tokens; replace colliding slots. Actual matrix value is read every
iteration, finite check before lookup. Integer coordinate fast path stays exact
and bypasses table. No global/persistent cache or scientific/authority observation.
Slot state fits<=5KiB in existing4MiB native ledger; sourcevalue authority remains
all existing admitted reads and lifecycle checks. Local workspace ends at append.

Focused proof must cover frozen full-byte/hash oracle; collisions/evictions,
signedzero, repeatednegatives, subnormal/range/nonfinite late errors and partial
prefix, unique values and integerbypass. Actual hit/count evidence requires an
external development instrumented copy of the unchanged production Csource,
never new public telemetry/bindings or a test-only authority shortcut. Runtime
tests/compile/install/benchmarks await exact source review and serial release.

Implementation source:64*(8-byte key+64-byte token+1-byte valid)=4672-byte
separate stackarrays, no structpadding/globalstate. sizeof(double)==sizeof(uint64_t)
guards bitcopy; finitecheck always precedeshit. Slot = low6(bits XOR(bits>>32));
exactfull64bit comparison determineshit. Quarter-integer fixture values all
collide atslot0, exercising eviction without changingindependentbyteoracle.
number() itself remains unchanged. Wholeprimitive/sourceidentity checks untouched.

Three focused definitions cover fullrawbytes/SHA, independently constructed
complete matrix-slice framing for repeatednormalized/randomvalues and chunks,
and exactoldfinite/rangeerrors plus flushed64KiBprefix/cleanup/retry. Tests add
no productioncounter or native/publicbinding. Repeatedactualfixture plus source
proof and subsequent matchedinstalled measurement establish use/benefit; any
optional number-call census must instrument only a separatelycompiled development
copy after review, never the final installedruntime or authorityobservations.
