# Follow-on generic ownership decisions

Twenty-one explicit named rows extend the existing versioned engine ledger:
five raw-file SHA contracts (a8e31e3), three issued-registry observation contracts
(b1fdb68), three actual synthetic-runner boundary contracts (2fe2068), five
recipient actual-table observation contracts (3066d0d), and five independent
row-hash/fold contracts (89bd10c). Each ledger row gives its own generic engine
authority/lifecycle reason and exact existing source checkpoint. These are not
scientific method tests and do not modify official pack ownership.

The three runner entrypoints now explicitly assert their shared lifecycle
helper's TRUE return. The helper's detailed mutation, rollback, retry,
promotion and fresh pack-free recipient assertions are unchanged. This fixes
ownership extraction's initial `length(assertions)>0` rejection without
weakening the generator or automatically assigning unknown discovered tests.
Their runtime rerun belongs to the assembled affected checkpoint; no new pass
is inferred merely from assertion extraction.

Current-only regeneration, exit0:

```text
PHASE8_TEST_INVENTORY tests=242 files=139 migrated_reference_rows=63
PHASE8_CURRENT_TEST_INVENTORY tests=492 files=208 introduced=252 moved=2
```

This is source discovery/ownership accounting, not492 executed or passing
tests. Frozen historical inventories and original qualification outcomes remain
unchanged. Unintegrated numeric-token and ASCII experiments are not counted.
