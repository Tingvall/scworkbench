# Recipient audit

Finalize a recipient bundle before transfer, then inspect it through a read-only
handle. Audit does not mutate the recipient.

```r
wb_finalize_recipient_bundle(b)
recipient <- wb_open_bundle("path/to/recipient", read_only = TRUE)
on.exit(wb_close_bundle(recipient), add = TRUE)
wb_recipient_readiness(recipient)
wb_validate_bundle(recipient)
```
