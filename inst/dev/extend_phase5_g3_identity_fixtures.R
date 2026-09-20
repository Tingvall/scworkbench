#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
path <- file.path(root, "inst", "protocol", "fixtures",
  "operation-pack-v3", "identities.json")
fixture <- jsonlite::read_json(path, simplifyVector = FALSE)
plain <- scworkbench:::.wb_operation_pack_v2_identity_plain
scoped <- scworkbench:::.wb_operation_pack_v2_identity_scoped
hex <- function(x) paste(rep(x, 64L), collapse = "")
id <- function(scheme, x) list(scheme = scheme, sha256 = hex(x))
case <- function(name, preimage, field, identity) {
  value <- preimage; value[[field]] <- identity
  list(name = name, preimage = preimage, identity = identity, value = value)
}
mk <- function(name, scheme, scope, preimage, field) {
  identity <- scoped(scheme, scope, preimage)
  case(name, preimage, field, identity)
}

declaration <- list(schema =
    "scworkbench.operation_pack.supported_external_state_adoption.v1",
  name = "adoption", state_input = "candidate",
  source_parameter = "external_source_ref",
  allowed_state_types = list(list(engine = "slingshot",
    model_type = "principal_curves")),
  allowed_source_byte_states = list("bytes_verified",
    "bytes_not_inspected", "bytes_unavailable"), model_output = "model",
  required_closure_outputs = list("pseudotime"),
  primary_path = "model.rds", maximum_file_count = 8L,
  maximum_total_bytes = 1048576L, maximum_cell_count = 100000L,
  call_discipline = "adoption_state_exactly_once",
  output_tree_policy = "exact_admitted_tree_identity",
  execution_semantics = "supported_external_state_adoption_without_refit_v1")
declaration_id <- scoped(declaration$schema,
  "supported external state adoption declaration excluding declaration_identity",
  declaration)
declaration_value <- declaration
declaration_value$declaration_identity <- declaration_id

source <- list(entity_kind = "external_source", source_id = "source-fit",
  source_snapshot_id = "snapshot-1", source_run_id = "run-1",
  scope = "external_file", lifecycle_state = "current",
  recorded_checksum_status = "checksummed",
  declared_content_identity = id("scworkbench.raw_file.sha256.v1", "1"))
source_id <- scoped(
  "scworkbench.operation_pack.external_source_adoption_snapshot.v1",
  "external source snapshot excluding source_snapshot_identity", source)
source_value <- source; source_value$source_snapshot_identity <- source_id

tree <- list(schema =
    "scworkbench.operation_pack.contained_model_tree_manifest.v1",
  engine = "slingshot", model_type = "principal_curves",
  primary_path = "model.rds", file_count = 1L, total_size = 12L,
  entries = list(list(path = "model.rds", size = 12L, sha256 = hex("2"))))
tree_id <- scoped(tree$schema, "manifest excluding manifest_identity", tree)
tree_value <- tree; tree_value$manifest_identity <- tree_id
payload_id <- plain("scworkbench.operation_pack.payload_manifest.v2",
  list(contained_model_tree_manifest_identity = tree_id[c("scheme", "sha256")],
    entry_payload_identities = list(plain(
      "scworkbench.operation_pack.payload_file.v1", tree$entries[[1L]]))))
cell_id <- plain("scworkbench.cell_order.v1", list("cell-b", "cell-a"))
candidate <- list(selected_state_type = list(engine = "slingshot",
    model_type = "principal_curves"), tree_manifest = tree_value,
  tree_manifest_identity = tree_id[c("scheme", "sha256")],
  payload_manifest_identity = payload_id, primary_path = "model.rds",
  file_count = 1L, total_bytes = 12L, ordered_cell_count = 2L,
  ordered_cell_identity = cell_id, integrity_status = "authenticated",
  relative_root = "external_state_adoptions/adoption/tree")
candidate_id <- scoped("scworkbench.operation_pack.external_state_candidate.v1",
  "external state candidate excluding candidate_snapshot_identity", candidate)
candidate_value <- candidate
candidate_value$candidate_snapshot_identity <- candidate_id

writer_id <- id(
  "scworkbench.operation_pack.contained_model_sibling_write_grant.v1", "3")
linkage_id <- id("scworkbench.operation_pack.model_source_linkage.v2", "4")
output_id <- id("scworkbench.operation_pack.output_grant.v3", "5")
closure <- list(outputs = list(list(name = "model", allocated_id = "model-1",
    kind = "model_ref", output_grant_identity = output_id,
    terminal_policy = "loadable_reference", promotion_group = "adoption",
    expected_cell_order_identity_if_cell_indexed = NULL)),
  contained_model_sibling_write_grant_identity = writer_id,
  model_source_linkage_identity = linkage_id)
closure_id <- scoped(
  "scworkbench.operation_pack.supported_external_state_adoption_closure.v1",
  "adopted closure excluding adopted_closure_identity", closure)
closure_value <- closure; closure_value$adopted_closure_identity <- closure_id

