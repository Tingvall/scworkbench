#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")
read <- function(name) jsonlite::read_json(file.path(protocol, name),
  simplifyVector = FALSE)
write <- function(value, name) jsonlite::write_json(value,
  file.path(protocol, name), auto_unbox = TRUE, pretty = TRUE, null = "null",
  digits = NA)
ref <- function(name) list(`$ref` = paste0("#/$defs/", name))
string <- function(...) c(list(type = "string"), list(...))
integer <- function(...) c(list(type = "integer"), list(...))
array <- function(items, ...) c(list(type = "array", items = items), list(...))
object <- function(required, properties, ...) c(list(type = "object",
  additionalProperties = FALSE, required = unname(as.list(required)),
  properties = properties), list(...))
name <- string(pattern = "^[a-z][a-z0-9_]*$")
nonempty <- string(minLength = 1L)
nullable_identity <- list(oneOf = list(ref("identity"), list(type = "null")))
nullable_string <- list(oneOf = list(nonempty, list(type = "null")))
model_pair <- object(c("engine", "model_type"), list(engine = nonempty,
  model_type = nonempty))
self_identity <- object(c("scheme", "scope", "sha256"), list(
  scheme = nonempty, scope = nonempty,
  sha256 = string(pattern = "^[a-f0-9]{64}$")))

# Manifest ----------------------------------------------------------------
manifest <- read("operation-pack-v3.schema.json")
defs <- manifest[["$defs"]]
candidate_input <- object(c("name", "kind", "required", "alignment"), list(
  name = name, kind = list(const = "external_state_candidate"),
  required = list(const = TRUE), alignment = list(const = "none")))
defs$input$oneOf <- Filter(function(x) !identical(
  x$properties$kind$const, "external_state_candidate"), defs$input$oneOf)
defs$input$oneOf <- c(defs$input$oneOf, list(candidate_input))
adoption <- object(c("schema", "name", "state_input", "source_parameter",
  "allowed_state_types", "allowed_source_byte_states", "model_output",
  "required_closure_outputs", "primary_path", "maximum_file_count",
  "maximum_total_bytes", "maximum_cell_count", "call_discipline",
  "output_tree_policy", "execution_semantics", "declaration_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.supported_external_state_adoption.v1"),
    name = name, state_input = name, source_parameter = name,
    allowed_state_types = array(model_pair, minItems = 1L,
      uniqueItems = TRUE),
    allowed_source_byte_states = array(list(enum = list("bytes_verified",
      "bytes_not_inspected", "bytes_unavailable")), minItems = 1L,
      maxItems = 3L, uniqueItems = TRUE), model_output = name,
    required_closure_outputs = array(name, minItems = 0L,
    uniqueItems = TRUE), primary_path = string(pattern =
      "^(?!/)(?!.*(?:^|/)\\.\\.(?:/|$))(?!.*\\\\)[A-Za-z0-9._/-]+$"),
    maximum_file_count = integer(minimum = 1L, maximum = 32L),
    maximum_total_bytes = integer(minimum = 1L, maximum = 1073741824),
    maximum_cell_count = integer(minimum = 1L, maximum = 10000000),
    call_discipline = list(const = "adoption_state_exactly_once"),
    output_tree_policy = list(const = "exact_admitted_tree_identity"),
    execution_semantics = list(const =
      "supported_external_state_adoption_without_refit_v1"),
    declaration_identity = self_identity))
defs$operation$properties$supported_external_state_adoptions <- array(
  adoption, minItems = 1L, maxItems = 1L)
for (i in seq_along(defs$output$oneOf)) if (identical(
    defs$output$oneOf[[i]]$properties$kind$const, "model_ref"))
  defs$output$oneOf[[i]]$properties$contained_model_sibling_closure_policy$
    properties$required_sibling_terminals$minItems <- 0L
manifest[["$defs"]] <- defs
write(manifest, "operation-pack-v3.schema.json")

