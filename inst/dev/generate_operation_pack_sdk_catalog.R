#!/usr/bin/env Rscript
# SDK references derive schema spellings from the accepted ABI; they are not validators.
schema <- jsonlite::read_json("inst/protocol/operation-pack-v3.schema.json")
kinds <- unlist(schema[["$defs"]]$primitive_kind$enum, use.names = FALSE)
profiles <- unlist(schema[["$defs"]]$storage_profile$enum, use.names = FALSE)
entry <- function(id, locations, kinds, signature, discipline, source, limits,
                  closure, python, evidence) list(id = id,
  manifest_locations = as.list(locations), kinds = as.list(kinds),
  backends = list("R", "Python"), callback_signature = signature,
  source_binding = source, call_discipline = discipline,
  empty_na_rules = "Only the admitted declaration permits empties or canonical null; otherwise reject. Scientific finite-value rules remain the pack's responsibility.",
  limits = limits, seal_close_timing = closure,
  R = list(manifest_admission = "supported", request_admission = "supported",
    executable_runtime = "supported"),
  Python = list(manifest_admission = "see exact policy and runtime guards",
    request_admission = "see exact policy and runtime guards",
    executable_runtime = python),
  evidence = as.list(evidence), recipe = "GUIDE.md")
capabilities <- list(
  entry("ordinary_io", c("inputs", "outputs"), kinds,
    "readers[[input]](); matrix reader(features=NULL,cells=NULL); writers$write_{matrix,space,space_2d,model_ref,path_2d_family,space_path_family}(name,value,semantic_metadata=list()); writers$write_terminal_primitive(name,value,semantic_metadata=list())",
    "Read copied declared input; each required output exactly once; writer must match kind/profile/category tuple.",
    "Authenticated input descriptor and output allocation; symbolic constructors are not computed output payloads.",
    "Declared dimensions and profile; do not infer full materialization is bounded.",
    "Complete promotion closure and core-created receipt before publication.",
    "supported for ordinary 11-kind IO; advanced policies are separate entries",
    c("tests/test_operation_pack_v2_contract.R", "PyBench:tests/test_operation_pack_v2.py::test_synthetic_pack_all_readers_writers_profiles_and_receipt")),
  entry("typed_slices", "typed_slice_reads", "matrix",
    "readers[[declaration_name]](features, cells)",
    "ordered_partition_exactly_once or independent_slices; explicit axes; observation mandatory; exact-once schedules may require unselected feature blocks.",
    "Authenticated source matrix, selected features/effective cells and parameter-resolved chunk size.",
    "requested_chunk_size, max_rows, max_columns, max_elements and full schedule enforced by grant.",
    "Finish required read schedule before receipt; retirement prohibits later reuse.",
    "supported ordinary numeric slices; nonnegative_integer_v1 request rejected",
    "tests/test_operation_pack_v3_contract.R"),
  entry("typed_spaces", "typed_space_reads", c("space", "space_2d"),
    "readers[[declaration_name]](cells)",
    "Admitted ordered cell partitions and declared dimension role; full independent axes are separate policy.",
    "Space ID, payload, selector axis and role bound by core.", "Grant chunk/cell/dimension/element ceilings.",
    "Complete declared reads before linked model/output seal.",
    "unsupported executable callback; schema/receipt parity only", "tests/test_operation_pack_v3_contract.R"),
  entry("bindings", c("public_interface", "parameter_bindings", "cell_selector_axes", "retained_parameters"), kinds,
    "params (copied admitted effective values); no bundle reader", "Resolve defaults/selectors before dispatch; retain only declared sources.",
    "Core selectors and parameter schema; raw runner return fields do not become retained params.",
    "Admitted parameter dialect, unknown-key rejection, source-specific ceilings.", "Read-only params/context; output-derived retention checked at receipt.",
    "ordinary bindings supported; selector-bound advanced grants require separate runtime support", "tests/test_operation_pack_v3_contract.R"),
  entry("output_axes", c("dimension_policies", "parameter_axes"), kinds,
    "context effective_cells; family/parameter axes encoded in the admitted output descriptors", "Exact shape, family keys, row order and missing-value policy; unique-key canonical metadata.",
    "Fixed, parameter-resolved feature groups/input keys, grouped or runtime key declarations.",
    "Declared rank, dimension labels, key counts and row ceilings; exact spelling below.", "Authenticated axes before linked writes; runtime families declare before writing.",
    "basic axes supported; runtime/genomic/sparse/relation/derived fitted/matrix-trained variants unsupported", "tests/test_operation_pack_v3_contract.R"),
  entry("matrix_fragments", "publication_policies", "matrix",
    "writers$open_matrix_fragments(name); handle$source_fragments; handle$write_fragment(source_fragment_ordinal,values,feature_ids,cell_ids); handle$finish(semantic_metadata=list())",
    "Open once, exact declared partitions, finish once; add/replace policy and source currentness enforced.",
    "Allocated matrix output linked to authenticated axes and publication policy.", "Per-fragment grant bounds and complete matrix axis coverage.",
    "Close handle before runner return; complete output closure.", "supported fragment handle", "tests/test_operation_pack_v2_contract.R"),
  entry("registry_reads", "registry_reads", character(),
    "readers[[declaration_name]]()", "No-argument exactly-once selected snapshot; registry authority is not a primitive kind.",
    "Feature-set/genomic/motif/match-set snapshot, currentness and declared metadata-derived provider.",
    "Snapshot selections/fields/provider dependencies admitted before dispatch.", "Reader observations and source revalidation before publication.",
    "session-cell-axis and feature-annotation snapshots supported; genomic/motif/match-set callbacks unsupported", "tests/test_operation_pack_v2_feature_set_registry_read_contract.R"),
  entry("registry_admission", "outputs", character(),
    "writers$request_cell_set_admission(name,value,semantic_metadata=list()); writers$request_cell_set_family_admission(name,value,semantic_metadata=list())",
    "Exactly one request per declared output; family ordering and empty/nonempty policy.",
    "Requests are audited by core; no direct registry writer is granted.", "Declared membership/current source and family ceilings.",
    "Atomic complete registry/output closure, including empty families.", "cell-set and family requests supported in existing ordinary protocol", "tests/test_operation_pack_v2_cell_set_family_admission_contract.R"),
  entry("provenance", c("provenance_reads", "producer_lineage_reads"), kinds,
    "readers[[declaration_name]]()", "No-argument exactly once; only admitted provenance fields.",
    "Artifact ancestry or producer lineage bound to actual source run/snapshot, not self-asserted summary text.",
    "Admitted selection/currentness and parameter assertions.", "Reader observations retained independently of payload assertions.",
    "artifact ancestry supported; producer lineage unsupported", "tests/test_operation_pack_v3_contract.R"),
  entry("models", c("contained_model_reads", "self_linked_contained_model_reads", "outputs"), "model_ref",
    "readers[[name]](); handle$read_bytes(relative); handle$path(relative) or $runtime_private_path(relative); writers$open_model_tree(output); handle$path(relative), $write_bytes(relative,bytes), $finish(value,semantic_metadata=list())",
    "Read declared tree only; open/finish writer once; entries contained, no symlinks/traversal; safe deserialization is the author's responsibility.",
    "Exact model tree, source linkage, ordered cells/features/dimensions and sibling output identities.",
    "Declared file/count/size/tree ceilings; never a durable bundle path.", "Finish before return; private paths and all closures must not escape invocation. Some returned closures do not universally enforce retirement; reuse is prohibited.",
    "ordinary contained_model_reads and self-linked linkage v2 supported; linkage v3 derived fitted and matrix-trained model grants request-rejected", "tests/test_operation_pack_v3_durable_model_tree_contract.R"),
  entry("G4", "artifact_collection_reads", kinds,
    "readers$read_retained_artifact_collection_item(collection_name,resolved_ordinal,slot)",
    "Every authenticated ordinal/slot exactly once in admitted order.", "Authenticated retained collection references and source observations.",
    "Collection count and slot ceilings.", "Complete reads before composed output writes/receipt.", "unsupported executable callback", "tests/test_operation_pack_v3_phase5_consolidated_capabilities.R"),
  entry("G5", "named_cell_axis_collections", character(),
    "readers$read_named_cell_axis(collection_name,ordinal)", "Exactly once per declared ordinal; preserve source order.",
    "Authenticated named cell-axis collection.", "Unique ordered cells and declared collection ceilings.", "Complete observations before linked output seal.",
    "unsupported executable callback", "tests/test_operation_pack_v3_phase5_consolidated_capabilities.R"),
  entry("G6", "optional_display_axis_groups", c("space", "space_2d"),
    "readers$read_optional_display_space(group_name,group_key,cells); readers$read_optional_endpoint_axis(group_name,group_key,ordinal)",
    "Absent groups have no capability; complete display partitions before endpoint reads.", "Core-attested group, display axis and endpoint role/ordinal.",
    "Ordered partition/endpoint ceilings.", "Complete optional group observations before receipt; display geometry is distinct from fitted model state.",
    "unsupported executable callback", "tests/test_operation_pack_v3_phase5_consolidated_capabilities.R"),
  entry("G3", "supported_external_state_adoptions", "model_ref",
    "readers[[adoption_name]](); result$pack_source_association_attestation; result$pack_no_refit_attestation",
    "Exactly-once path-free candidate admission; separate TRUE attestations; no refit.",
    "external_state_candidate is input authority, not a primitive; exact snapshot/tree/payload/ordered cell identity and G2 linkage.",
    "bytes_verified/bytes_not_inspected/manifest-authorized bytes_unavailable; observed checksum mismatch always rejects.",
    "Admitted and published trees byte-identical; atomic model/linked output closure.", "unsupported executable adoption authority; shared parity only", "tests/test_operation_pack_v3_g3_external_state_adoption_contract.R"),
  entry("G7", "derived_cell_output_axes", c("cell_vector", "cell_vector_family", "space"),
    "result$derived_cell_output_axis_declarations (ordered axis declarations); writers seal linked outputs under admitted grants",
    "Exactly one declared subset/ordered-union axis; final union order belongs to pack; each member selection remains in source order.",
    "Authenticated single source axis or selected G4 members; separate seal-derived cardinality, not v1 grant substitution.",
    "Unique membership, ordered member selections, cell/key/row ceilings and effective family-key policy.",
    "Seal before linked output admission; complete receipt/output closure independently enforced.", "unsupported executable sealing/receipt authority; some variants manifest/request rejected", "tests/test_operation_pack_v3_g7_derived_cell_output_axis_contract.R"),
  entry("dependencies", "dependencies", character(), "pre-dispatch engine dependency probes; no installer callback",
    "R/Python/system/device fixed and optional requirements; dynamic providers retained from authenticated metadata.",
    "Declared version predicates/import probes and provider source evidence.", "Offline failure; no silent package replacement; separate process/environment for conflicts.",
    "Dependency evidence retained with run runtime identity.", "fixed dependency probes supported; dynamic genomic provider authority unsupported", "tests/test_operation_pack_v2_contract.R"),
  entry("closure_replay", c("promotion_closure", "replay_equivalence"), kinds,
    "writer return is an acknowledgment; runner returns list(status='ok') plus only declared channels",
    "Required terminals exactly once, sorted closed promotion groups and admitted six replay policy spellings.",
    "Core-created receipt, source/installed pack/operation identity, artifacts and provenance.",
    "No author-generated receipt or hash substitutes for authentication.", "Atomic publication; pack-free inspection differs from identity-bound execution/replay.",
    "ordinary closure/replay supported; advanced closure requires supported runtime", "tests/test_operation_pack_v2_contract.R")
)
branches <- list()
owner <- function(path) {
  definition <- sub("^#/[\u0024]defs/", "", path)
  if (grepl("typed_slice|axis_selection", definition)) return("typed_slices")
  if (grepl("typed_space", definition)) return("typed_spaces")
  if (grepl("registry|genomic|motif|metadata", definition)) return("registry_reads")
  if (grepl("provenance|producer_lineage", definition)) return("provenance")
  if (grepl("external.*adoption", definition)) return("G3")
  if (grepl("artifact_collection", definition)) return("G4")
  if (grepl("named_cell_axis", definition)) return("G5")
  if (grepl("optional_display|endpoint", definition)) return("G6")
  if (grepl("derived_cell_output|seal_derived", definition)) return("G7")
  if (grepl("model|fitted", definition)) return("models")
  if (grepl("dimension|parameter_axis|family|membership|pseudobulk", definition)) return("output_axes")
  if (grepl("dependency|language|system|device", definition)) return("dependencies")
  if (grepl("parameter|public_interface", definition)) return("bindings")
  if (grepl("publication", definition)) return("matrix_fragments")
  if (grepl("promotion_closure|replay_equivalence", path)) return("closure_replay")
  "ordinary_io"
}
walk <- function(value, path) {
  if (!is.list(value)) return(invisible(NULL))
  if (!is.null(value$const) || !is.null(value$enum)) branches[[length(branches)+1L]] <<-
    list(schema_path = path, values = as.list(value$enum %||% value$const),
      capability_id = owner(path),
      classification = "exact accepted ABI spelling; use owning capability recipe and backend policy")
  for (name in names(value)) if (is.list(value[[name]])) {
    child <- value[[name]]
    if (is.null(names(child))) for (i in seq_along(child)) walk(child[[i]], paste0(path,"/",name,"/",i-1L))
    else walk(child, paste0(path,"/",name))
  }
}
`%||%` <- function(x,y) if (is.null(x)) y else x
walk(schema, "#")
recipes <- unlist(lapply(sort(list.files("inst/sdk/operation-packs",
  pattern = "^recipe-source-[0-9]+[.]json$", full.names = TRUE)),
  jsonlite::read_json), recursive = FALSE)
