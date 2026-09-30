# Installed declaration recipes

Frozen accepted declarations, validated using wb_operation_pack_manifest_validate(). These are manifest-only recipes, not installed handlers, scientific endorsements or additional scaffold options. Edit package/namespace/entry point/qualified name consistently. Preserve dependencies, admitted axes and complete output closure when adapting a recipe. Never load a recipe as a pack without implementing and testing its runner.

The normative shapes and numerical/empty/NA ceilings are shipped, not hidden in core source:

```r
schema <- system.file('protocol', 'operation-pack-v3.schema.json', package='scworkbench')
recipe <- system.file('sdk', 'operation-packs', 'recipes', '<filename>.json', package='scworkbench')
definition <- wb_operation_pack_manifest_validate(recipe)$manifest$operations[[1]]
# Inspect definition$inputs, declaration-specific grants, dimension_policies, outputs and promotion_closure.
```

Runtime family/derived-fitted/sparse/relation declarations are invocation-scoped writer calls, not author-created seals. See callbacks.json for exact declare-before-write signatures. Model tree finish closes the complete linkage; a receipt hash never replaces a finished handle. Core enforces the declared policy. Empty and missing values depend on the selected declaration; do not generalize them from the scalar reference.

## ordinary_io

Declare **inputs, outputs**. Invoke `readers[[input]] (); matrix reader(features=NULL,cells=NULL); writers$write_{matrix,space,space_2d,model_ref,path_2d_family,space_path_family}(name,value,semantic_metadata=list()); writers$write_terminal_primitive(name,value,semantic_metadata=list())`.

Authenticated input descriptor and output allocation; symbolic constructors are not computed output payloads.
Read copied declared input; each required output exactly once; writer must match kind/profile/category tuple.
Declared dimensions and profile; do not infer full materialization is bounded.
Complete promotion closure and core-created receipt before publication.

Python runtime: supported for ordinary 11-kind IO; advanced policies are separate entries. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [02-read_matrix_model.json](recipes/02-read_matrix_model.json), [03-fit_derived_axis_model.json](recipes/03-fit_derived_axis_model.json), [04-fit_sibling_model.json](recipes/04-fit_sibling_model.json), [05-adopt_external_state.json](recipes/05-adopt_external_state.json), [06-derived_subset.json](recipes/06-derived_subset.json), [07-derived_union.json](recipes/07-derived_union.json), [08-standalone_sparse_family.json](recipes/08-standalone_sparse_family.json), [09-sealed_relation_family.json](recipes/09-sealed_relation_family.json), [10-bounded_family.json](recipes/10-bounded_family.json), [11-ancestry_family.json](recipes/11-ancestry_family.json), [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json), [26-chromvar.json](recipes/26-chromvar.json)

## typed_slices

Declare **typed_slice_reads**. Invoke `readers[[declaration_name]] (features, cells)`.

Authenticated source matrix, selected features/effective cells and parameter-resolved chunk size.
ordered_partition_exactly_once or independent_slices; explicit axes; observation mandatory; exact-once schedules may require unselected feature blocks.
requested_chunk_size, max_rows, max_columns, max_elements and full schedule enforced by grant.
Finish required read schedule before receipt; retirement prohibits later reuse.

Python runtime: supported ordinary numeric slices; nonnegative_integer_v1 request rejected. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [26-chromvar.json](recipes/26-chromvar.json)

## typed_spaces

Declare **typed_space_reads**. Invoke `readers[[declaration_name]] (cells)`.

Space ID, payload, selector axis and role bound by core.
Admitted ordered cell partitions and declared dimension role; full independent axes are separate policy.
Grant chunk/cell/dimension/element ceilings.
Complete declared reads before linked model/output seal.

Python runtime: unsupported executable callback; schema/receipt parity only. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json)

## bindings

Declare **public_interface, parameter_bindings, cell_selector_axes, retained_parameters**. Invoke `params (copied admitted effective values); no bundle reader`.

Core selectors and parameter schema; raw runner return fields do not become retained params.
Resolve defaults/selectors before dispatch; retain only declared sources.
Admitted parameter dialect, unknown-key rejection, source-specific ceilings.
Read-only params/context; output-derived retention checked at receipt.

