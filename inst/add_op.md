# Adding an Op

Current engine rule:

- add ops through one canonical path
- do not edit parallel registries by hand

The canonical registration point is:

- `R/op_catalog.R`

An op should be added as:

1. a `wb_op_*()` implementation function
2. a runner in `R/op_catalog.R`
3. one `trajectory_de = list(...)`-style op entry in `.wb_op_catalog()`
4. contract tests
5. optional client adaptation

## 1. Implement the op function

Conventions:

- name: `wb_op_foo()`
- file: `R/op_foo.R` or nearby domain file
- inputs: resolved engine objects, not client-shaped UI payloads
- output: `list(outputs = <named primitives>, params = <list>)`

Example skeleton:

```r
#' @export
wb_op_foo <- function(bundle, matrix_id, cells = NULL, seed = 1L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  # compute ...

  list(
    outputs = list(
      summary = wb_prim_obs_table(
        table = out_tbl,
        table_type = "foo_summary",
        entity_kind = "generic"
      )
    ),
    params = list(
      matrix_id = matrix_id,
      seed = as.integer(seed)
    )
  )
}
```

Rules:

- outputs must be named primitives
- primitive kinds must already be engine-supported
- `params` must reflect resolved values actually used

## 2. Add the runner in `R/op_catalog.R`

The runner adapts resolved session inputs to the op function.

Example:

```r
.wb_runner_foo <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "foo runner: missing resolved$matrix.")

  raw <- wb_op_foo(
    bundle = bundle,
    matrix_id = as.character(resolved$matrix$matrix_id)[1],
    cells = effective_cells,
    seed = as.integer(inputs$seed %||% 1L)
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs) && is.list(raw$params),
             "foo must return list(outputs=<list>, params=<list>).")
  raw
}
```

## 3. Register the op in `.wb_op_catalog()`

Define together:

- required inputs
- produced primitive kinds
- promotable outputs
- interface metadata
- runner

Example shape:

```r
foo = list(
  op_name = "foo",
  title = "Foo summary",
  description = "Compute foo from a resolved matrix.",
  intent = c("summary"),
  requires = list(matrix = "matrix"),
  produces = list(summary = "obs_table"),
  promotable = c("summary"),
  inputs = list(
    matrix = list(required = TRUE)
  ),
  params = list(
    list(name = "seed", type = "int", default = 1, help = "Random seed.")
  ),
  interface_produces = list(
    summary = list(kind = "obs_table", description = "Foo summary table.")
  ),
  runner = .wb_runner_foo
)
```

Do not add separate interface or dispatch entries elsewhere.

Those are derived from the catalog.

## 4. Promotion

If the op emits an existing primitive kind and includes the output name in
`promotable`, promotion should work through the existing promoter map.

If the op needs a new primitive kind:

- stop first
- define the primitive contract before adding the op

Do not smuggle a new output type through an existing primitive casually.

## 5. Tests

Minimum:

- contract test for the op
- real-bundle smoke run if the op touches substantial engine behavior

Typical places:

- `tests/test_op_<name>_contract.R`
- `inst/tests/run_contract_tests.R` auto-discovers every top-level `test_*`
  function in `tests/test_*.R`; no manual registry entry is permitted

Test:

- interface shape
- output primitive kind(s)
- required columns / metadata
- promotion, if promotable

## 6. Docs

Update:

- roxygen on exported helpers
- relevant contract docs
- extension docs if this introduces a new extensibility surface

## Anti-Patterns

Do not:

- add separate manual interface registries
- add client-specific behavior into the op
- return raw data frames instead of primitives
- hide major analysis decisions in plot mappers instead of ops

## Related Docs

- `inst/foundation_contracts.md`
- `docs/engine_extension_patterns.md`
- `docs/navigation_contract_draft.md`