recipe_index <- lapply(seq_along(recipes), function(index) {
  item <- recipes[[index]]
  operation <- item$manifest$operations[[1L]]
  path <- paste0("recipes/", sprintf("%02d", index), "-", operation$name, ".json")
  dir.create("inst/sdk/operation-packs/recipes", showWarnings = FALSE)
  jsonlite::write_json(item$manifest, file.path("inst/sdk/operation-packs", path),
    auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  list(path = path, operation = operation$name, source = item$source,
    source_sha256 = item$source_sha256, manifest_fields = as.list(names(operation)),
    policies = item$policies,
    qualification = "static declaration recipe only; no runner is shipped or activated")
})
for (i in seq_along(capabilities)) {
  capabilities[[i]]$recipe <- paste0("RECIPES.md#", capabilities[[i]]$id)
  locations <- unlist(capabilities[[i]]$manifest_locations)
  matches <- Filter(function(x) any(locations %in% unlist(x$manifest_fields)), recipe_index)
  capabilities[[i]]$declaration_examples <- lapply(matches, `[[`, "path")
}
public_names <- c("wb_operation_pack_manifest_validate", "wb_operation_pack_validate",
  "wb_operation_pack_activate", "wb_operation_pack_load", "wb_operation_pack_register",
  "wb_operation_pack_inspect", "wb_operation_pack_unload", "wb_operation_packs",
  "wb_operation_pack_transition_outputs", "wb_operation_pack_transition_load",
  "wb_operation_pack_transition_registry_reads", "wb_operation_pack_registry_receipts",
  "wb_partition_axis", "wb_session_new", "wb_session_run_op", "wb_session_promote_current",
  "wb_op_interface", "wb_list_ops", "wb_finalize_recipient_bundle", "wb_open_bundle",
  "wb_validate_bundle", "wb_art_list", "wb_art_load")
public_names <- c(public_names, paste0("wb_prim_", kinds),
  vapply(jsonlite::read_json("inst/sdk/operation-packs/interface.json")$apis, `[[`, character(1), "name"))
public_api <- list()
for (file in sort(list.files("R", "[.]R$", full.names = TRUE))) {
  for (expression in parse(file)) if (is.call(expression) &&
      identical(expression[[1L]], as.name("<-")) && is.symbol(expression[[2L]]) &&
      as.character(expression[[2L]]) %in% public_names &&
      is.call(expression[[3L]]) && identical(expression[[3L]][[1L]], as.name("function"))) {
    name <- as.character(expression[[2L]])
    public_api[[name]] <- list(name = name, source = file,
      signature = paste(deparse(expression[[3L]][[2L]], width.cutoff = 500L), collapse = " "))
  }
}
catalog <- list(sdk_version = "1.0.0", pack_abi_version = "3",
  schema_sha256 = digest::digest(file = "inst/protocol/operation-pack-v3.schema.json", algo = "sha256"),
  primitive_kinds = as.list(kinds), storage_profiles = as.list(profiles),
  operation_declaration_fields = as.list(names(schema[["$defs"]]$operation$properties)),
  capabilities = capabilities, declaration_branches = branches,
  public_api = unname(public_api),
  declaration_recipes = recipe_index,
  callbacks_and_context = jsonlite::read_json("inst/sdk/operation-packs/callbacks.json"),
  Python_policy_support = jsonlite::read_json("inst/sdk/operation-packs/python_support.json"),
  authoring_interface = jsonlite::read_json("inst/sdk/operation-packs/interface.json"))
jsonlite::write_json(catalog, "inst/sdk/operation-packs/capabilities.json",
  auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
human <- c("# Installed Operation Pack SDK capability reference", "",
  "Generated by inst/dev/generate_operation_pack_sdk_catalog.R from the accepted ABI and author recipes. This is an inventory, not an admission validator.", "",
  "| Family | Manifest locations | Callback | Python execution | Evidence |",
  "| --- | --- | --- | --- | --- |",
  vapply(capabilities, function(x) paste0("| ",x$id," | ",paste(unlist(x$manifest_locations),collapse=", "),
    " | ",x$callback_signature," | ",x$Python$executable_runtime," | ",paste(unlist(x$evidence),collapse=", ")," |"), character(1)), "",
  paste0("The machine catalog includes all ",length(kinds)," primitive kinds, ",length(profiles),
    " storage profiles, ",length(catalog$operation_declaration_fields)," operation fields and ",length(branches),
    " accepted constant/enum schema branches. Read their exact spelling, ordering, ceilings and backend restrictions before declaring authority."))
writeLines(human, "inst/sdk/operation-packs/CAPABILITIES.md")
recipes_doc <- c("# Installed declaration recipes", "",
  "Frozen accepted declarations, validated using wb_operation_pack_manifest_validate(). These are manifest-only recipes, not installed handlers, scientific endorsements or additional scaffold options. Edit package/namespace/entry point/qualified name consistently. Preserve dependencies, admitted axes and complete output closure when adapting a recipe. Never load a recipe as a pack without implementing and testing its runner.", "",
  "The normative shapes and numerical/empty/NA ceilings are shipped, not hidden in core source:", "",
  "```r", "schema <- system.file('protocol', 'operation-pack-v3.schema.json', package='scworkbench')",
  "recipe <- system.file('sdk', 'operation-packs', 'recipes', '<filename>.json', package='scworkbench')",
  "definition <- wb_operation_pack_manifest_validate(recipe)$manifest$operations[[1]]",
  "# Inspect definition$inputs, declaration-specific grants, dimension_policies, outputs and promotion_closure.",
  "```", "",
  "Runtime family/derived-fitted/sparse/relation declarations are invocation-scoped writer calls, not author-created seals. See callbacks.json for exact declare-before-write signatures. Model tree finish closes the complete linkage; a receipt hash never replaces a finished handle. Core enforces the declared policy. Empty and missing values depend on the selected declaration; do not generalize them from the scalar reference.", "")
for (capability in capabilities) recipes_doc <- c(recipes_doc, paste0("## ", capability$id), "",
  paste0("Declare **", paste(unlist(capability$manifest_locations), collapse = ", "), "**. Invoke `",capability$callback_signature,"`."), "",
  capability$source_binding, capability$call_discipline, capability$limits,
  capability$seal_close_timing, "",
  paste0("Python runtime: ",capability$Python$executable_runtime,
    ". Read Python_policy_support for exact manifest/request guards; a shared schema is not runtime authority."), "",
  paste0("Worked closed manifests: ",paste(vapply(capability$declaration_examples,
    function(path) paste0("[",basename(path),"](",path,")"), character(1)), collapse = ", ")), "")
while (length(recipes_doc) && !nzchar(tail(recipes_doc, 1L)))
  recipes_doc <- head(recipes_doc, -1L)
writeLines(recipes_doc, "inst/sdk/operation-packs/RECIPES.md")
