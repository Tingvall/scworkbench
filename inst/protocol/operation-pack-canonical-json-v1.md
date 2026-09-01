# Operation-pack canonical JSON identity v1

Scheme identifier: `scworkbench.operation_pack.canonical_json.v1`.

This is a deliberately narrower JSON canonicalization than RFC 8785. R does
not expose ECMAScript's `Number::toString` algorithm, and operation-pack
identity must not depend on either R or Python's default serializer. The
restricted decimal domain below is sufficient for operation definitions and
has a small, independently implementable byte contract.

The canonical product is UTF-8 with no byte-order mark, insignificant
whitespace, or trailing newline.

- Object members are ordered by the unsigned bytes of their UTF-8 keys.
  Duplicate keys and invalid UTF-8 are rejected. Arrays retain source order.
- Strings are decoded to Unicode scalar values. Quote, reverse solidus, and
  U+0008/U+0009/U+000A/U+000C/U+000D use JSON's short escapes. Other U+0000
  through U+001F values use lowercase `\u00xx`; every other scalar is emitted
  as UTF-8. Equivalent JSON Unicode escapes therefore have one product.
- `true`, `false`, and `null` have those exact lowercase spellings.
- A number must match JSON's decimal grammar, be finite, have at most 15
  significant decimal digits after insignificant leading and trailing zeros
  are removed, and have adjusted base-10 exponent in `[-307, 308]`. Zero,
  including negative zero, is `0`. Every nonzero value is
  `[-]d[.digits]e[-]digits`: one digit precedes the optional decimal point,
  trailing coefficient zeros are absent, `e` is lowercase, and the exponent
  has no plus sign or leading zeros. Thus `1`, `1.0`, and `1e0` are `1e0`;
  `0`, `0.0`, and `-0e12` are `0`; and `0.125` is `1.25e-1`.
- Malformed JSON, non-finite extensions, more than 15 significant decimal
  digits, and values outside the adjusted-exponent boundary are rejected with
  typed canonical-number diagnostics. A parsed runtime number must likewise
  be finite; file-backed manifests retain and validate their original decimal
  token before structural normalization.

Structural validation adds deterministic protocol fields before identity:
`identity_scheme`; empty `optional_requires` and `coverage`; derived
`interface_produces` when omitted; and internal `op_name` and
`definition_sha256`. `op_name` and `definition_sha256` never enter a definition
or manifest digest. All other normalized definition fields, including the
deterministic defaults just listed, enter each operation-definition digest.

The manifest digest covers the complete structurally normalized manifest,
including `identity_scheme`, with internal `op_name` and
`definition_sha256` removed from operations. The pack digest covers the
identity-scheme identifier, schema/protocol, manifest digest, namespace,
package, backend, compatibility, entry point, all operation-definition
digests, and the Python distribution/entry-point-group fields when applicable.
The digest algorithm is SHA-256 over the exact canonical UTF-8 bytes.

An omitted manifest `identity_scheme` is normalized to this sole v1 scheme so
already accepted pre-release manifests can be evaluated without changing
scientific fields. Any explicit different claim, and any different scheme in
a backend discovery or runtime attestation, fails before catalog publication.
