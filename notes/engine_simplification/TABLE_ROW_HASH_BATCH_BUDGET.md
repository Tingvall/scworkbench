# Independent row SHA-256 batching: prospective budget

Before implementation: target>=25-percent lower complete100000-row ordered
fold elapsed than old242, excluding row emission, with whole-process peak
RSS<=matched old+10 percent. Exact independent old preimages and final state
are mandatory. No new performance evidence is claimed.

Only independent per-row digests may be vectorized; the ordered previous-state
fold and its serializedJSON template remain byte-for-byte unchanged. No new
identity scheme, JSON representation, row order or public interface.

Primary source proof for installed digest0.6.35 and openssl2.2.0:

- [digest.c](https://raw.githubusercontent.com/cran/digest/0.6.35/src/digest.c)
  lines88-90 reads STRING_VALUE/strlen, then SHA-256 at149-163. Installed
  Rdefines.h126-127 defines STRING_VALUE as CHAR(Rf_asChar(x)).
- [openssl hash.c](https://raw.githubusercontent.com/cran/openssl/2.2.0/src/hash.c)
  lines47-70 hashes each CHAR(STRING_ELT)/LENGTH without encoding conversion.
  Non-NA, NUL-free ordinary R strings therefore use the same bytes, including
  Latin1/UTF8/bytes tags; do not normalize them to UTF8.
- [openssl hash.R](https://raw.githubusercontent.com/cran/openssl/2.2.0/R/hash.R)
  lines167-170 dispatches the whole string vector to one native call. This is
  not the allocation-heavy connection/readBin path used by file hashing.

NA differs: old digest hashes literalNA bytes, while openssl propagatesNA.
NA/attributes/classes/names/noncharacters/ALTREP/over1000 elements bypass
BEFORE forcing any elements. Unsupported cases keep the original loop and its
partial-state/first-error behavior. An openssl failure falls back before any
state fold is advanced.

Fast-batch admission: existing input UTF8/raw encoded bytes (without recoding)
plus256bytes/row+4096 <=min(32MiB, existing ordinary dense guard/4). This
conservative carrier allowance covers row-byte lengths, vectorized64-hex
results, pointers/classes and bounded native digest context. Original input
strings already belong to the caller. Larger inputs use the original loop;
there is no new rejection or universal bounded-input claim. Standalone source
without the private native eligibility symbol also uses the old loop.