Python runtime: ordinary bindings supported; selector-bound advanced grants require separate runtime support. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json)

## output_axes

Declare **dimension_policies, parameter_axes**. Invoke `context effective_cells; family/parameter axes encoded in the admitted output descriptors`.

Fixed, parameter-resolved feature groups/input keys, grouped or runtime key declarations.
Exact shape, family keys, row order and missing-value policy; unique-key canonical metadata.
Declared rank, dimension labels, key counts and row ceilings; exact spelling below.
Authenticated axes before linked writes; runtime families declare before writing.

Python runtime: basic axes supported; runtime/genomic/sparse/relation/derived fitted/matrix-trained variants unsupported. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [02-read_matrix_model.json](recipes/02-read_matrix_model.json), [04-fit_sibling_model.json](recipes/04-fit_sibling_model.json), [05-adopt_external_state.json](recipes/05-adopt_external_state.json), [08-standalone_sparse_family.json](recipes/08-standalone_sparse_family.json), [09-sealed_relation_family.json](recipes/09-sealed_relation_family.json), [10-bounded_family.json](recipes/10-bounded_family.json), [11-ancestry_family.json](recipes/11-ancestry_family.json), [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json), [26-chromvar.json](recipes/26-chromvar.json)

## matrix_fragments

Declare **publication_policies**. Invoke `writers$open_matrix_fragments(name); handle$source_fragments; handle$write_fragment(source_fragment_ordinal,values,feature_ids,cell_ids); handle$finish(semantic_metadata=list())`.

Allocated matrix output linked to authenticated axes and publication policy.
Open once, exact declared partitions, finish once; add/replace policy and source currentness enforced.
Per-fragment grant bounds and complete matrix axis coverage.
Close handle before runner return; complete output closure.

Python runtime: supported fragment handle. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json)

## registry_reads

Declare **registry_reads**. Invoke `readers[[declaration_name]] ()`.

Feature-set/genomic/motif/match-set snapshot, currentness and declared metadata-derived provider.
No-argument exactly-once selected snapshot; registry authority is not a primitive kind.
Snapshot selections/fields/provider dependencies admitted before dispatch.
Reader observations and source revalidation before publication.

Python runtime: session-cell-axis and feature-annotation snapshots supported; genomic/motif/match-set callbacks unsupported. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [26-chromvar.json](recipes/26-chromvar.json)

## registry_admission

Declare **outputs**. Invoke `writers$request_cell_set_admission(name,value,semantic_metadata=list()); writers$request_cell_set_family_admission(name,value,semantic_metadata=list())`.

Requests are audited by core; no direct registry writer is granted.
Exactly one request per declared output; family ordering and empty/nonempty policy.
Declared membership/current source and family ceilings.
Atomic complete registry/output closure, including empty families.

Python runtime: cell-set and family requests supported in existing ordinary protocol. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [02-read_matrix_model.json](recipes/02-read_matrix_model.json), [03-fit_derived_axis_model.json](recipes/03-fit_derived_axis_model.json), [04-fit_sibling_model.json](recipes/04-fit_sibling_model.json), [05-adopt_external_state.json](recipes/05-adopt_external_state.json), [06-derived_subset.json](recipes/06-derived_subset.json), [07-derived_union.json](recipes/07-derived_union.json), [08-standalone_sparse_family.json](recipes/08-standalone_sparse_family.json), [09-sealed_relation_family.json](recipes/09-sealed_relation_family.json), [10-bounded_family.json](recipes/10-bounded_family.json), [11-ancestry_family.json](recipes/11-ancestry_family.json), [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json), [26-chromvar.json](recipes/26-chromvar.json)

## provenance

Declare **provenance_reads, producer_lineage_reads**. Invoke `readers[[declaration_name]] ()`.

Artifact ancestry or producer lineage bound to actual source run/snapshot, not self-asserted summary text.
No-argument exactly once; only admitted provenance fields.
Admitted selection/currentness and parameter assertions.
Reader observations retained independently of payload assertions.

