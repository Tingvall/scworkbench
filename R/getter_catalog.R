# Semantic catalog for safe bundle getter / inspection functions.

.wb_getter_catalog_entries <- function() {
  list(
    list(
      function_name = "wb_status",
      title = "Bundle Status",
      category = "bundle",
      description = "Summarize bundle health and high-level registry counts.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("check whether a bundle is readable", "get a quick bundle overview")
    ),
    list(
      function_name = "wb_manifest",
      title = "Bundle Manifest",
      category = "bundle",
      description = "Read the atomically published authoritative manifest, or request an explicitly reconstructed diagnostic registry view.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "view"),
      use_when = c("inspect durable bundle identity and current state", "diagnose manifest/registry publication disagreement")
    ),
    list(
      function_name = "wb_bundle_overview",
      title = "Bundle Overview",
      category = "bundle",
      description = "Summarize bundle identity, validation state, registries, artifact counts, and provenance heads for read-only clients.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "validate"),
      use_when = c("build collaborator dashboard", "inspect bundle readiness without direct SQL")
    ),
    list(
      function_name = "wb_bundle_schema",
      title = "Bundle Schema",
      category = "bundle",
      description = "Inspect available SQLite schema objects in the bundle.",
      returns = "data.frame/list",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("debug bundle tables", "inspect schema capabilities")
    ),
    list(
      function_name = "wb_list",
      title = "Registry List",
      category = "bundle",
      description = "List common registry tables such as matrices, features, spaces, or datasets.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "what"),
      use_when = c("quickly inspect registry content")
    ),
    list(
      function_name = "wb_cells",
      title = "Cell IDs",
      category = "cells",
      description = "Return cell IDs in canonical bundle order, optionally restricted to a cell set or dataset.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "cell_set", "dataset_id"),
      use_when = c("get cells for an analysis", "resolve a cell set to cell IDs")
    ),
    list(
      function_name = "wb_cell_sets",
      title = "Cell Sets",
      category = "cells",
      description = "List available cell sets in a bundle.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "include_history"),
      use_when = c("find available subsets", "choose cell_set input for an op")
    ),
    list(
      function_name = "wb_resolve_cell_set",
      title = "Resolve Cell Set",
      category = "cells",
      description = "Resolve a cell-set selector into concrete cell IDs.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "cell_set"),
      use_when = c("expand set:<name>", "verify effective cell IDs")
    ),
    list(
      function_name = "wb_meta",
      title = "Cell Metadata",
      category = "cells",
      description = "Read cell-level metadata for selected cells and columns.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "cells", "cols", "dataset_id"),
      use_when = c("inspect annotations", "fetch labels or covariates")
    ),
    list(
      function_name = "wb_cell_metadata_columns",
      title = "Cell Metadata Columns",
      category = "cells",
      description = "List cell metadata columns with type, missingness, cardinality, and display hints for clients.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "summarize", "max_distinct_for_grouping"),
      use_when = c("choose metadata coloring columns", "avoid direct SQLite metadata introspection")
    ),
    list(
      function_name = "wb_cell_coverage",
      title = "Cell Coverage",
      category = "cells",
      description = "Summarize which cells are covered by matrices, spaces, and sets.",
      returns = "data.frame/list",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("check data coverage before running ops")
    ),
    list(
      function_name = "wb_cells_with_matrix",
      title = "Cells With Matrix",
      category = "matrices",
      description = "List cells available for a given matrix.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id"),
      use_when = c("intersect cells with matrix coverage")
    ),
    list(
      function_name = "wb_cells_with_space",
      title = "Cells With Space",
      category = "spaces",
      description = "List cells available for a given space.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "space_id", "dims"),
      use_when = c("intersect cells with embedding coverage")
    ),
    list(
      function_name = "wb_matrices",
      title = "Matrices",
      category = "matrices",
      description = "List matrices available in the bundle.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "include_history"),
      use_when = c("choose matrix input for an op")
    ),
    list(
      function_name = "wb_matrix_info",
      title = "Matrix Info",
      category = "matrices",
      description = "Read matrix registry metadata, optionally for one matrix.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id"),
      use_when = c("inspect matrix type, dimensions, and metadata")
    ),
    list(
      function_name = "wb_matrix_fragments",
      title = "Matrix Fragments",
      category = "matrices",
      description = "List physical storage fragments backing a logical matrix.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id"),
      use_when = c("debug fragmented matrix storage")
    ),
    list(
      function_name = "wb_matrix_resolve",
      title = "Resolve Matrix",
      category = "matrices",
      description = "Resolve matrix fragments to absolute storage paths.",
      returns = "data.frame/list",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id"),
      use_when = c("inspect physical matrix payload locations")
    ),
    list(
      function_name = "wb_matrix",
      title = "Matrix Handle",
      category = "matrices",
      description = "Open a matrix handle for a matrix ID.",
      returns = "matrix-like object",
      payload_level = "payload",
      arguments = c("bundle", "matrix_id"),
      use_when = c("advanced direct matrix access")
    ),
    list(
      function_name = "wb_slice",
      title = "Matrix Slice",
      category = "matrices",
      description = "Read a feature-by-cell matrix slice.",
      returns = "matrix",
      payload_level = "payload",
      arguments = c("bundle", "matrix_id", "features", "cells"),
      use_when = c("read expression/accessibility block", "feed custom analysis")
    ),
    list(
      function_name = "wb_matrix_read_feature",
      title = "Read One Feature",
      category = "matrices",
      description = "Read one feature vector across requested cells.",
      returns = "numeric vector",
      payload_level = "payload",
      arguments = c("bundle", "matrix_id", "feature_id", "cell_ids"),
      use_when = c("inspect one gene or peak across cells")
    ),
    list(
      function_name = "wb_matrix_read_features",
      title = "Read Features",
      category = "matrices",
      description = "Read multiple features across cells from a logical matrix.",
      returns = "matrix",
      payload_level = "payload",
      arguments = c("bundle", "matrix_id", "features", "cells"),
      use_when = c("inspect marker panel", "read feature block")
    ),
    list(
      function_name = "wb_vector",
      title = "Feature Vector",
      category = "matrices",
      description = "Get a single feature vector across cells.",
      returns = "numeric vector",
      payload_level = "payload",
      arguments = c("bundle", "matrix_id", "feature_id", "cells"),
      use_when = c("plot one gene", "threshold one feature")
    ),
    list(
      function_name = "wb_features",
      title = "Features",
      category = "features",
      description = "Read feature registry rows, optionally filtered by matrix or feature type.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id", "feature_type"),
      use_when = c("inspect feature metadata", "find available genes or peaks")
    ),
    list(
      function_name = "wb_feature_ids",
      title = "Feature IDs",
      category = "features",
      description = "Get feature IDs in canonical order for a matrix.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id", "feature_type"),
      use_when = c("verify feature availability", "choose genes for scoring")
    ),
    list(
      function_name = "wb_search_features",
      title = "Search Features",
      category = "features",
      description = "Search feature IDs or feature metadata.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "query", "matrix_id"),
      use_when = c("find matching genes/features by text")
    ),
    list(
      function_name = "wb_feature_sets",
      title = "Feature Sets",
      category = "feature_sets",
      description = "List feature sets and namespaces in the bundle.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "matrix_id", "namespace", "organism", "origin", "include_history"),
      use_when = c("find gene-set libraries", "choose namespace for enrichment or dynamics")
    ),
    list(
      function_name = "wb_feature_set_info",
      title = "Feature Set Info",
      category = "feature_sets",
      description = "Read metadata for one feature set.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "feature_set", "matrix_id"),
      use_when = c("inspect gene-set provenance and metadata")
    ),
    list(
      function_name = "wb_feature_set_get",
      title = "Feature Set Members",
      category = "feature_sets",
      description = "Get feature IDs from one feature set.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "feature_set", "matrix_id"),
      use_when = c("inspect gene-set members", "debug missing genes")
    ),
    list(
      function_name = "wb_spaces",
      title = "Spaces",
      category = "spaces",
      description = "List spaces in the bundle.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "include_history"),
      use_when = c("choose embedding or latent space for an op")
    ),
    list(
      function_name = "wb_space_info",
      title = "Space Info",
      category = "spaces",
      description = "Read space registry metadata, optionally for one space.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "space_id"),
      use_when = c("inspect space dimensions and source")
    ),
    list(
      function_name = "wb_space",
      title = "Space Coordinates",
      category = "spaces",
      description = "Read coordinates for a space, optionally restricted to cells and dimensions.",
      returns = "matrix/data.frame",
      payload_level = "payload",
      arguments = c("bundle", "space_id", "cells", "dims"),
      use_when = c("load UMAP/latent coordinates", "plot or fit geometry")
    ),
    list(
      function_name = "wb_spaces_with_model",
      title = "Spaces With Model",
      category = "spaces",
      description = "List space IDs that have a stored projection model.",
      returns = "character vector",
      payload_level = "metadata",
      arguments = c("bundle", "model_type", "include_history"),
      use_when = c("choose UMAP model for projection")
    ),
    list(
      function_name = "wb_space_model",
      title = "Space Model Metadata",
      category = "spaces",
      description = "Get model metadata for a space.",
      returns = "data.frame/list",
      payload_level = "metadata",
      arguments = c("bundle", "space_id"),
      use_when = c("inspect fitted UMAP or projection model metadata")
    ),
    list(
      function_name = "wb_space_model_path",
      title = "Space Model Path",
      category = "spaces",
      description = "Get absolute path to a stored model file for a space.",
      returns = "character",
      payload_level = "metadata",
      arguments = c("bundle", "space_id"),
      use_when = c("locate model payload file")
    ),
    list(
      function_name = "wb_art_list",
      title = "Artifacts",
      category = "artifacts",
      description = "List current promoted artifacts by default, optionally filtered by type or expanded to retained history.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "type", "include_history"),
      use_when = c("find promoted outputs", "choose artifact for plotting or loading")
    ),
    list(
      function_name = "wb_entity_lifecycle",
      title = "Durable Entity Lifecycle",
      category = "provenance",
      description = "List current, superseded, rejected, retracted, and ephemeral durable entity identities without reading physical storage tables.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "entity_kind", "entity_id", "lifecycle_state", "include_history"),
      use_when = c("distinguish current claims from historical evidence", "audit immutable identity state")
    ),
    list(
      function_name = "wb_entity_supersessions",
      title = "Entity Supersessions",
      category = "provenance",
      description = "List explicit SUPERSEDES relationships between immutable durable identities.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("trace claim replacement", "render historical lifecycle relationships")
    ),
    list(
      function_name = "wb_list_trajectory_models",
      title = "Trajectory Model Inventory",
      category = "artifacts",
      description = "List promoted model_ref trajectory candidates with engine, provenance, and optional pseudotime coverage.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "inspect_payload"),
      use_when = c("choose trajectory model", "review trajectory candidates for reports or agents")
    ),
    list(
      function_name = "wb_trajectory_lineage_weights",
      title = "Trajectory Lineage Weights",
      category = "artifacts",
      description = "Load Slingshot lineage membership weights as a cell_vector_family from a promoted lineage_weights artifact, promoted sibling trajectory artifact, or in-memory Slingshot model_ref fallback.",
      returns = "wb_primitive cell_vector_family",
      payload_level = "payload",
      arguments = c("bundle", "model_ref", "pseudotime_artifact", "lineage_weights_artifact"),
      use_when = c("restrict trajectory universes by lineage membership", "filter cells by Slingshot lineage weight", "derive claim-supporting trajectory cell sets")
    ),
    list(
      function_name = "wb_trajectory_fit_info",
      title = "Trajectory Fit Identity",
      category = "artifacts",
      description = "Inspect the trajectory_fit_id, engine, lineage keys, and available cell universe metadata for a trajectory primitive or promoted artifact.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "x", "runs"),
      use_when = c("audit trajectory fit-family identity", "check whether trajectory artifacts can be combined")
    ),
    list(
      function_name = "wb_trajectory_assert_fit_compatible",
      title = "Trajectory Fit Compatibility Assertion",
      category = "artifacts",
      description = "Fail loudly when trajectory artifacts come from different trajectory fit families; shared labels such as L1 are not sufficient compatibility evidence.",
      returns = "invisible data.frame or error",
      payload_level = "metadata",
      arguments = c("bundle", "...", "runs", "allow_legacy"),
      use_when = c("validate pseudotime, weights, model, and path compatibility", "prevent cross-fit lineage-label mixing")
    ),
    list(
      function_name = "wb_art_load",
      title = "Load Artifact",
      category = "artifacts",
      description = "Load a promoted artifact as a primitive.",
      returns = "wb_primitive",
      payload_level = "payload",
      arguments = c("bundle", "artifact_id", "expected_kind"),
      use_when = c("load promoted output for downstream analysis")
    ),
    list(
      function_name = "wb_art_table_info",
      title = "Table Artifact Info",
      category = "artifacts",
      description = "Read metadata for a promoted table artifact.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id"),
      use_when = c("inspect table type before slicing")
    ),
    list(
      function_name = "wb_art_table_slice",
      title = "Table Artifact Slice",
      category = "artifacts",
      description = "Read a bounded row slice from a promoted feature_table or obs_table.",
      returns = "data.frame",
      payload_level = "payload",
      arguments = c("bundle", "artifact_id", "filters", "limit"),
      use_when = c("preview artifact table without full load", "filter promoted dynamics tables")
    ),
    list(
      function_name = "wb_art_table_distinct",
      title = "Table Artifact Distinct Values",
      category = "artifacts",
      description = "List distinct values from one promoted table artifact column.",
      returns = "vector",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id", "column", "filters", "limit"),
      use_when = c("enumerate lineage IDs", "find feature sets in an artifact")
    ),
    list(
      function_name = "wb_art_identity_card",
      title = "Artifact Identity Card",
      category = "artifacts",
      description = "Summarize artifact identity, provenance, labels, and display hints.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id"),
      use_when = c("explain an artifact to an agent or user")
    ),
    list(
      function_name = "wb_art_birth_certificate",
      title = "Artifact Birth Certificate",
      category = "artifacts",
      description = "Read provenance/birth metadata for a promoted artifact.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id"),
      use_when = c("trace artifact provenance")
    ),
    list(
      function_name = "wb_art_dependencies",
      title = "Artifact Dependencies",
      category = "artifacts",
      description = "Get dependency relationships for an artifact.",
      returns = "data.frame/list",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id"),
      use_when = c("inspect downstream/upstream artifact relationships")
    ),
    list(
      function_name = "wb_art_trajectory_related",
      title = "Related Trajectory Artifacts",
      category = "artifacts",
      description = "Find trajectory-related sibling artifacts for a source artifact.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id"),
      use_when = c("navigate between trajectory DE, smooth, and signature artifacts")
    ),
    list(
      function_name = "wb_list_cell_vectors",
      title = "Cell Vectors",
      category = "vectors",
      description = "List available cell vectors from artifacts and optionally session outputs.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "session", "include_session"),
      use_when = c("choose vector input", "find UCell/module score artifacts")
    ),
    list(
      function_name = "wb_list_vector_sources",
      title = "Vector Sources",
      category = "vectors",
      description = "List vector-like sources available for UI/agent selection.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "runs"),
      use_when = c("discover cell_vector and cell_vector_family inputs")
    ),
    list(
      function_name = "wb_read_cell_vector",
      title = "Read Cell Vector",
      category = "vectors",
      description = "Read a scalar cell vector for a requested set of cells.",
      returns = "named vector",
      payload_level = "payload",
      arguments = c("bundle", "vector_id", "cell_ids"),
      use_when = c("read promoted per-cell values")
    ),
    list(
      function_name = "wb_read_cell_vector_family",
      title = "Read Cell Vector Family Member",
      category = "vectors",
      description = "Read one key/member from a cell_vector_family for requested cells.",
      returns = "named vector",
      payload_level = "payload",
      arguments = c("bundle", "vector_id", "key", "cell_ids"),
      use_when = c("read one UCell/module/chromVAR signal")
    ),
    list(
      function_name = "wb_cell_vector_load",
      title = "Load Cell Vector Primitive",
      category = "vectors",
      description = "Load a cell vector primitive by artifact or session reference.",
      returns = "wb_primitive",
      payload_level = "payload",
      arguments = c("bundle", "session", "vector_id", "expected_kind"),
      use_when = c("resolve vector reference for plotting or ops")
    ),
    list(
      function_name = "wb_motif_libraries",
      title = "Motif Libraries",
      category = "motifs",
      description = "List registered motif libraries.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("inspect available motif catalogs")
    ),
    list(
      function_name = "wb_motifs",
      title = "Motifs",
      category = "motifs",
      description = "List motifs, optionally filtered by library.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "library_id"),
      use_when = c("find motif IDs for regulatory analysis")
    ),
    list(
      function_name = "wb_motif_match_sets",
      title = "Motif Match Sets",
      category = "motifs",
      description = "List motif match sets available for peak features.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("choose motif-to-peak mapping for chromVAR")
    ),
    list(
      function_name = "wb_motif_match_get",
      title = "Motif Match Membership",
      category = "motifs",
      description = "Load motif match membership rows for a match set.",
      returns = "data.frame",
      payload_level = "payload",
      arguments = c("bundle", "match_set_id"),
      use_when = c("inspect motif-feature memberships")
    ),
    list(
      function_name = "wb_prov_list_heads",
      title = "Provenance Heads",
      category = "provenance",
      description = "List persisted provenance snapshot heads.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("find saved analysis DAGs")
    ),
    list(
      function_name = "wb_prov_dag",
      title = "Provenance DAG",
      category = "provenance",
      description = "Read one snapshot-local persisted provenance DAG.",
      returns = "list/data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "snapshot_id"),
      use_when = c("inspect one saved analysis snapshot", "reconstruct analysis steps within one snapshot")
    ),
    list(
      function_name = "wb_prov_bundle_dag",
      title = "Bundle-Level Composed Provenance DAG",
      category = "provenance",
      description = "Compose persisted runs, artifacts, snapshots, artifact inputs, outputs, and registry mutations across all bundle provenance snapshots.",
      returns = "list/data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "snapshot_id", "run_id", "artifact_id", "direction", "max_depth", "include_snapshots", "include_registry_mutations"),
      use_when = c("render a connected artifact/run lineage across promotions", "show bundle-level provenance in Shiny or agents", "trace analysis chains that continue from promoted artifacts")
    ),
    list(
      function_name = "wb_target_reproduction_plan",
      title = "Target Reproduction Plan",
      category = "provenance",
      description = "Resolve an artifact, matrix, space, model, or run DAG node into its minimal cross-snapshot replay closure.",
      returns = "wb_target_reproduction_plan",
      payload_level = "metadata",
      arguments = c("bundle", "target"),
      use_when = c("export the minimum reproducible path to a durable result", "distinguish imported source state from engine-reproducible output")
    ),
    list(
      function_name = "wb_target_emit_r_script",
      title = "Target Reproduction Script",
      category = "provenance",
      description = "Emit a replay-and-promotion script for a target reproduction plan and writable execution clone.",
      returns = "character",
      payload_level = "metadata",
      arguments = c("plan", "execution_bundle_dir"),
      use_when = c("hand off a target-specific reproducible analysis path")
    ),
    list(
      function_name = "wb_prov_replay_equivalence_results",
      title = "Replay Equivalence Results",
      category = "provenance",
      description = "List target-reproduction equivalence results with separate original and replayed payload SHA-256 identities.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "replay_snapshot_id"),
      use_when = c("audit scientific replay equality separately from stored-payload integrity")
    ),
    list(
      function_name = "wb_prov_artifact_lineage",
      title = "Composed Artifact Lineage",
      category = "provenance",
      description = "Return an upstream, downstream, or bidirectional composed provenance subgraph centered on one promoted artifact.",
      returns = "list/data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "artifact_id", "direction", "max_depth"),
      use_when = c("explain one artifact in context", "find upstream source artifacts and downstream dependents")
    ),
    list(
      function_name = "wb_prov_run_details",
      title = "Provenance Run Details",
      category = "provenance",
      description = "Inspect one persisted run from provenance.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "run_id"),
      use_when = c("explain exact inputs and params for one run")
    ),
    list(
      function_name = "wb_run_history",
      title = "Run History",
      category = "provenance",
      description = "Flatten persisted provenance snapshots into a chronological run-history table.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("bundle", "snapshot_id"),
      use_when = c("build run history timeline", "inspect promoted analysis steps")
    ),
    list(
      function_name = "wb_session_dag",
      title = "Session DAG",
      category = "session",
      description = "Inspect an in-memory session DAG.",
      returns = "data.frame/list",
      payload_level = "metadata",
      arguments = c("session", "bundle", "include_artifacts", "include_active"),
      use_when = c("inspect current session runs")
    ),
    list(
      function_name = "wb_session_dag_run_details",
      title = "Session DAG Run Details",
      category = "session",
      description = "Inspect one run node from an in-memory session DAG.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("session", "run_id", "bundle"),
      use_when = c("explain one current session run")
    ),
    list(
      function_name = "wb_session_view",
      title = "Session Staging View",
      category = "session",
      description = "Open the session-local bundle overlay containing staged outputs before promotion.",
      returns = "scworkbench_bundle",
      payload_level = "data",
      arguments = c("session"),
      use_when = c("inspect staged matrix or space output before promotion", "continue session-local analysis without mutating the portable bundle")
    ),
    list(
      function_name = "wb_nav_entities",
      title = "Navigation Entities",
      category = "navigation",
      description = "List entities that can be navigated from an artifact-backed source.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("source", "bundle", "entity_kind", "lineage_id"),
      use_when = c("find clickable genes, lineages, or feature sets")
    ),
    list(
      function_name = "wb_nav_targets",
      title = "Navigation Targets",
      category = "navigation",
      description = "List compatible navigation targets for a selected source/entity.",
      returns = "data.frame",
      payload_level = "metadata",
      arguments = c("source", "bundle", "entity", "lineage_id"),
      use_when = c("find next plot/table from an artifact")
    ),
    list(
      function_name = "wb_nav_handoff",
      title = "Navigation Handoff",
      category = "navigation",
      description = "Resolve a navigation target into a client-agnostic handoff payload.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("source", "target", "bundle", "entity", "lineage_id"),
      use_when = c("open linked plot from selected artifact entity")
    ),
    list(
      function_name = "wb_client_discover",
      title = "Client Discovery",
      category = "client",
      description = "Client facade for discovering bundle state and available operations.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle"),
      use_when = c("initialize UI or agent context")
    ),
    list(
      function_name = "wb_client_inspect",
      title = "Client Inspect",
      category = "client",
      description = "Client facade for inspecting session and bundle runtime state.",
      returns = "list",
      payload_level = "metadata",
      arguments = c("bundle", "session"),
      use_when = c("summarize current analysis state")
    ),
    list(
      function_name = "wb_client_load",
      title = "Client Load",
      category = "client",
      description = "Client facade for loading primitives by reference.",
      returns = "wb_primitive",
      payload_level = "payload",
      arguments = c("bundle", "ref", "session"),
      use_when = c("load selected artifact or session output")
    ),
    list(
      function_name = "wb_client_load_table",
      title = "Client Load Table",
      category = "client",
      description = "Client facade for loading and wrangling references into normalized tables.",
      returns = "data.frame",
      payload_level = "payload",
      arguments = c("bundle", "ref", "session", "key"),
      use_when = c("preview primitive data in a table")
    )
  )
}

