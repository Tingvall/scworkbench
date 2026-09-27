.wb_runner_slingshot_adopt <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$model), "slingshot_adopt runner: missing resolved$model.")
  raw <- wb_op_slingshot_adopt(
    bundle = bundle,
    model_ref = resolved$model,
    cells = as.character(effective_cells),
    source = inputs$source
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "slingshot_adopt must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_py_protocol_hello <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  wb_op_py_protocol_hello(
    bundle = bundle,
    cell_set = inputs$cell_set %||% "all",
    n_preview = inputs$n_preview %||% 25L
  )
}

.wb_runner_model_bound_latent_union <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$reference_space), "model_bound_latent_union runner: missing reference_space.")
  .wb_assert(!is.null(resolved$query_space), "model_bound_latent_union runner: missing query_space.")
  .wb_assert(!is.null(resolved$model), "model_bound_latent_union runner: missing model.")
  .wb_assert(!is.null(resolved$projection_summary), "model_bound_latent_union runner: missing projection_summary.")
  raw <- wb_op_model_bound_latent_union(
    bundle = bundle,
    reference_space = resolved$reference_space,
    query_space = resolved$query_space,
    model = resolved$model,
    projection_summary = resolved$projection_summary,
    cells = as.character(effective_cells),
    space_id_out = inputs$space_id_out %||% "model_bound_latent_union"
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "model_bound_latent_union must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_chromvar <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "chromvar runner: missing resolved$matrix.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 1,
             "chromvar runner: effective_cells must contain at least 2 cells.")

  matrix_id <- resolved$matrix$matrix_id
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "chromvar runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_chromvar(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    motif_library = inputs$motif_library,
    motifs = inputs$motifs %||% NULL,
    motif_match_set = inputs$motif_match_set %||% NULL,
    min_motif_peaks = inputs$min_motif_peaks %||% 10L,
    max_motif_peaks = inputs$max_motif_peaks %||% NULL,
    motif_p_cutoff = inputs$motif_p_cutoff %||% 5e-05,
    motif_w = inputs$motif_w %||% 7L,
    seqlevels_mode = inputs$seqlevels_mode %||% "standard",
    seqlevels_include = inputs$seqlevels_include %||% NULL,
    seqlevels_exclude = inputs$seqlevels_exclude %||% NULL,
    background_iterations = inputs$background_iterations %||% 50L,
    background_w = inputs$background_w %||% 0.1,
    background_bs = inputs$background_bs %||% 50L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "chromvar must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_feature_set_import <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "feature_set_import runner: missing resolved$matrix.")
  .wb_assert(!is.null(inputs$namespace), "feature_set_import runner: inputs$namespace is required.")

  raw <- wb_op_feature_set_import(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    source_path = inputs$source_path %||% NULL,
    source_format = inputs$source_format %||% "auto",
    namespace = as.character(inputs$namespace)[1],
    collection = inputs$collection %||% NULL,
    subcollection = inputs$subcollection %||% NULL,
    species = inputs$species %||% NULL,
    organism = inputs$organism %||% NULL,
    gene_id_type = inputs$gene_id_type %||% NULL,
    set_id_col = inputs$set_id_col %||% "feature_set",
    set_name_col = inputs$set_name_col %||% NULL,
    gene_col = inputs$gene_col %||% "feature_id",
    description_col = inputs$description_col %||% "description",
    split_by_collection = inputs$split_by_collection %||% FALSE,
    overwrite = inputs$overwrite %||% TRUE,
    strict = inputs$strict %||% FALSE,
    created_by = inputs$created_by %||% NULL,
    source_id = inputs$source_id %||% NULL,
    source_version = inputs$source_version %||% NULL,
    origin = inputs$origin %||% "imported",
    is_readonly = inputs$is_readonly %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "feature_set_import must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_feature_set_namespace_transfer <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$source_matrix), "feature_set_namespace_transfer runner: missing resolved$source_matrix.")
  .wb_assert(!is.null(resolved$target_matrix), "feature_set_namespace_transfer runner: missing resolved$target_matrix.")

  raw <- wb_feature_set_namespace_transfer(
    bundle = bundle,
    source_matrix_id = resolved$source_matrix$matrix_id,
    target_matrix_id = resolved$target_matrix$matrix_id,
    namespace = inputs$namespace %||% NULL,
    namespaces = inputs$namespaces %||% NULL,
    feature_sets = inputs$feature_sets %||% NULL,
    mode = inputs$mode %||% "mirror",
    target_namespace = inputs$target_namespace %||% NULL,
    overwrite = inputs$overwrite %||% FALSE,
    strict = inputs$strict %||% TRUE,
    min_retained_features = inputs$min_retained_features %||% 1L,
    min_retained_fraction = inputs$min_retained_fraction %||% 0,
    created_by = inputs$created_by %||% NULL,
    notes = inputs$notes %||% NULL
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "feature_set_namespace_transfer must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_set_derive <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  target_cell_set <- as.character(inputs$target_cell_set %||% "")[1]
  .wb_assert(nzchar(target_cell_set), "cell_set_derive runner: target_cell_set is required.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "cell_set_derive runner: effective_cells is empty.")

  raw <- wb_cell_set_derive(
    bundle = bundle,
    cell_set = target_cell_set,
    cells = as.character(effective_cells),
    role = inputs$role %||% "analysis_universe",
    status = inputs$status %||% "candidate",
    source = inputs$source %||% "selector_recipe",
    created_by = inputs$created_by %||% NULL,
    description = inputs$description %||% NULL,
    recipe = inputs$recipe %||% NULL,
    overwrite = inputs$overwrite %||% TRUE,
    promote_manifest = FALSE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_set_derive must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_metadata_cell_vector <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  source_field <- .wb_metadata_resolve(bundle, inputs$source_column, allow_core = TRUE)
  vector_name <- as.character(inputs$vector_name %||% source_field$display_name[[1L]])[1]
  .wb_assert(nzchar(vector_name), "metadata_cell_vector runner: vector_name is required.")
  if (!isTRUE(inputs$overwrite %||% FALSE)) {
    arts <- wb_art_list(bundle)
    collision <- nrow(arts) && any(
      as.character(arts$type %||% "") == "cell_vector" &
        as.character(arts$name %||% "") == vector_name
    )
    .wb_assert(!collision, paste0("A promoted cell_vector named '", vector_name,
                                  "' already exists. Set overwrite=TRUE to create a superseding immutable artifact."))
  }
  raw <- wb_op_metadata_cell_vector(
    bundle = bundle, source_column = inputs$source_column, cells = as.character(effective_cells),
    value_type = inputs$value_type %||% "auto", missing_policy = inputs$missing_policy %||% "error",
    missing_label = inputs$missing_label %||% "__MISSING__", vector_name = vector_name,
    overwrite = inputs$overwrite %||% FALSE
  )
  raw$params$cell_set <- as.character(inputs$cell_set %||% "all")[1]
  raw
}

# Canonical op catalog.
# Add new ops in one place only: contract + wrangler + interface metadata.
.wb_op_catalog <- function() {
  catalog <- list(
    chromvar = list(
      op_name = "chromvar",
      title = "chromVAR deviations",
      description = "Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.",
      intent = c("atac", "motif", "signature", "score"),
      requires = list(matrix = "matrix"),
      produces = list(
        deviation_z = "cell_vector_family",
        deviation_raw = "cell_vector_family",
        motif_summary = "obs_table"
      ),
      promotable = c("deviation_z", "deviation_raw", "motif_summary"),
      runner = .wb_runner_chromvar,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "motif_library", type = "string", default = NULL,
             help = "Canonical motif-library key from the motif registry."),
        list(name = "motifs", type = "string_vec", default = NULL,
             help = "Optional motif-key subset within motif_library."),
        list(name = "motif_match_set", type = "string", default = NULL,
             help = "Optional canonical motif-match-set key to reuse cached motif-to-peak matches."),
        list(name = "min_motif_peaks", type = "int", default = 10L, min = 1, max = 100000,
             help = "Minimum number of matched peaks per retained motif."),
        list(name = "max_motif_peaks", type = "int", default = NULL, min = 1, max = 1000000,
             help = "Optional maximum number of matched peaks per retained motif."),
        list(name = "motif_p_cutoff", type = "dbl", default = 5e-05, min = 0, max = 1,
             help = "Motifmatchr p-value cutoff."),
        list(name = "motif_w", type = "int", default = 7L, min = 1, max = 100,
             help = "Motifmatchr background window width."),
        list(name = "seqlevels_mode", type = "choice", default = "standard", choices = c("standard", "all"),
             help = "Seqlevel policy; standard chromosomes are the default."),
        list(name = "seqlevels_include", type = "string_vec", default = NULL,
             help = "Optional explicit seqlevels to keep after applying seqlevels_mode."),
        list(name = "seqlevels_exclude", type = "string_vec", default = NULL,
             help = "Optional explicit seqlevels to drop after applying seqlevels_mode."),
        list(name = "background_iterations", type = "int", default = 50L, min = 1, max = 1000,
             help = "Number of chromVAR background iterations."),
        list(name = "background_w", type = "dbl", default = 0.1, min = 0, max = 10,
             help = "Background peak matching window width."),
        list(name = "background_bs", type = "int", default = 50L, min = 2, max = 1000,
             help = "Background peak matching bin count.")
      ),
      interface_produces = list(
        deviation_z = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "motif",
          description = "Per-cell chromVAR z-scores keyed by motif."
        ),
        deviation_raw = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "motif",
          description = "Per-cell raw chromVAR deviations keyed by motif."
        ),
        motif_summary = list(
          kind = "obs_table",
          description = "Per-motif chromVAR summary statistics."
        )
      )
    ),
    feature_set_import = list(
      op_name = "feature_set_import",
      title = "Feature-Set Library Import",
      description = "Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.",
      intent = c("feature_set", "import", "gene_set", "provenance", "library"),
      requires = list(matrix = "matrix"),
      produces = list(
        import_summary = "obs_table",
        import_manifest = "obs_table",
        rejected_sets = "obs_table"
      ),
      promotable = c("import_summary", "import_manifest", "rejected_sets"),
      runner = .wb_runner_feature_set_import,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "source_path", type = "path", required = TRUE,
             help = "Path to GMT, RDS list/data.frame, or CSV-like table source."),
        list(name = "source_format", type = "choice", default = "auto",
             choices = c("auto", "gmt", "rds", "table"),
             help = "Input parser. auto infers from file extension."),
        list(name = "namespace", type = "string", required = TRUE,
             help = "Target feature-set namespace base label."),
        list(name = "collection", type = "string", default = NULL,
             help = "Optional collection label recorded in import manifests."),
        list(name = "subcollection", type = "string", default = NULL,
             help = "Optional subcollection label; used for namespace splitting when requested."),
        list(name = "species", type = "string", default = NULL,
             help = "Species/organism label recorded in feature-set metadata."),
        list(name = "organism", type = "string", default = NULL,
             help = "Optional organism label; when omitted, species is used."),
        list(name = "gene_id_type", type = "string", default = NULL,
             help = "Identifier type expected in source genes, for example gene_symbol."),
        list(name = "set_id_col", type = "string", default = "feature_set",
             help = "For table sources, column containing set identifiers."),
        list(name = "set_name_col", type = "string", default = NULL,
             help = "For table sources, optional human-readable set-name column."),
        list(name = "gene_col", type = "string", default = "feature_id",
             help = "For table sources, column containing gene/feature identifiers."),
        list(name = "description_col", type = "string", default = "description",
             help = "For table sources, optional set description column."),
        list(name = "split_by_collection", type = "bool", default = FALSE,
             help = "If TRUE, append detected/declared subcollection to the namespace base."),
        list(name = "overwrite", type = "bool", default = TRUE,
             help = "If FALSE, existing feature sets are skipped instead of replaced."),
        list(name = "strict", type = "bool", default = FALSE,
             help = "If TRUE, error on genes absent from the matrix; otherwise drop absent genes."),
        list(name = "created_by", type = "string", default = NULL,
             help = "Optional creator label stored in feature-set provenance."),
        list(name = "source_id", type = "string", default = NULL,
             help = "Optional source/library identifier stored in feature-set metadata."),
        list(name = "source_version", type = "string", default = NULL,
             help = "Optional source/library version stored in feature-set metadata."),
        list(name = "origin", type = "string", default = "imported",
             help = "Origin label stored in feature-set metadata."),
        list(name = "is_readonly", type = "bool", default = TRUE,
             help = "Whether imported feature sets are registered read-only.")
      ),
      interface_produces = list(
        import_summary = list(
          kind = "obs_table",
          table_type = "feature_set_import_summary",
          description = "One-row summary of parsed/imported/skipped/rejected set counts."
        ),
        import_manifest = list(
          kind = "obs_table",
          table_type = "feature_set_import_manifest",
          description = "One row per parsed feature set with target namespace, overlap counts, and import status."
        ),
        rejected_sets = list(
          kind = "obs_table",
          table_type = "feature_set_import_rejected",
          description = "Feature sets rejected during import, typically because no genes mapped to the matrix."
        )
      )
    ),
    feature_set_namespace_transfer = list(
      op_name = "feature_set_namespace_transfer",
      title = "Feature-Set Namespace Transfer",
      description = "Transfer matrix-scoped feature-set namespaces between comparable matrices using mirror or intersect semantics.",
      intent = c("feature_set", "transfer", "namespace", "matrix", "provenance"),
      requires = list(source_matrix = "matrix", target_matrix = "matrix"),
      produces = list(
        transfer_summary = "obs_table",
        transfer_manifest = "obs_table",
        transfer_rejected = "obs_table"
      ),
      promotable = c("transfer_summary", "transfer_manifest", "transfer_rejected"),
      runner = .wb_runner_feature_set_namespace_transfer,
      inputs = list(),
      params = list(
        list(name = "namespace", type = "string", default = NULL,
             help = "Single source namespace to transfer."),
        list(name = "namespaces", type = "string_vec", default = NULL,
             help = "Optional multiple source namespaces to transfer."),
        list(name = "feature_sets", type = "string_vec", default = NULL,
             help = "Optional feature-set subset within selected source namespaces."),
        list(name = "mode", type = "choice", default = "mirror",
             choices = c("mirror", "intersect"),
             help = "mirror requires identical feature universes; intersect retains only target-valid members and records loss."),
        list(name = "target_namespace", type = "string", default = NULL,
             help = "Optional target namespace override. Defaults to the source namespace."),
        list(name = "overwrite", type = "bool", default = FALSE,
             help = "If FALSE, existing target feature sets are skipped instead of replaced."),
        list(name = "strict", type = "bool", default = TRUE,
             help = "If TRUE, fail when intersect mode rejects any selected set by retention thresholds."),
        list(name = "min_retained_features", type = "int", default = 1, min = 0,
             help = "Minimum target-retained members required to transfer a set."),
        list(name = "min_retained_fraction", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum fraction of source members retained on the target matrix."),
        list(name = "created_by", type = "string", default = NULL,
             help = "Optional created_by metadata for transferred registry rows."),
        list(name = "notes", type = "string", default = NULL,
             help = "Optional provenance note. This op is not for gene-to-peak, peak-to-gene, motif-to-TF, ortholog, or synonym mapping.")
      ),
      interface_produces = list(
        transfer_summary = list(
          kind = "obs_table",
          table_type = "feature_set_transfer_summary",
          description = "Namespace-level summary of transfer mode, matrix compatibility, and transferred/skipped/rejected set counts."
        ),
        transfer_manifest = list(
          kind = "obs_table",
          table_type = "feature_set_transfer_manifest",
          description = "One row per source feature set with source/target matrices, namespaces, retained members, status, and set IDs."
        ),
        transfer_rejected = list(
          kind = "obs_table",
          table_type = "feature_set_transfer_rejected",
          description = "Feature sets rejected during intersect transfer because retained members failed thresholds."
        )
      )
    ),
    cell_set_derive = list(
      op_name = "cell_set_derive",
      title = "Derived Cell Set",
      description = "Materialize a selector-derived or explicitly declared cell universe as a named cell set with lifecycle role/status and manifest tables.",
      intent = c("selection", "provenance", "registry"),
      requires = list(),
      produces = list(manifest = "obs_table", rule_table = "obs_table"),
      promotable = c("manifest", "rule_table"),
      runner = .wb_runner_cell_set_derive,
      inputs = list(),
      params = list(
        list(name = "target_cell_set", type = "string", required = TRUE,
             help = "Name of the derived cell set to create, for example set:universe_b_l1_weight090."),
        list(name = "role", type = "choice", default = "analysis_universe",
             choices = c("core", "annotation", "analysis_universe", "exclusion_set", "endpoint_set", "diagnostic", "temporary"),
             help = "Lifecycle role of the derived set."),
        list(name = "status", type = "choice", default = "candidate",
             choices = c("active", "candidate", "accepted", "superseded", "rejected", "temporary"),
             help = "Lifecycle status controlling interpretation and default visibility."),
        list(name = "source", type = "string", default = "selector_recipe",
             help = "Source/provenance label stored on membership rows."),
        list(name = "created_by", type = "string", default = NULL,
             help = "Optional creator label."),
        list(name = "description", type = "string", default = NULL,
             help = "Human-readable derivation rationale."),
        list(name = "recipe", type = "list", default = NULL,
             help = "Optional selector recipe stored with the derived cell set."),
        list(name = "overwrite", type = "bool", default = TRUE,
             help = "If TRUE, replace existing membership for the target set; if FALSE, add cells to it.")
      ),
      interface_produces = list(
        manifest = list(
          kind = "obs_table",
          table_type = "derived_cell_set_manifest",
          entity_kind = "cell_set",
          description = "One-row lifecycle manifest for the named derived cell set, including counts, role, status, recipe availability, and source summary."
        ),
        rule_table = list(
          kind = "obs_table",
          table_type = "derived_cell_set_rules",
          entity_kind = "cell_set_rule",
          description = "Ordered per-rule derivation audit table with input/output/removal counts and source fields."
        )
      )
    ),
    metadata_cell_vector = list(
      op_name = "metadata_cell_vector",
      title = "Metadata Cell Vector",
      description = "Materialize an imported cell metadata column as a typed, provenance-backed cell vector.",
      intent = c("metadata", "cell_vector", "provenance", "technical_diagnostics"),
      requires = list(), produces = list(vector = "cell_vector"), promotable = c("vector"),
      runner = .wb_runner_metadata_cell_vector,
      inputs = list(),
      params = list(
        list(name = "source_column", type = "metadata_field", required = TRUE, help = "Imported metadata name or explicit wb_ref_metadata_field() reference to materialize."),
        list(name = "cell_set", type = "cell_set", default = "all", help = "Named bundle cell set defining the vector universe."),
        list(name = "value_type", type = "choice", default = "auto", choices = c("categorical", "continuous", "auto"), help = "Explicit vector value type; auto records a conservative native-type decision."),
        list(name = "missing_policy", type = "choice", default = "error", choices = c("error", "drop", "as_category"), help = "How missing values are handled before vector materialization."),
        list(name = "missing_label", type = "string", default = "__MISSING__", help = "Replacement label when missing_policy='as_category'."),
        list(name = "vector_name", type = "string", required = TRUE, help = "Stable promoted vector name; collision protection is controlled by overwrite."),
        list(name = "overwrite", type = "bool", default = FALSE, help = "Allow a new immutable artifact to supersede an existing vector with the same name.")
      ),
      interface_produces = list(vector = list(kind = "cell_vector", description = "Typed per-cell vector materialized from imported bundle metadata."))
    ),
    slingshot_adopt = list(
      op_name = "slingshot_adopt",
      title = "Adopt an existing Slingshot fit",
      description = "Adopt a checksummed source-derived Slingshot fit as a complete trajectory family without refitting it.",
      intent = c("trajectory", "adoption", "provenance", "source_derived"),
      requires = list(model = "model_ref"),
      produces = list(
        pseudotime = "cell_vector_family",
        lineage_weights = "cell_vector_family",
        curves = "path_2d_family",
        model = "model_ref",
        adoption_summary = "obs_table"
      ),
      promotable = c("pseudotime", "lineage_weights", "curves", "model", "adoption_summary"),
      runner = .wb_runner_slingshot_adopt,
      inputs = list(model = list(required = TRUE, kind = "model_ref")),
      params = list(
        list(name = "source", type = "entity_ref", required = TRUE,
             help = "Registered external_source reference for the object from which the selected Slingshot fit was extracted.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector_family", value_kind = "continuous", key = "lineage_id",
          description = "Source-derived lineage-specific pseudotime values; no refit is performed."
        ),
        lineage_weights = list(
          kind = "cell_vector_family", value_kind = "continuous", key = "lineage_id",
          family_kind = "trajectory_membership_weight", engine = "slingshot", range = c(0, 1),
          description = "Source-derived Slingshot lineage membership weights; no refit is performed."
        ),
        curves = list(
          kind = "path_2d_family", key = "lineage_id",
          description = "Source-derived two-dimensional Slingshot lineage curves."
        ),
        model = list(
          kind = "model_ref",
          description = "Contained source-derived Slingshot model bound to the adopted trajectory fit family."
        ),
        adoption_summary = list(
          kind = "obs_table", table_type = "slingshot_adoption_summary",
          description = "Source checksum, subobject identity, coordinate-alignment result, fit identity, dimensions, and explicit external-execution boundary."
        )
      )
    ),
    model_bound_latent_union = list(
      op_name = "model_bound_latent_union",
      title = "Model-Bound Latent-Space Union",
      description = "Combine disjoint fitted-reference and projected-query latent coordinates only when both are bound to the same retained PeakVI or scVI model identity.",
      intent = c("latent", "integration", "projection", "provenance"),
      requires = list(
        reference_space = "space",
        query_space = "space",
        model = "model_ref",
        projection_summary = "obs_table"
      ),
      coverage = list(
        reference_space = "reference_only",
        query_space = "reference_only",
        model = "reference_only",
        projection_summary = "reference_only"
      ),
      produces = list(space = "space", union_summary = "obs_table"),
      promotable = c("union_summary"),
      runner = .wb_runner_model_bound_latent_union,
      inputs = list(
        reference_space = list(required = TRUE, kind = "space"),
        query_space = list(required = TRUE, kind = "space"),
        model = list(required = TRUE, kind = "model_ref"),
        projection_summary = list(required = TRUE, kind = "obs_table")
      ),
      params = list(
        list(name = "space_id_out", type = "string", default = "model_bound_latent_union",
             help = "New durable space identity for the unchanged row-wise coordinate union.")
      ),
      interface_produces = list(
        space = list(
          kind = "space",
          description = "Durable high-dimensional space containing fitted reference and projected query coordinates in canonical cell order."
        ),
        union_summary = list(
          kind = "obs_table",
          table_type = "model_bound_latent_union_summary",
          description = "Model, source-space, output-space, cell-count, dimension, disjointness, and no-transformation record."
        )
      )
    )
  )
  catalog
}