evidence <- function(status) {
  x <- list(status = status,
    declared_content_identity = source$declared_content_identity,
    observed_content_identity = if (identical(status, "bytes_verified"))
      source$declared_content_identity else NULL,
    nonverification_reason = switch(status, bytes_verified = NULL,
      bytes_not_inspected = "policy_did_not_inspect_external_bytes",
      bytes_unavailable = "external_bytes_unavailable"))
  identity <- scoped(
    "scworkbench.operation_pack.external_source_byte_evidence.v1",
    "external source byte evidence excluding source_byte_evidence_identity", x)
  x$source_byte_evidence_identity <- identity
  x
}
grant <- function(status) {
  x <- list(schema =
      "scworkbench.operation_pack.supported_external_state_adoption_grant.v1",
    name = "adoption", declaration_identity =
      declaration_id[c("scheme", "sha256")],
    source_snapshot = source_value, source_byte_evidence = evidence(status),
    candidate_snapshot = candidate_value,
    contained_model_sibling_write_grant_identity = writer_id,
    model_source_linkage_identity = linkage_id,
    adopted_closure = closure_value,
    access = "verified_private_copy_read_only_v1",
    call_discipline = "adoption_state_exactly_once",
    execution_semantics = "supported_external_state_adoption_without_refit_v1")
  x$grant_identity <- scoped(x$schema,
    "supported external state adoption grant excluding grant_identity", x)
  x
}
observation <- function(status) {
  g <- grant(status)
  x <- list(schema =
      "scworkbench.operation_pack.observed_supported_external_state_adoption.v1",
    name = "adoption", grant_identity = g$grant_identity[c("scheme", "sha256")],
    source_snapshot_identity = source_id[c("scheme", "sha256")],
    source_byte_evidence = g$source_byte_evidence,
    candidate_snapshot_identity = candidate_id[c("scheme", "sha256")],
    candidate_tree_manifest_identity = tree_id[c("scheme", "sha256")],
    candidate_payload_manifest_identity = payload_id,
    ordered_cell_count = 2L, ordered_cell_identity = cell_id,
    contained_model_sibling_tree_observation_identity = id(
      "scworkbench.operation_pack.contained_model_sibling_tree_observation.v1",
      "6"), adopted_model_tree_manifest_identity =
      tree_id[c("scheme", "sha256")],
    adopted_model_payload_manifest_identity = payload_id,
    model_source_linkage_identity = linkage_id,
    adopted_closure_identity = closure_id[c("scheme", "sha256")],
    ordered_observed_output_descriptor_identities = list(id(
      "scworkbench.operation_pack.observed_output.v3", "7")),
    read_count = 1L, event_count = 1L,
    execution_mode = "supported_external_state_adoption",
    upstream_execution = "external",
    pack_source_association_attestation = TRUE,
    pack_no_refit_attestation = TRUE, integrity_status = "unchanged",
    publication_status = "validated_not_published")
  x$observation_identity <- scoped(x$schema,
    "observed supported external state adoption excluding observation_identity",
    x)
  x
}

states <- c("bytes_verified", "bytes_not_inspected", "bytes_unavailable")
new_cases <- list(
  case("g3_declaration", declaration, "declaration_identity", declaration_id),
  case("g3_source_snapshot", source, "source_snapshot_identity", source_id),
  case("g3_candidate_snapshot", candidate, "candidate_snapshot_identity",
    candidate_id),
  case("g3_adopted_closure", closure, "adopted_closure_identity", closure_id))
for (status in states) {
  e <- evidence(status); e_pre <- e; e_pre$source_byte_evidence_identity <- NULL
  g <- grant(status); g_pre <- g; g_pre$grant_identity <- NULL
  o <- observation(status); o_pre <- o; o_pre$observation_identity <- NULL
  request_pre <- list(schema =
      "scworkbench.operation_pack.transition_request.v3",
    supported_external_state_adoption_grants = list(g))
  request_id <- scoped(request_pre$schema,
    "request excluding request_identity", request_pre)
  receipt_pre <- list(schema =
      "scworkbench.operation_pack.transition_receipt.v3",
    supported_external_state_adoption_observations = list(o))
  receipt_id <- scoped(receipt_pre$schema,
    "receipt excluding receipt_identity", receipt_pre)
  suffix <- sub("^bytes_", "", status)
  new_cases <- c(new_cases, list(
    case(paste0("g3_byte_evidence_", suffix), e_pre,
      "source_byte_evidence_identity", e$source_byte_evidence_identity),
    case(paste0("g3_grant_", suffix), g_pre, "grant_identity",
      g$grant_identity),
    case(paste0("g3_observation_", suffix), o_pre, "observation_identity",
      o$observation_identity),
    case(paste0("g3_request_", suffix), request_pre, "request_identity",
      request_id),
    case(paste0("g3_receipt_", suffix), receipt_pre, "receipt_identity",
      receipt_id)))
}
names_new <- vapply(new_cases, `[[`, character(1), "name")
fixture$cases <- c(Filter(function(x) !x$name %in% names_new,
  fixture$cases), new_cases)
fixture$g3_positive_examples <- lapply(states, function(status) list(
  status = status, declaration = declaration_value, grant = grant(status),
  observation = observation(status)))
jsonlite::write_json(fixture, path, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = NA)