.wb_getter_catalog_semantic_clean <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) .wb_getter_catalog_semantic_clean(as.list(x[i, , drop = FALSE]))))
  if (is.list(x)) return(lapply(x, .wb_getter_catalog_semantic_clean))
  if (is.factor(x)) return(as.character(x))
  if (length(x) == 0L) return(list())
  if (length(x) == 1L && is.na(x)) return(NULL)
  x
}

#' Export Getter Catalog As Semantic Metadata
#'
#' Returns a structured, JSON-friendly description of safe bundle getter and
#' inspection functions. This is intended for agents, documentation generators,
#' and semantic indexes that need to discover bundle state before choosing ops.
#'
#' @return A named list with one record per getter.
#' @export
wb_getter_catalog_semantic <- function() {
  entries <- .wb_getter_catalog_entries()
  entries <- lapply(entries, function(x) {
    x$mutates <- FALSE
    x
  })
  .wb_getter_catalog_semantic_clean(list(
    schema_version = "scworkbench.getter_catalog.semantic.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    getter_count = length(entries),
    getters = entries
  ))
}

.wb_getter_catalog_reference_lines <- function(catalog) {
  getters <- catalog$getters %||% list()
  lines <- c(
    "# scworkbench Getter Catalog",
    "",
    "<!-- Generated from wb_getter_catalog_semantic(); do not edit getter entries by hand. -->",
    "",
    paste0("Generated at: ", as.character(catalog$generated_at %||% "")),
    "",
    paste0("Getter count: ", as.integer(catalog$getter_count %||% length(getters))),
    "",
    "This document summarizes safe bundle getter and inspection functions for humans, agents, and semantic indexing.",
    "The machine-readable companion is `docs/getter_catalog_semantic.json`.",
    ""
  )
  by_cat <- split(getters, vapply(getters, function(x) as.character(x$category %||% "misc")[1], character(1)))
  for (cat_name in sort(names(by_cat))) {
    lines <- c(lines, paste0("## ", cat_name), "")
    for (g in by_cat[[cat_name]]) {
      args <- paste(as.character(g$arguments %||% character(0)), collapse = ", ")
      use_when <- as.character(g$use_when %||% character(0))
      lines <- c(
        lines,
        paste0("### `", as.character(g$function_name %||% "")[1], "`"),
        "",
        paste0("Title: ", as.character(g$title %||% "")[1]),
        "",
        paste0("Description: ", as.character(g$description %||% "")[1]),
        "",
        paste0("Returns: ", as.character(g$returns %||% "")[1]),
        "",
        paste0("Payload level: ", as.character(g$payload_level %||% "")[1]),
        "",
        paste0("Arguments: ", if (nzchar(args)) args else "(none)"),
        "",
        "Use when:"
      )
      lines <- c(lines, if (length(use_when)) paste0("- ", use_when) else "- (unspecified)", "")
    }
  }
  lines
}

#' Write Getter Catalog Reference Files
#'
#' Writes a human-readable markdown reference and/or machine-readable JSON
#' export from the semantic getter catalog.
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the semantic getter catalog list.
#' @export
wb_write_getter_catalog_reference <- function(path_md = "docs/getter_catalog_reference.md",
                                              path_json = "docs/getter_catalog_semantic.json") {
  catalog <- wb_getter_catalog_semantic()
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    writeLines(.wb_getter_catalog_reference_lines(catalog), con = path_md, useBytes = TRUE)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "getter catalog semantic export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}
