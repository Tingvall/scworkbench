# Adding an op

To add an op, do the following steps:

## Implement the op


Conventions:

- name should be _wb_op_foo()_
- file should be _R/ops_foo.R_
- contract should be _wb_op_foo(bundle, <resolved required inputs>, ...)_
- returns a list with named fields: 
  - outputs, containing one or more of the following:
      - _labels_ (data.frame: cell_id + cluster) 
      - _pseudotime_ (data.frame: cell_id + lineage_id + pseudotime)
      - _curves_ (data.frame: lineage_id + point + x + y)
      - _scores_ (data.frame: cell_id + scores)
  - _params_ list of resolved parameters actually used (for provenance)

example skeleton:

```{r}
#' @export
wb_op_foo <- function(bundle, space_id, ..., seed = 1) {
  if (!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) set.seed(seed)

  # compute ...
  res <- list(
    labels = labels_df,          # if produces labels
    pseudotime = pseudotime_df,  # if produces trajectory
    curves = curves_df,          # if produces trajectory
    scores = scores_vec,         # if produces scores
    params = list(seed = seed, ...)  # always include params
  )
  res
}
```

## Declare it in the session op spec

File: _R/session_context.R_


Add:

```{r}
foo = list(
  requires = c("space"),     # or "matrix", "labels"
  produces = c("scores")     # or "labels", "trajectory"
)
```

Rules:

_requires_ controls what _wb_session_run_op()_ resolves (_space_id, matrix_id, labels_)

_produces_ controls what _wb_session_run_op()_ stores in _run$outputs_ and sets active refs


## Add its UI/agent interface spec

File: _R/op_interface.R_

Add a new entry to _.wb_op_interface_registry()_:

```{r}
foo = list(
  op_name = "foo",
  title = "Foo scoring",
  description = "…",
  intent = c("score"),
  inputs = list(
    space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
  ),
  params = list(
    list(name="seed", type="int", default=1, help="Random seed.")
  ),
  produces = list(
    scores = list(kind="scores", description="Per-cell numeric score.")
  )
)
```


## Add to promotion registry

File: _R/op_registry.R_

Add:

```{r}
foo = list(
  saveable_outputs = list(
    scores = list(
      artifact_type = "scores",
      promoter = ".wb_promote_scores"
    )
  )
)
```

Then implement the promoter if it doesn’t exist:

_.wb_promote_scores(bundle, run, ...)_ writes to DB artifact tables

returns new _artifact_id_

## Register the op in the dispatch registry 

Each op must be registered in the dispatch registry, which defines how inputs are mapped to the op function.

File: _R/op_dispatch.R_

What to add

Add a runner function for your op to .wb_op_dispatch_registry().

Example for a simple space-based op (foo):

```{r}
.wb_op_dispatch_registry <- function() {
  list(
    # existing runners ...

    foo = function(bundle, space_id, ..., inputs, matrix_id = NULL, labels_df = NULL) {
      wb_op_foo(
        bundle = bundle,
        space_id = space_id,
        ...
      )
    }
  )
}
```

Example for an op that requires labels (slingshot-like):

```{r}
slingshot = function(bundle, space_id, ..., inputs, matrix_id = NULL, labels_df) {
  wb_op_slingshot(
    bundle = bundle,
    space_id = space_id,
    labels = labels_df,
    ...
  )
}
```

Example for an op that requires a matrix (meanexpr-like):

```{r}
meanexpr = function(bundle, space_id = NULL, ..., inputs, matrix_id, labels_df = NULL) {
  wb_op_meanexpr(
    bundle = bundle,
    matrix_id = matrix_id,
    features = inputs$features,
    ...
  )
}
```

