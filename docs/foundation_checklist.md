# Foundation Checklist

This checklist is for stabilizing the `data + getters + selectors` foundation before expanding client surface area.

## 1. Data Layer

- [ ] Canonical cell order is explicitly defined and tested (`cells.rowid`).
- [ ] Required schema tables are validated (`cells`, `datasets`, `features`, `matrices`).
- [ ] Optional schema tables are validated when present (spaces, artifacts, vectors).
- [ ] Matrix-to-cell alignment assumptions are tested on real bundles.
- [ ] Bundle migration behavior is tested for at least one older bundle shape.

## 2. Getter Layer

- [ ] Getter output shapes/classes are documented in roxygen for public `wb_*` getters.
- [ ] Getter ordering guarantees are tested (especially `wb_cells`, `wb_meta(cells=...)`, `wb_space(cells=...)`).
- [ ] Error behavior for unknown IDs / invalid args is tested.
- [x] Typed coverage helpers (`wb_cells_with_space`, `wb_cells_with_matrix`,
  `wb_cell_coverage`) derive exact matrix/space/primitive availability and are
  tested across direct IDs, session refs, artifact refs, partial dimensions,
  explicit cell order, and insufficient intersections.
- [ ] Any non-guaranteed ordering paths are documented as such.

## 3. Selector Layer

- [ ] Selector inputs/outputs are documented (`bundle` or prior selector output).
- [ ] Canonical-order determinism is tested for set algebra (`and`, `or`, `not`).
- [ ] Empty-selection behavior is explicit and tested.
- [ ] Recipe attachment (`wb_recipe`) and bundle attachment are tested.
- [ ] Selector behavior is validated across at least two spaces and one vector family.

## 4. Cross-Layer Invariants

- [ ] Getter and selector outputs remain compatible with downstream ops.
- [ ] Notebook smoke path validates core data/getter/selector assumptions.
- [ ] Foundation tests run in CI or a repeatable local command.

## 5. Documentation

- [ ] Public function docs are generated from roxygen and up to date.
- [ ] Foundation contracts are documented in markdown (`inst/foundation_contracts.md`).
- [ ] This checklist is kept current as invariants are added/changed.

## Suggested Run Order

1. Rebuild a clean bundle (`000` notebook).
2. Run foundation tests.
3. Run notebook smoke sequence.
4. Update docs if behavior changed.