Python runtime: artifact ancestry supported; producer lineage unsupported. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [11-ancestry_family.json](recipes/11-ancestry_family.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json)

## models

Declare **contained_model_reads, self_linked_contained_model_reads, outputs**. Invoke `readers[[name]] (); handle$read_bytes(relative); handle$path(relative) or $runtime_private_path(relative); writers$open_model_tree(output); handle$path(relative), $write_bytes(relative,bytes), $finish(value,semantic_metadata=list())`.

Exact model tree, source linkage, ordered cells/features/dimensions and sibling output identities.
Read declared tree only; open/finish writer once; entries contained, no symlinks/traversal; safe deserialization is the author's responsibility.
Declared file/count/size/tree ceilings; never a durable bundle path.
Finish before return; private paths and all closures must not escape invocation. Some returned closures do not universally enforce retirement; reuse is prohibited.

Python runtime: ordinary contained_model_reads and self-linked linkage v2 supported; linkage v3 derived fitted and matrix-trained model grants request-rejected. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [02-read_matrix_model.json](recipes/02-read_matrix_model.json), [03-fit_derived_axis_model.json](recipes/03-fit_derived_axis_model.json), [04-fit_sibling_model.json](recipes/04-fit_sibling_model.json), [05-adopt_external_state.json](recipes/05-adopt_external_state.json), [06-derived_subset.json](recipes/06-derived_subset.json), [07-derived_union.json](recipes/07-derived_union.json), [08-standalone_sparse_family.json](recipes/08-standalone_sparse_family.json), [09-sealed_relation_family.json](recipes/09-sealed_relation_family.json), [10-bounded_family.json](recipes/10-bounded_family.json), [11-ancestry_family.json](recipes/11-ancestry_family.json), [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json), [26-chromvar.json](recipes/26-chromvar.json)

## G4

Declare **artifact_collection_reads**. Invoke `readers$read_retained_artifact_collection_item(collection_name,resolved_ordinal,slot)`.

Authenticated retained collection references and source observations.
Every authenticated ordinal/slot exactly once in admitted order.
Collection count and slot ceilings.
Complete reads before composed output writes/receipt.

Python runtime: unsupported executable callback. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [07-derived_union.json](recipes/07-derived_union.json)

## G5

Declare **named_cell_axis_collections**. Invoke `readers$read_named_cell_axis(collection_name,ordinal)`.

Authenticated named cell-axis collection.
Exactly once per declared ordinal; preserve source order.
Unique ordered cells and declared collection ceilings.
Complete observations before linked output seal.

Python runtime: unsupported executable callback. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [23-space_path_define.json](recipes/23-space_path_define.json)

## G6

Declare **optional_display_axis_groups**. Invoke `readers$read_optional_display_space(group_name,group_key,cells); readers$read_optional_endpoint_axis(group_name,group_key,ordinal)`.

Core-attested group, display axis and endpoint role/ordinal.
Absent groups have no capability; complete display partitions before endpoint reads.
Ordered partition/endpoint ceilings.
Complete optional group observations before receipt; display geometry is distinct from fitted model state.

Python runtime: unsupported executable callback. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json)

## G3

Declare **supported_external_state_adoptions**. Invoke `readers[[adoption_name]] (); result$pack_source_association_attestation; result$pack_no_refit_attestation`.

external_state_candidate is input authority, not a primitive; exact snapshot/tree/payload/ordered cell identity and G2 linkage.
Exactly-once path-free candidate admission; separate TRUE attestations; no refit.
bytes_verified/bytes_not_inspected/manifest-authorized bytes_unavailable; observed checksum mismatch always rejects.
Admitted and published trees byte-identical; atomic model/linked output closure.

Python runtime: unsupported executable adoption authority; shared parity only. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [05-adopt_external_state.json](recipes/05-adopt_external_state.json)

## G7

Declare **derived_cell_output_axes**. Invoke `result$derived_cell_output_axis_declarations (ordered axis declarations); writers seal linked outputs under admitted grants`.

Authenticated single source axis or selected G4 members; separate seal-derived cardinality, not v1 grant substitution.
Exactly one declared subset/ordered-union axis; final union order belongs to pack; each member selection remains in source order.
Unique membership, ordered member selections, cell/key/row ceilings and effective family-key policy.
Seal before linked output admission; complete receipt/output closure independently enforced.