# Request -----------------------------------------------------------------
request <- read("operation-pack-transition-request-v3.schema.json")
rdefs <- request[["$defs"]]
source_snapshot <- object(c("entity_kind", "source_id",
  "source_snapshot_id", "source_run_id", "scope", "lifecycle_state",
  "recorded_checksum_status", "declared_content_identity",
  "source_snapshot_identity"), list(entity_kind = list(const =
    "external_source"), source_id = nonempty, source_snapshot_id = nonempty,
    source_run_id = nonempty, scope = nonempty,
    lifecycle_state = list(const = "current"),
    recorded_checksum_status = list(const = "checksummed"),
    declared_content_identity = ref("identity"),
    source_snapshot_identity = ref("self_identity")))
byte_evidence <- object(c("status", "declared_content_identity",
  "observed_content_identity", "nonverification_reason",
  "source_byte_evidence_identity"), list(status = list(enum = list(
    "bytes_verified", "bytes_not_inspected", "bytes_unavailable")),
    declared_content_identity = ref("identity"),
    observed_content_identity = nullable_identity,
    nonverification_reason = nullable_string,
    source_byte_evidence_identity = ref("self_identity")), allOf = list(
      list(`if` = list(properties = list(status = list(const =
        "bytes_verified"))), then = list(properties = list(
          observed_content_identity = ref("identity"),
          nonverification_reason = list(type = "null")))),
      list(`if` = list(properties = list(status = list(const =
        "bytes_not_inspected"))), then = list(properties = list(
          observed_content_identity = list(type = "null"),
          nonverification_reason = list(const =
            "policy_did_not_inspect_external_bytes")))),
      list(`if` = list(properties = list(status = list(const =
        "bytes_unavailable"))), then = list(properties = list(
          observed_content_identity = list(type = "null"),
          nonverification_reason = list(const =
            "external_bytes_unavailable"))))))
candidate <- object(c("selected_state_type", "tree_manifest",
  "tree_manifest_identity", "payload_manifest_identity", "primary_path",
  "file_count", "total_bytes", "ordered_cell_count",
  "ordered_cell_identity", "integrity_status", "relative_root",
  "candidate_snapshot_identity"), list(selected_state_type = model_pair,
    tree_manifest = ref("contained_model_tree_manifest"),
    tree_manifest_identity = ref("identity"),
    payload_manifest_identity = ref("identity"),
    primary_path = ref("relative_root"),
    file_count = integer(minimum = 1L, maximum = 32L),
    total_bytes = integer(minimum = 1L, maximum = 1073741824),
    ordered_cell_count = integer(minimum = 1L, maximum = 10000000),
    ordered_cell_identity = ref("identity"),
    integrity_status = list(const = "authenticated"),
    relative_root = ref("relative_root"),
    candidate_snapshot_identity = ref("self_identity")))
closure_output <- object(c("name", "allocated_id", "kind",
  "output_grant_identity", "terminal_policy", "promotion_group",
  "expected_cell_order_identity_if_cell_indexed"), list(name = name,
    allocated_id = ref("id"), kind = nonempty,
    output_grant_identity = ref("identity"), terminal_policy = nonempty,
    promotion_group = nonempty,
    expected_cell_order_identity_if_cell_indexed = nullable_identity))
closure <- object(c("outputs",
  "contained_model_sibling_write_grant_identity",
  "model_source_linkage_identity", "adopted_closure_identity"), list(
    outputs = array(closure_output, minItems = 1L, maxItems = 16L),
    contained_model_sibling_write_grant_identity = ref("identity"),
    model_source_linkage_identity = ref("identity"),
    adopted_closure_identity = ref("self_identity")))
grant <- object(c("schema", "name", "declaration_identity",
  "source_snapshot", "source_byte_evidence", "candidate_snapshot",
  "contained_model_sibling_write_grant_identity",
  "model_source_linkage_identity", "adopted_closure", "access",
  "call_discipline", "execution_semantics", "grant_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.supported_external_state_adoption_grant.v1"),
    name = name, declaration_identity = ref("identity"),
    source_snapshot = source_snapshot, source_byte_evidence = byte_evidence,
    candidate_snapshot = candidate,
    contained_model_sibling_write_grant_identity = ref("identity"),
    model_source_linkage_identity = ref("identity"),
    adopted_closure = closure,
    access = list(const = "verified_private_copy_read_only_v1"),
    call_discipline = list(const = "adoption_state_exactly_once"),
    execution_semantics = list(const =
      "supported_external_state_adoption_without_refit_v1"),
    grant_identity = ref("self_identity")))
