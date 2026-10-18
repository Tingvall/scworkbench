# Source review history, not execution evidence

Original prototype32d55e1d2a30ac062fc7485878fe56500c634200 used PCRE dollar
anchors, which permit a match before a final newline. Controller/Forge source
review caught that defect BEFORE installation, tests or execution of32d source.
The source was not released or qualified. Its exact commit remains available.

Corrected cb1800e6b40e985cc438a09a7f4d9321a24adfbb (integrated root
3009a196a36ed9cec8c471336983a5fd4b7de867) uses byte-oriented absolute
anchors and explicitly unknown encoding in BOTH preflight and emission passes.
Sable reviewed the corrected complete source and all four tests and accepted
it for actual installed focused qualification, not performance acceptance.
Trailing LF/CRLF and unsupported encoding tests preserve whole original fallback
and first-error behavior. They were strengthened, not waived or removed.

The new four ownership rows pin initial integrated source7b066dc; their current
discovery assertions reflect corrected source3009. Installation, focused tests,
matched measurements and future combined workflow remain PENDING here.
Prepared compact archive plans do not establish their execution or acceptance;
terminal evidence must be added through a NEW append-only ledger.
