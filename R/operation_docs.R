# Generated from the runtime operation interface catalog; do not edit by hand.
# Source: .wb_op_catalog() via wb_op_interface().
# Regenerate: Rscript inst/dev/generate_operation_docs.R

#' @name wb_op_feature_set_import
#' @aliases wb_op_feature_set_import
#' @description Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param source_path Path to GMT, RDS list/data.frame, or CSV-like table source.
#' @param source_format Input parser. auto infers from file extension.
#' @param table Optional in-memory feature-set source table.
#' @param sets Optional named in-memory feature-set list.
#' @param namespace Target feature-set namespace base label.
#' @param collection Optional collection label recorded in import manifests.
#' @param subcollection Optional subcollection label; used for namespace splitting when requested.
#' @param species Species/organism label recorded in feature-set metadata.
#' @param organism Organism label recorded with the imported feature-set namespace.
#' @param gene_id_type Identifier type expected in source genes, for example gene_symbol.
#' @param set_id_col For table sources, column containing set identifiers.
#' @param set_name_col For table sources, optional human-readable set-name column.
#' @param gene_col For table sources, column containing gene/feature identifiers.
#' @param description_col For table sources, optional set description column.
#' @param split_by_collection If TRUE, append detected/declared subcollection to the namespace base.
#' @param overwrite If FALSE, existing feature sets are skipped instead of replaced.
#' @param strict If TRUE, error on genes absent from the matrix; otherwise drop absent genes.
#' @param created_by Optional actor label recorded in provenance.
#' @param source_id Optional source/library identifier stored in feature-set metadata.
#' @param source_version Optional source/library version stored in feature-set metadata.
#' @param origin Human-readable origin label recorded for imported source material.
#' @param is_readonly Whether imported feature sets are marked read-only after registration.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$import_summary` (`obs_table`): One-row summary of parsed/imported/skipped/rejected set counts.; `outputs$import_manifest` (`obs_table`): One row per parsed feature set with target namespace, overlap counts, and import status.; `outputs$rejected_sets` (`obs_table`): Feature sets rejected during import, typically because no genes mapped to the matrix.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_metadata_cell_vector
#' @aliases wb_op_metadata_cell_vector
#' @description Materialize an imported cell metadata column as a typed, provenance-backed cell vector.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param source_column Imported metadata name or explicit wb_ref_metadata_field() reference to materialize.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param value_type Explicit vector value type; auto records a conservative native-type decision.
#' @param missing_policy How missing values are handled before vector materialization.
#' @param missing_label Replacement label when missing_policy='as_category'.
#' @param vector_name Stable promoted vector name; collision protection is controlled by overwrite.
#' @param overwrite Allow a new immutable artifact to supersede an existing vector with the same name.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$vector` (`cell_vector`): Typed per-cell vector materialized from imported bundle metadata.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_slingshot_adopt
#' @aliases wb_op_slingshot_adopt
#' @description Adopt a checksummed source-derived Slingshot fit as a complete trajectory family without refitting it.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param model_ref Typed `model_ref` primitive required by this engine-specific helper.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param source Registered external_source reference for the object from which the selected Slingshot fit was extracted.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector_family`): Source-derived lineage-specific pseudotime values; no refit is performed.; `outputs$lineage_weights` (`cell_vector_family`): Source-derived Slingshot lineage membership weights; no refit is performed.; `outputs$curves` (`path_2d_family`): Source-derived two-dimensional Slingshot lineage curves.; `outputs$model` (`model_ref`): Contained source-derived Slingshot model bound to the adopted trajectory fit family.; `outputs$adoption_summary` (`obs_table`): Source checksum, subobject identity, coordinate-alignment result, fit identity, dimensions, and explicit external-execution boundary.. Promotion eligibility is declared by the operation catalog.
NULL