Python runtime: unsupported executable sealing/receipt authority; some variants manifest/request rejected. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [06-derived_subset.json](recipes/06-derived_subset.json), [07-derived_union.json](recipes/07-derived_union.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json)

## dependencies

Declare **dependencies**. Invoke `pre-dispatch engine dependency probes; no installer callback`.

Declared version predicates/import probes and provider source evidence.
R/Python/system/device fixed and optional requirements; dynamic providers retained from authenticated metadata.
Offline failure; no silent package replacement; separate process/environment for conflicts.
Dependency evidence retained with run runtime identity.

Python runtime: fixed dependency probes supported; dynamic genomic provider authority unsupported. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [02-read_matrix_model.json](recipes/02-read_matrix_model.json), [03-fit_derived_axis_model.json](recipes/03-fit_derived_axis_model.json), [04-fit_sibling_model.json](recipes/04-fit_sibling_model.json), [05-adopt_external_state.json](recipes/05-adopt_external_state.json), [06-derived_subset.json](recipes/06-derived_subset.json), [07-derived_union.json](recipes/07-derived_union.json), [08-standalone_sparse_family.json](recipes/08-standalone_sparse_family.json), [09-sealed_relation_family.json](recipes/09-sealed_relation_family.json), [10-bounded_family.json](recipes/10-bounded_family.json), [11-ancestry_family.json](recipes/11-ancestry_family.json), [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json), [26-chromvar.json](recipes/26-chromvar.json)

## closure_replay

Declare **promotion_closure, replay_equivalence**. Invoke `writer return is an acknowledgment; runner returns list(status='ok') plus only declared channels`.

Core-created receipt, source/installed pack/operation identity, artifacts and provenance.
Required terminals exactly once, sorted closed promotion groups and admitted six replay policy spellings.
No author-generated receipt or hash substitutes for authentication.
Atomic publication; pack-free inspection differs from identity-bound execution/replay.

Python runtime: ordinary closure/replay supported; advanced closure requires supported runtime. Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority.

Worked closed manifests: [01-fit_matrix_model.json](recipes/01-fit_matrix_model.json), [02-read_matrix_model.json](recipes/02-read_matrix_model.json), [03-fit_derived_axis_model.json](recipes/03-fit_derived_axis_model.json), [04-fit_sibling_model.json](recipes/04-fit_sibling_model.json), [05-adopt_external_state.json](recipes/05-adopt_external_state.json), [06-derived_subset.json](recipes/06-derived_subset.json), [07-derived_union.json](recipes/07-derived_union.json), [08-standalone_sparse_family.json](recipes/08-standalone_sparse_family.json), [09-sealed_relation_family.json](recipes/09-sealed_relation_family.json), [10-bounded_family.json](recipes/10-bounded_family.json), [11-ancestry_family.json](recipes/11-ancestry_family.json), [12-addmodulescore.json](recipes/12-addmodulescore.json), [13-winner_cell_sets.json](recipes/13-winner_cell_sets.json), [14-feature_set_overlap_qc.json](recipes/14-feature_set_overlap_qc.json), [15-rna_qc_metrics.json](recipes/15-rna_qc_metrics.json), [16-matrix_log_normalize.json](recipes/16-matrix_log_normalize.json), [17-pca_fit.json](recipes/17-pca_fit.json), [18-umap_fit.json](recipes/18-umap_fit.json), [19-umap_transform.json](recipes/19-umap_transform.json), [20-knn_neighbors.json](recipes/20-knn_neighbors.json), [21-knn_pseudobulk.json](recipes/21-knn_pseudobulk.json), [22-space_path_project_2d.json](recipes/22-space_path_project_2d.json), [23-space_path_define.json](recipes/23-space_path_define.json), [24-trajectory_space_path_segment.json](recipes/24-trajectory_space_path_segment.json), [25-model_bound_latent_union.json](recipes/25-model_bound_latent_union.json), [26-chromvar.json](recipes/26-chromvar.json)
