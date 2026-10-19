# Installed fixture ownership diagnosis and test-only correction

Original installed67f29 focused gate executed10:5old contracts passed;5new tests
failed. Four failures asserted no held writer despite using wb_init_bundle; the
fifth expected an outermost caller-TX error despite an assembly owner still being
held. Two buffered cleanup warnings (dbDisconnect reminder/already disconnected)
remain in the original log and are not relabelled absent or proved fixed here.
Raw capsule_67f29a1_focused.log and exit1 are retained unchanged.

Source: wb_init_bundle transfers its initialization lock into assembly ownership
(bundle_init.R118/136, mutation_boundary.R20–44) until public close. A nested lock
handle shares the same owner token; releasing the same handle twice can consume
underlying depth, so explicit release must clear its cleanup reference.

Independent installed diagnostic ran old2eb and new67f29 once each (outer0,
both trial0, immutable SHA guards0), root capsule_fixture_ownership_diagnosis.
All12observations agreed: constructor assembly depth1→1/token exact, including
caller TX returning successfully; public close/reopen initially unheld and stays
unheld after recovery; outermost TX rejects acquire-before-TX on both; explicitly
held nested owner depth1→1 on both with/without TX. This demonstrates the failed
fixture premise, not a runtime ownership regression.

Test-only correction: default fixture uses public close/reopen and explicitly
asserts the intended initially-unheld/nonassembly premise. All strict original
no-lock/SQL/FS/publication/condition assertions remain. Add separate constructor
assembly coverage within the existing nested/TX test: exact token/depth/assembly,
full actual SQL state and total_changes preserved with/without caller TX. Clear
explicitly released lock handles before their on.exit cleanup. Fixture construction
owns cleanup before reopen, and fixture close clears its handle.

No R runtime, contract, guard, transaction, limit, expected science or performance
threshold changes. Literal new test count remains5; focused union remains10.
Source parse/diff checks only for this delta; exact source review required before
commit/retry. Original failures and cleanup warnings remain evidence until an
actual corrected retry is terminal.