rdefs$external_source_adoption_snapshot <- source_snapshot
rdefs$external_source_byte_evidence <- byte_evidence
rdefs$external_state_candidate_snapshot <- candidate
rdefs$supported_external_state_adoption_closure <- closure
rdefs$supported_external_state_adoption_grant <- grant
request$properties$supported_external_state_adoption_grants <- array(
  ref("supported_external_state_adoption_grant"), minItems = 1L,
  maxItems = 1L)
rdefs$capability$properties$
  supported_external_state_adoption_grant_identities <- array(
    ref("identity"), minItems = 1L, maxItems = 1L)
g3_reader <- object(c("supported_external_state_adoption_name", "reader",
  "grant_identity"), list(supported_external_state_adoption_name = name,
    reader = list(const = "read_supported_external_state"),
    grant_identity = ref("self_identity")))
rdefs$capability$properties$reader_grants$items$oneOf <- c(Filter(function(x)
  !identical(x$properties$reader$const, "read_supported_external_state"),
  rdefs$capability$properties$reader_grants$items$oneOf), list(g3_reader))
request[["$defs"]] <- rdefs
write(request, "operation-pack-transition-request-v3.schema.json")

# Receipt -----------------------------------------------------------------
receipt <- read("operation-pack-transition-receipt-v3.schema.json")
odefs <- receipt[["$defs"]]
observation <- object(c("schema", "name", "grant_identity",
  "source_snapshot_identity", "source_byte_evidence",
  "candidate_snapshot_identity", "candidate_tree_manifest_identity",
  "candidate_payload_manifest_identity", "ordered_cell_count",
  "ordered_cell_identity", "contained_model_sibling_tree_observation_identity",
  "adopted_model_tree_manifest_identity",
  "adopted_model_payload_manifest_identity", "model_source_linkage_identity",
  "adopted_closure_identity", "ordered_observed_output_descriptor_identities",
  "read_count", "event_count", "execution_mode", "upstream_execution",
  "pack_source_association_attestation", "pack_no_refit_attestation",
  "integrity_status", "publication_status", "observation_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.observed_supported_external_state_adoption.v1"),
    name = name, grant_identity = ref("identity"),
    source_snapshot_identity = ref("identity"),
    source_byte_evidence = byte_evidence,
    candidate_snapshot_identity = ref("identity"),
    candidate_tree_manifest_identity = ref("identity"),
    candidate_payload_manifest_identity = ref("identity"),
    ordered_cell_count = integer(minimum = 1L),
    ordered_cell_identity = ref("identity"),
    contained_model_sibling_tree_observation_identity = ref("identity"),
    adopted_model_tree_manifest_identity = ref("identity"),
    adopted_model_payload_manifest_identity = ref("identity"),
    model_source_linkage_identity = ref("identity"),
    adopted_closure_identity = ref("identity"),
    ordered_observed_output_descriptor_identities = array(ref("identity"),
      minItems = 1L, maxItems = 16L), read_count = list(const = 1L),
    event_count = list(const = 1L), execution_mode = list(const =
      "supported_external_state_adoption"), upstream_execution = list(const =
        "external"), pack_source_association_attestation = list(const = TRUE),
    pack_no_refit_attestation = list(const = TRUE),
    integrity_status = list(const = "unchanged"),
    publication_status = list(const = "validated_not_published"),
    observation_identity = ref("self_identity")))
odefs$external_source_byte_evidence <- byte_evidence
odefs$supported_external_state_adoption_observation <- observation
receipt$properties$supported_external_state_adoption_observations <- array(
  ref("supported_external_state_adoption_observation"), minItems = 1L,
  maxItems = 1L)
receipt[["$defs"]] <- odefs
write(receipt, "operation-pack-transition-receipt-v3.schema.json")
