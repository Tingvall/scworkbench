# Current-peer composite fixture maintenance: source decision

Root-reviewed patch phase3b_current_peer_fixture_maintenance.patch modifies only the
expected qualification peer and four exact protocol hashes in the historical
composite test. No protocol/runtime/pack/fixture byte is changed. ALL lifecycle,
mutation, cleanup, promotion, model, receipt and identity assertions remain
literal originals. No claim this revised test has passed.

Actual prior three skips remain actual skips: the environment was unset, and
the retained test expected an obsolete historical paired protocol generation.
Historical roots are available and clean; they are not falsely called absent.
The source-only comparison in HISTORICAL_PHASE3B_FIXTURE_CONFIGURATION_SOURCE_AUDIT.md
shows why historical root selection cannot satisfy current protocol bytes.

The proposed final environment truthfully uses the CURRENT peer:

```
SCWORKBENCH_PHASE3B_PYBENCH_ROOT=/home/dirk/Projects/.pybench-worktrees/engine-simplification-quill-20261018
SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST=/tmp/quill-engine-simplification-venv/lib/python3.11/site-packages/scwbpyv3reference/operation-pack.json
SCWORKBENCH_PYBENCH_PYTHON=/tmp/quill-engine-simplification-venv/bin/python
```

The expected default peer becomes actual reviewed0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e,
NOT observed HEAD at test time. Existing qualification helper
tests/helpers/operation_pack_test_peer_pin.R validates any independently supplied
SCWORKBENCH_TEST_PYBENCH_COMMIT40hex override. An explicitly reviewed final peer
must be supplied through that existing override and guarded source maps. The
intended S1 peer changes runtime snapshot comparison; it is NOT test-only. Its
runtime change requires its own review/qualification, and unchanged protocol
bytes must still be proved by the literal comparisons below. This override
is not permission to accept arbitrary observed HEAD. Publication/release
companion pins are not changed.

Current R protocol and current peer protocol independently have identical
four digests proposed in the patch: bc8d6552...,81f5ef42...,492ee6fb...,27f0e731....
The protocol assertion still compares complete R/Python bytes AND each exact
literal digest; none is removed. Source inspected current peer is clean0ef.

Actual installed scwbpyv3reference manifest is byte-identical to CURRENT peer
tests/fixtures/operation-pack-v3-python-reference/operation-pack.json:
SHA2566e153505985255f2ee42602ac3b4c34a93ddf74d3c32c24c0efdb2042035cfac.
Installed pack.py equals current source at
SHA256da83fd89eaa131d3fb976bdd00b23b7581ab3aebd2626dd0406720857c4d027d;
__init__.py matches too. Installed entry-point metadata names the declared
scworkbench.operation_packs.v3 reference. Interpreter .pth points to that
CURRENT peer source. No fake historical/current interchange, PYTHONPATH
override, installation or altered package code is used.

Root approved this exact test-only maintenance; independent source review and
focused three definitions must still complete against the frozen
installed core and guarded peer/interpreter. Old skipped evidence is preserved;
new focus counts are separate and cannot be added into an old full-suite count.
