# Contiguous numeric emission: prospective scope and budget

Clean base c590070b9580f760272b49c8aae13063884aa0cb. The prior numeric
100000-value component measured vector .086s and scalar-list .111s; both missed
the original 10x target against frozen13de (.629/.593s). Dataframe1.513/.476s
also missed10x; this change does not replace dataframe object assembly.
Prospective flat-array target: <=.6*prior+.01s, retaining the original10x target
separately. Typed-space5s remains unchanged; 20.981/20.577s are still MISS.

Private native emission reuses the unchanged number formatter and eligibility.
It validates the complete <=131072-element batch before allocating one managed
buffer, then rechecks values on access. Flat arrays preserve existing framing;
space row mode emits the same row-major nested arrays without per-row/per-value
R lists or strings. At the ceiling, buffer<=67*131072+3 bytes plus input and
returned JSON remain within the existing256-byte/element temporary allowance.
No durable state or authority is introduced. Unsupported carriers fall back to
the existing canonical encoder, preserving its diagnostics and first error.
Locale and absent-native standalone fallbacks remain unchanged. Source and
independent frozen-byte tests must precede any performance claim.
