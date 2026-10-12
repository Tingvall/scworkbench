# Tuple445 fixture-size reporting correction

This addendum corrects reporting only. The sealed REVIEW_PACKET_445.md,
historical phase notes, source tuple445, installed444, and sealed454 evidence
remain unchanged.

The current producer log 446_collector_duplicate_sensitive_tuple445.log records
the public duplicate fixtures as direct 174 bytes, escaped 179 bytes, nested
216 bytes, and native_class 179 bytes. Each rejection recorded zero decoder
calls, maximum allocation 524336 bytes, cleanup PASS, and cache restoration PASS.
The packet and phase notes incorrectly describe the current direct fixture as
176 bytes. The historical independent tuple429 public reproduction was 176
bytes and remains separate evidence; its result is not relabeled or transferred.

No runtime or test was edited or rerun for this correction. These allocation
observations do not establish aggregate lifecycle RSS qualification.
