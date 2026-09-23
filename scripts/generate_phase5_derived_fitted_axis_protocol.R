#!/usr/bin/env Rscript

# Deterministically installs the additive Phase 5 derived-fitted-axis protocol
# into the frozen ABI-v3 documents. Existing protocol cases are retained.

library(jsonlite)
args <- commandArgs(FALSE)
script <- sub("^--file=", "", args[grep("^--file=", args)][1L])
root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")
read <- function(name) read_json(file.path(protocol, name), simplifyVector = FALSE)
normalize_object_order <- function(value) {
  if (!is.list(value)) return(value)
  if (!is.null(names(value))) value <- value[order(names(value),
    method = "radix")]
  lapply(value, normalize_object_order)
}
write <- function(x, name) {
  # This generator owns the DFA additions, not later additive ABI fields.
  # Preserve an already-equivalent document's exact frozen protocol bytes.
  stable_json <- function(value) as.character(toJSON(
    normalize_object_order(value), auto_unbox = TRUE, null = "null",
    na = "null", digits = NA))
  if (identical(stable_json(read(name)), stable_json(x)))
    return(invisible(FALSE))
  writeChar(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null",
    na = "null", digits = NA), file.path(protocol, name), eos = NULL,
    useBytes = TRUE)
}
ref <- function(name) list(`$ref` = paste0("#/$defs/", name))
obj <- function(required, properties) list(type = "object",
  additionalProperties = FALSE, required = as.list(required),
  properties = properties)
arr <- function(items, min = 0L, max = NULL, unique = FALSE) {
  out <- list(type = "array", items = items, minItems = min)
  if (!is.null(max)) out$maxItems <- max
  if (isTRUE(unique)) out$uniqueItems <- TRUE
  out
}
str <- function(pattern = NULL, const = NULL) {
  out <- list(type = "string", minLength = 1L)
  if (!is.null(pattern)) out$pattern <- pattern
  if (!is.null(const)) { out$type <- NULL; out$minLength <- NULL;
    out$const <- const }
  out
}
id <- ref("identity")
self <- function(scheme, scope) obj(c("scheme", "scope", "sha256"), list(
  scheme = list(const = scheme), scope = list(const = scope),
  sha256 = ref("sha256")))
name <- str("^[a-z][a-z0-9_]*$")

manifest_name <- "operation-pack-v3.schema.json"
m <- read(manifest_name)
sibling_fields <- list(name = name, kind = NULL, coverage_policy = NULL)
sibling <- list(oneOf = list(
  obj(c("name", "kind", "coverage_policy"), c(sibling_fields["name"],
    list(kind = list(const = "cell_vector"),
      coverage_policy = list(const = "exact_fitted_axis_v1")))),
  obj(c("name", "kind", "coverage_policy"), c(sibling_fields["name"],
    list(kind = list(const = "cell_vector_family"), coverage_policy =
      list(enum = as.list(c("exact_fitted_axis_v1",
        "per_key_source_relative_subset_v1"))))))))
policy <- obj(c("schema", "mode", "source_space_input", "model_output",
  "required_siblings", "declaration_discipline", "maximum_selected_cells",
  "maximum_combined_id_bytes", "maximum_id_bytes", "maximum_family_keys",
  "policy_identity"), list(
  schema = list(const = "scworkbench.operation_pack.derived_fitted_axis_policy.v1"),
  mode = list(const = "source_relative_subset_v1"),
  source_space_input = name, model_output = name,
  required_siblings = arr(sibling, 1L, 64L),
  declaration_discipline = list(const =
    "exactly_once_before_cell_indexed_writes"),
  maximum_selected_cells = list(type = "integer", minimum = 1L,
    maximum = 1000000L),
  maximum_combined_id_bytes = list(type = "integer", minimum = 1L,
    maximum = 67108864L),
  maximum_id_bytes = list(type = "integer", minimum = 1L, maximum = 1024L),
  maximum_family_keys = list(type = "integer", minimum = 1L, maximum = 64L),
  policy_identity = self(
    "scworkbench.operation_pack.derived_fitted_axis_policy.v1",
    "policy excluding policy_identity")))
model_index <- which(vapply(m$`$defs`$output$oneOf, function(x)
  identical(x$properties$kind$const, "model_ref"), logical(1)))
m$`$defs`$output$oneOf[[model_index]]$properties$derived_fitted_axis_policy <- policy
write(m, manifest_name)

request_name <- "operation-pack-transition-request-v3.schema.json"
q <- read(request_name)
q$`$defs`$fitted_axis_parent_snapshot <- obj(c("schema", "source_space_id",
  "full_content_identity", "durable_payload_snapshot_identity",
  "full_cell_count", "full_cell_order_identity", "selected_dimension_count",
  "selected_dimension_ids", "selected_dimension_order_identity",
  "parent_snapshot_identity"), list(
  schema = list(const = "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1"),
  source_space_id = str(), full_content_identity = id,
  durable_payload_snapshot_identity = id,
  full_cell_count = list(type = "integer", minimum = 1L),
  full_cell_order_identity = id,
  selected_dimension_count = list(type = "integer", minimum = 1L),
  selected_dimension_ids = arr(str(), 1L, unique = TRUE),
  selected_dimension_order_identity = id,
  parent_snapshot_identity = self(
    "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
    "parent snapshot excluding parent_snapshot_identity")))
q$`$defs`$derived_fitted_session <- obj(c("schema",
  "parent_snapshot_identity", "source_input_name",
  "source_input_descriptor_identity", "source_input_content_identity",
  "session_cell_ids", "session_cell_count", "session_cell_order_identity",
  "selected_dimension_order_identity", "session_identity"), list(
  schema = list(const = "scworkbench.operation_pack.derived_fitted_session.v1"),
  parent_snapshot_identity = id, source_input_name = name,
  source_input_descriptor_identity = id, source_input_content_identity = id,
  session_cell_ids = arr(str(), 1L, 1000000L, unique = TRUE),
  session_cell_count = list(type = "integer", minimum = 1L, maximum = 1000000L),
  session_cell_order_identity = id, selected_dimension_order_identity = id,
  session_identity = self("scworkbench.operation_pack.derived_fitted_session.v1",
    "session projection excluding session_identity")))
model_limits <- obj(c("maximum_file_count", "maximum_total_bytes"), list(
  maximum_file_count = list(type = "integer", minimum = 1L, maximum = 32L),
  maximum_total_bytes = list(type = "integer", minimum = 1L,
    maximum = 1073741824)))
base_grant <- obj(c("name", "grant_identity", "engine", "model_type",
  "primary_path", "relative_root", "promotion_group", "limits"), list(
  name = name, grant_identity = id, engine = str(), model_type = str(),
  primary_path = str(), relative_root = ref("relative_root"),
  promotion_group = name, limits = model_limits))
sibling_base_fields <- function(kind, coverage) obj(c("name", "kind",
  "coverage_policy", "promotion_group", "grant_identity"), list(name = name,
  kind = list(const = kind), coverage_policy = coverage,
  promotion_group = name, grant_identity = id))
sibling_base <- list(oneOf = list(sibling_base_fields("cell_vector",
  list(const = "exact_fitted_axis_v1")),
  sibling_base_fields("cell_vector_family", list(enum = as.list(c(
    "exact_fitted_axis_v1", "per_key_source_relative_subset_v1"))))))
limits <- obj(c("maximum_selected_cells", "maximum_combined_id_bytes",
  "maximum_id_bytes", "maximum_family_keys"), list(
  maximum_selected_cells = list(type = "integer", minimum = 1L, maximum = 1000000L),
  maximum_combined_id_bytes = list(type = "integer", minimum = 1L,
    maximum = 67108864L),
  maximum_id_bytes = list(type = "integer", minimum = 1L, maximum = 1024L),
  maximum_family_keys = list(type = "integer", minimum = 1L, maximum = 64L)))
q$`$defs`$derived_fitted_axis_grant <- obj(c("schema", "policy_identity",
  "parent_snapshot", "session_projection", "transition_identity",
  "model_base_grant", "sibling_base_grants", "limits",
  "declaration_discipline", "grant_identity"), list(
  schema = list(const = "scworkbench.operation_pack.derived_fitted_axis_grant.v1"),
  policy_identity = id, parent_snapshot = ref("fitted_axis_parent_snapshot"),
  session_projection = ref("derived_fitted_session"), transition_identity = id,
  model_base_grant = base_grant, sibling_base_grants = arr(sibling_base, 1L, 64L),
  limits = limits, declaration_discipline = list(const =
    "exactly_once_before_cell_indexed_writes"),
  grant_identity = self("scworkbench.operation_pack.derived_fitted_axis_grant.v1",
    "provisional grant excluding grant_identity")))
q$properties$derived_fitted_axis_grants <- arr(ref("derived_fitted_axis_grant"),
  1L, 1L)
q$`$defs`$capability$properties$derived_fitted_axis_grant_identities <-
  arr(id, 1L, 1L)
write(q, request_name)

receipt_name <- "operation-pack-transition-receipt-v3.schema.json"
r <- read(receipt_name)
r$`$defs`$relative_root <- q$`$defs`$relative_root
# Receipt protocol objects are closed at every newly introduced layer. The
# authenticated seal/linkage subobjects use their exact field sets.
evidence <- obj(c("relative_path", "sha256", "evidence_identity"), list(
  relative_path = list(const = ".scworkbench/selected-axis-v1.json"),
  sha256 = ref("sha256"), evidence_identity = id))
seal <- obj(c("schema", "provisional_grant_identity", "declaration_identity",
  "parent_snapshot_identity", "session_identity", "fitted_cell_ids",
  "fitted_cell_count", "fitted_cell_order_identity", "relation",
  "seal_identity"), list(
  schema = list(const = "scworkbench.operation_pack.derived_fitted_axis_seal.v1"),
  provisional_grant_identity = id, declaration_identity = id,
  parent_snapshot_identity = id, session_identity = id,
  fitted_cell_ids = arr(str(), 1L, 1000000L, unique = TRUE),
  fitted_cell_count = list(type = "integer", minimum = 1L, maximum = 1000000L),
  fitted_cell_order_identity = id,
  relation = list(const = "source_relative_ordered_subset_v1"),
  seal_identity = self("scworkbench.operation_pack.derived_fitted_axis_seal.v1",
    "seal excluding seal_identity")))
linkage <- obj(c("schema", "engine", "model_type", "source_space_id",
  "parent_snapshot_identity", "session_identity", "fitted_axis_seal_identity",
  "fitted_cell_order_identity", "selected_dimension_count",
  "selected_dimension_ids", "selected_dimension_order_identity",
  "selected_axis_evidence",
  "linkage_identity"), list(
  schema = list(const = "scworkbench.operation_pack.model_source_linkage.v3"),
  engine = str(), model_type = str(), source_space_id = str(),
  parent_snapshot_identity = id, session_identity = id,
  fitted_axis_seal_identity = id, fitted_cell_order_identity = id,
  selected_dimension_count = list(type = "integer", minimum = 1L),
  selected_dimension_ids = arr(str(), 1L, unique = TRUE),
  selected_dimension_order_identity = id, selected_axis_evidence = evidence,
  linkage_identity = self("scworkbench.operation_pack.model_source_linkage.v3",
    "linkage excluding linkage_identity")))
sealed_model <- obj(c("schema", "output", "base_grant_identity",
  "fitted_axis_seal_identity", "engine", "model_type", "primary_path",
  "relative_root", "source_space_id", "selected_dimension_count",
  "selected_dimension_ids", "selected_dimension_order_identity",
  "selected_axis_evidence", "limits", "sealed_grant_identity"), list(
  schema = list(const =
    "scworkbench.operation_pack.sealed_model_sibling_grant.v1"),
  output = name, base_grant_identity = id, fitted_axis_seal_identity = id,
  engine = str(), model_type = str(), primary_path = str(),
  relative_root = ref("relative_root"), source_space_id = str(),
  selected_dimension_count = list(type = "integer", minimum = 1L),
  selected_dimension_ids = arr(str(), 1L, unique = TRUE),
  selected_dimension_order_identity = id, selected_axis_evidence = evidence,
  limits = model_limits, sealed_grant_identity = self(
    "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
    "sealed model grant excluding sealed_grant_identity")))
sealed_sibling_fields <- function(kind, coverage) obj(c("schema", "name",
  "kind", "coverage_policy", "base_grant_identity",
  "fitted_axis_seal_identity", "promotion_group",
  "sealed_grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.sealed_sibling_output_grant.v1"),
  name = name, kind = list(const = kind), coverage_policy = coverage,
  base_grant_identity = id, fitted_axis_seal_identity = id,
  promotion_group = name, sealed_grant_identity = self(
    "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
    "sealed sibling grant excluding sealed_grant_identity")))
sealed_sibling <- list(oneOf = list(sealed_sibling_fields("cell_vector",
  list(const = "exact_fitted_axis_v1")),
  sealed_sibling_fields("cell_vector_family", list(enum = as.list(c(
    "exact_fitted_axis_v1", "per_key_source_relative_subset_v1"))))))
per_key <- obj(c("key", "cell_count", "cell_order_identity"), list(
  key = str(), cell_count = list(type = "integer", minimum = 1L),
  cell_order_identity = id))
coverage_required <- c("schema", "sealed_sibling_grant_identity",
  "output_name", "kind", "coverage_policy", "fitted_axis_seal_identity",
  "observed_keys", "per_key_coverage", "coverage_status",
  "output_observed_descriptor_identity", "output_content_identity",
  "observation_identity")
coverage_common <- list(
  schema = list(const = "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1"),
  sealed_sibling_grant_identity = id, output_name = name,
  fitted_axis_seal_identity = id,
  coverage_status = list(const = "validated"),
  output_observed_descriptor_identity = id, output_content_identity = id,
  observation_identity = self(
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
    "coverage observation excluding observation_identity"))
vector_coverage <- obj(coverage_required, c(coverage_common, list(
  kind = list(const = "cell_vector"),
  coverage_policy = list(const = "exact_fitted_axis_v1"),
  observed_keys = arr(str(), 0L, 0L),
  per_key_coverage = arr(per_key, 0L, 0L))))
family_coverage <- obj(coverage_required, c(coverage_common, list(
  kind = list(const = "cell_vector_family"),
  coverage_policy = list(enum = as.list(c("exact_fitted_axis_v1",
    "per_key_source_relative_subset_v1"))),
  observed_keys = arr(str(), 1L, 64L, unique = TRUE),
  per_key_coverage = arr(per_key, 1L, 64L))))
coverage <- list(oneOf = list(vector_coverage, family_coverage))
observation <- obj(c("schema", "provisional_grant_identity", "model_output",
  "declaration_identity", "seal", "sealed_model_grant",
  "sealed_sibling_grants", "selected_axis_evidence",
  "model_source_linkage", "model_tree_manifest_identity",
  "model_payload_manifest_identity", "model_observed_descriptor_identity",
  "sibling_coverage_observations", "closure_status", "observation_identity"), list(
  schema = list(const = "scworkbench.operation_pack.observed_derived_fitted_axis.v1"),
  provisional_grant_identity = id, model_output = name,
  declaration_identity = id, seal = ref("derived_fitted_axis_seal"),
  sealed_model_grant = ref("sealed_model_sibling_grant"),
  sealed_sibling_grants = arr(ref("sealed_sibling_output_grant"), 1L, 64L),
  selected_axis_evidence = ref("selected_axis_evidence_descriptor"),
  model_source_linkage = ref("model_source_linkage_v3"),
  model_tree_manifest_identity = id,
  model_payload_manifest_identity = id, model_observed_descriptor_identity = id,
  sibling_coverage_observations = arr(
    ref("observed_sealed_sibling_coverage"), 1L, 64L),
  closure_status = list(const = "complete"),
  observation_identity = self(
    "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
    "observation excluding observation_identity")))
r$`$defs`$derived_fitted_axis_observation <- observation
r$`$defs`$derived_fitted_axis_seal <- seal
r$`$defs`$selected_axis_evidence_descriptor <- evidence
r$`$defs`$model_source_linkage_v3 <- linkage
r$`$defs`$sealed_model_sibling_grant <- sealed_model
r$`$defs`$sealed_sibling_output_grant <- sealed_sibling
r$`$defs`$observed_sealed_sibling_coverage <- coverage
r$properties$derived_fitted_axis_observations <- arr(
  ref("derived_fitted_axis_observation"), 1L, 1L)
tree <- obj(c("schema", "sealed_model_grant_identity", "tree_manifest",
  "tree_manifest_identity", "payload_manifest_identity",
  "model_source_linkage_identity", "status", "observation_identity"), list(
  schema = list(const =
    "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1"),
  sealed_model_grant_identity = id,
  tree_manifest = ref("contained_model_tree_manifest"),
  tree_manifest_identity = id, payload_manifest_identity = id,
  model_source_linkage_identity = id, status = list(const = "complete"),
  observation_identity = self(
    "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1",
    "observation excluding observation_identity")))
r$`$defs`$derived_fitted_model_tree_observation <- tree
model_index <- which(vapply(r$`$defs`$observed_output_descriptor$oneOf,
  function(x) identical(x$properties$kind$const, "model_ref"), logical(1)))
r$`$defs`$observed_output_descriptor$oneOf[[model_index]]$properties$
  contained_model_sibling_tree <- list(oneOf = list(
    ref("contained_model_sibling_tree_observation"),
    ref("derived_fitted_model_tree_observation")))
write(r, receipt_name)

# Private/transient shapes are shared protocol even though they are not all
# serialized as top-level request fields.
q <- read(request_name)
q$`$defs`$derived_fitted_axis_declaration <- obj(c("schema",
  "provisional_grant_identity", "fitted_cell_ids", "fitted_cell_count",
  "declaration_identity"), list(schema = list(const =
    "scworkbench.operation_pack.derived_fitted_axis_declaration.v1"),
  provisional_grant_identity = id,
  fitted_cell_ids = arr(str(), 1L, 1000000L, unique = TRUE),
  fitted_cell_count = list(type = "integer", minimum = 1L, maximum = 1000000L),
  declaration_identity = self(
    "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
    "declaration excluding declaration_identity")))
q$`$defs`$selected_axis_evidence_sidecar <- obj(c("schema",
  "parent_snapshot_identity", "session_identity", "session_cell_ids",
  "fitted_cell_ids", "seal_identity"), list(schema = list(const =
    "scworkbench.operation_pack.selected_axis_evidence.v1"),
  parent_snapshot_identity = id, session_identity = id,
  session_cell_ids = arr(str(), 1L, 1000000L, unique = TRUE),
  fitted_cell_ids = arr(str(), 1L, 1000000L, unique = TRUE),
  seal_identity = id))
q$`$defs`$sealed_model_sibling_grant <- sealed_model
q$`$defs`$sealed_sibling_output_grant <- sealed_sibling
q$`$defs`$model_source_linkage_v3 <- linkage
q$`$defs`$derived_fitted_axis_seal <- seal
write(q, request_name)

# Append a coherent cross-language identity chain without perturbing accepted
# G3/G7 cases. The corpus uses only language-neutral canonical JSON v1.
fixture_name <- file.path("fixtures", "operation-pack-v3", "identities.json")
fixture <- read(fixture_name)
identity_env <- new.env(parent = globalenv())
sys.source(file.path(root, "R", "operation_packs.R"), envir = identity_env)
hash <- function(x) digest::digest(
  identity_env$.wb_operation_pack_canonical_json(x), "sha256",
  serialize = FALSE)
plain <- function(scheme, x) list(scheme = scheme, sha256 = hash(x))
scoped <- function(scheme, scope, x) list(scheme = scheme, scope = scope,
  sha256 = hash(x))
unscoped <- function(x) list(scheme = x$scheme, sha256 = x$sha256)
signed <- function(name, scheme, scope, value, field) {
  value[[field]] <- scoped(scheme, scope, value)
  list(name = name, preimage = value[names(value) != field],
    identity = value[[field]], value = value)
}
token <- function(letter, scheme = "fixture.identity.v1")
  list(scheme = scheme, sha256 = paste(rep(letter, 64L), collapse = ""))
policy_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_axis_policy.v1",
  mode = "source_relative_subset_v1", source_space_input = "source",
  model_output = "model", required_siblings = list(
    list(name = "embedding", kind = "cell_vector",
      coverage_policy = "exact_fitted_axis_v1"),
    list(name = "weights", kind = "cell_vector_family",
      coverage_policy = "per_key_source_relative_subset_v1")),
  declaration_discipline = "exactly_once_before_cell_indexed_writes",
  maximum_selected_cells = 1000000L,
  maximum_combined_id_bytes = 67108864L, maximum_id_bytes = 1024L,
  maximum_family_keys = 64L)
policy_case <- signed("dfa_manifest_policy",
  "scworkbench.operation_pack.derived_fitted_axis_policy.v1",
  "policy excluding policy_identity", policy_value, "policy_identity")
parent_value <- list(schema =
    "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
  source_space_id = "pca", full_content_identity = token("a",
    "scworkbench.space.content.v1"), durable_payload_snapshot_identity = token("b",
    "scworkbench.space.payload.v1"), full_cell_count = 4L,
  full_cell_order_identity = plain("scworkbench.cell_order.v1",
    as.list(c("cell_2", "cell_10", "cell_1", "cell_3"))),
  selected_dimension_count = 2L,
  selected_dimension_ids = as.list(c("PC1", "PC3")),
  selected_dimension_order_identity = plain("scworkbench.dimension_order.v1",
    as.list(c("PC1", "PC3"))))
parent_case <- signed("dfa_full_parent_snapshot",
  "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
  "parent snapshot excluding parent_snapshot_identity", parent_value,
  "parent_snapshot_identity")
session_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_session.v1",
  parent_snapshot_identity = unscoped(parent_case$identity),
  source_input_name = "source", source_input_descriptor_identity = token("c"),
  source_input_content_identity = token("d", "scworkbench.space.content.v1"),
  session_cell_ids = as.list(c("cell_2", "cell_1", "cell_3")),
  session_cell_count = 3L, session_cell_order_identity = plain(
    "scworkbench.cell_order.v1", as.list(c("cell_2", "cell_1", "cell_3"))),
  selected_dimension_order_identity = parent_value$
    selected_dimension_order_identity)
session_case <- signed("dfa_session_projection",
  "scworkbench.operation_pack.derived_fitted_session.v1",
  "session projection excluding session_identity", session_value,
  "session_identity")
limits_value <- list(maximum_selected_cells = 1000000L,
  maximum_combined_id_bytes = 67108864, maximum_id_bytes = 1024L,
  maximum_family_keys = 64L)
grant_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
  policy_identity = unscoped(policy_case$identity),
  parent_snapshot = parent_case$value, session_projection = session_case$value,
  transition_identity = token("e"), model_base_grant = list(name = "model",
    grant_identity = token("f"), engine = "fixture",
    model_type = "derived_axis_model", primary_path = "model.bin",
    relative_root = "outputs/model/model_tree", promotion_group = "fit",
    limits = list(maximum_file_count = 32L,
      maximum_total_bytes = 1073741824)), sibling_base_grants = list(
      list(name = "embedding", kind = "cell_vector",
        coverage_policy = "exact_fitted_axis_v1", promotion_group = "fit",
        grant_identity = token("1")),
      list(name = "weights", kind = "cell_vector_family",
        coverage_policy = "per_key_source_relative_subset_v1",
        promotion_group = "fit",
        grant_identity = token("2"))), limits = limits_value,
  declaration_discipline = "exactly_once_before_cell_indexed_writes")
grant_case <- signed("dfa_provisional_grant",
  "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
  "provisional grant excluding grant_identity", grant_value, "grant_identity")
declaration_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
  provisional_grant_identity = unscoped(grant_case$identity),
  fitted_cell_ids = as.list(c("cell_2", "cell_3")), fitted_cell_count = 2L)
declaration_case <- signed("dfa_private_declaration",
  "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
  "declaration excluding declaration_identity", declaration_value,
  "declaration_identity")
seal_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
  provisional_grant_identity = unscoped(grant_case$identity),
  declaration_identity = unscoped(declaration_case$identity),
  parent_snapshot_identity = unscoped(parent_case$identity),
  session_identity = unscoped(session_case$identity),
  fitted_cell_ids = declaration_value$fitted_cell_ids, fitted_cell_count = 2L,
  fitted_cell_order_identity = plain("scworkbench.cell_order.v1",
    declaration_value$fitted_cell_ids), relation =
    "source_relative_ordered_subset_v1")
seal_case <- signed("dfa_sealed_axis",
  "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
  "seal excluding seal_identity", seal_value, "seal_identity")
sidecar <- list(schema = "scworkbench.operation_pack.selected_axis_evidence.v1",
  parent_snapshot_identity = seal_value$parent_snapshot_identity,
  session_identity = seal_value$session_identity,
  session_cell_ids = session_value$session_cell_ids,
  fitted_cell_ids = seal_value$fitted_cell_ids,
  seal_identity = unscoped(seal_case$identity))
sidecar_case <- list(name = "dfa_selected_axis_sidecar", preimage = sidecar,
  identity = plain("scworkbench.operation_pack.selected_axis_evidence.v1",
    sidecar), value = sidecar)
evidence_value <- list(relative_path = ".scworkbench/selected-axis-v1.json",
  sha256 = hash(sidecar), evidence_identity = sidecar_case$identity)
linkage_value <- list(schema =
    "scworkbench.operation_pack.model_source_linkage.v3", engine = "fixture",
  model_type = "derived_axis_model", source_space_id = "pca",
  parent_snapshot_identity = unscoped(parent_case$identity),
  session_identity = unscoped(session_case$identity),
  fitted_axis_seal_identity = unscoped(seal_case$identity),
  fitted_cell_order_identity = seal_value$fitted_cell_order_identity,
  selected_dimension_count = 2L,
  selected_dimension_ids = parent_value$selected_dimension_ids,
  selected_dimension_order_identity = parent_value$
    selected_dimension_order_identity, selected_axis_evidence = evidence_value)
linkage_case <- signed("dfa_model_source_linkage_v3",
  "scworkbench.operation_pack.model_source_linkage.v3",
  "linkage excluding linkage_identity", linkage_value, "linkage_identity")
model_grant_value <- list(schema =
    "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
  output = "model", base_grant_identity = grant_value$model_base_grant$
    grant_identity, fitted_axis_seal_identity = unscoped(seal_case$identity),
  engine = "fixture", model_type = "derived_axis_model",
  primary_path = "model.bin", relative_root = "outputs/model/model_tree",
  source_space_id = "pca", selected_dimension_count = 2L,
  selected_dimension_ids = parent_value$selected_dimension_ids,
  selected_dimension_order_identity = parent_value$
    selected_dimension_order_identity, selected_axis_evidence = evidence_value,
  limits = list(maximum_file_count = 32L,
    maximum_total_bytes = 1073741824))
model_grant_case <- signed("dfa_sealed_model_grant",
  "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
  "sealed model grant excluding sealed_grant_identity", model_grant_value,
  "sealed_grant_identity")
sealed_sibling <- function(case_name, index) {
  item <- grant_value$sibling_base_grants[[index]]
  value <- list(schema =
      "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
    name = item$name, kind = item$kind, coverage_policy = item$coverage_policy,
    base_grant_identity = item$grant_identity,
    fitted_axis_seal_identity = unscoped(seal_case$identity),
    promotion_group = item$promotion_group)
  signed(case_name,
    "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
    "sealed sibling grant excluding sealed_grant_identity", value,
    "sealed_grant_identity")
}
embedding_grant_case <- sealed_sibling("dfa_sealed_embedding_grant", 1L)
weights_grant_case <- sealed_sibling("dfa_sealed_weights_grant", 2L)
embedding_descriptor <- token("3",
  "scworkbench.operation_pack.observed_output.v3")
embedding_content <- token("4", "scworkbench.cell_vector.content.v1")
weights_descriptor <- token("5",
  "scworkbench.operation_pack.observed_output.v3")
weights_content <- token("6", "scworkbench.cell_vector_family.content.v1")
exact_coverage_value <- list(schema =
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
  sealed_sibling_grant_identity = unscoped(embedding_grant_case$identity),
  output_name = "embedding", kind = "cell_vector",
  coverage_policy = "exact_fitted_axis_v1",
  fitted_axis_seal_identity = unscoped(seal_case$identity),
  observed_keys = list(), per_key_coverage = list(),
  coverage_status = "validated",
  output_observed_descriptor_identity = embedding_descriptor,
  output_content_identity = embedding_content)
exact_coverage_case <- signed("dfa_exact_vector_coverage",
  "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
  "coverage observation excluding observation_identity",
  exact_coverage_value, "observation_identity")
sparse_coverage_value <- list(schema =
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
  sealed_sibling_grant_identity = unscoped(weights_grant_case$identity),
  output_name = "weights", kind = "cell_vector_family",
  coverage_policy = "per_key_source_relative_subset_v1",
  fitted_axis_seal_identity = unscoped(seal_case$identity),
  observed_keys = as.list(c("lineage_a", "lineage_b")),
  per_key_coverage = list(
    list(key = "lineage_a", cell_count = 2L,
      cell_order_identity = seal_value$fitted_cell_order_identity),
    list(key = "lineage_b", cell_count = 1L,
      cell_order_identity = plain("scworkbench.cell_order.v1",
        as.list("cell_2")))), coverage_status = "validated",
  output_observed_descriptor_identity = weights_descriptor,
  output_content_identity = weights_content)
sparse_coverage_case <- signed("dfa_sparse_family_coverage",
  "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
  "coverage observation excluding observation_identity",
  sparse_coverage_value, "observation_identity")
case_named <- function(value) fixture$cases[[match(value,
  vapply(fixture$cases, `[[`, character(1), "name"))]]
tree_manifest_case <- case_named("contained_model_tree_manifest")
payload_manifest_case <- case_named("contained_model_payload_manifest")
tree_observation_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1",
  sealed_model_grant_identity = unscoped(model_grant_case$identity),
  tree_manifest = tree_manifest_case$value,
  tree_manifest_identity = unscoped(tree_manifest_case$identity),
  payload_manifest_identity = payload_manifest_case$identity,
  model_source_linkage_identity = unscoped(linkage_case$identity),
  status = "complete")
tree_observation_case <- signed("dfa_derived_model_tree_observation",
  "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1",
  "observation excluding observation_identity", tree_observation_value,
  "observation_identity")
model_content_preimage <- list(engine = "fixture",
  model_type = "derived_axis_model",
  linkage_identity = unscoped(linkage_case$identity),
  tree_manifest_identity = unscoped(tree_manifest_case$identity))
model_content_case <- list(name = "dfa_model_content_identity",
  preimage = model_content_preimage,
  identity = plain("scworkbench.model_ref.content.v1",
    model_content_preimage), value = model_content_preimage)
model_descriptor_preimage <- list(output = "model",
  content_identity = model_content_case$identity,
  payload_manifest_identity = payload_manifest_case$identity,
  model_source_linkage_identity = unscoped(linkage_case$identity),
  tree_observation_identity = unscoped(tree_observation_case$identity))
model_descriptor_case <- list(name = "dfa_model_observed_descriptor",
  preimage = model_descriptor_preimage,
  identity = scoped("scworkbench.operation_pack.observed_output.v3",
    "descriptor excluding observed_descriptor_identity",
    model_descriptor_preimage), value = model_descriptor_preimage)
observation_value <- list(schema =
    "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
  provisional_grant_identity = unscoped(grant_case$identity),
  model_output = "model",
  declaration_identity = unscoped(declaration_case$identity),
  seal = seal_case$value, sealed_model_grant = model_grant_case$value,
  sealed_sibling_grants = list(embedding_grant_case$value,
    weights_grant_case$value), selected_axis_evidence = evidence_value,
  model_source_linkage = linkage_case$value,
  model_tree_manifest_identity = unscoped(tree_manifest_case$identity),
  model_payload_manifest_identity = payload_manifest_case$identity,
  model_observed_descriptor_identity = model_descriptor_case$identity,
  sibling_coverage_observations = list(exact_coverage_case$value,
    sparse_coverage_case$value), closure_status = "complete")
observation_case <- signed("dfa_complete_observation",
  "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
  "observation excluding observation_identity", observation_value,
  "observation_identity")
# A second full-axis chain proves that subset cardinality changes identity.
full_session_value <- session_value
full_session_value$session_cell_ids <- parent_value$
  full_cell_order_identity # replaced immediately with the retained preimage
full_session_value$session_cell_ids <- as.list(c("cell_2", "cell_10",
  "cell_1", "cell_3"))
full_session_value$session_cell_count <- 4L
full_session_value$session_cell_order_identity <- parent_value$
  full_cell_order_identity
full_session_value$session_identity <- NULL
full_session_case <- signed("dfa_full_axis_session",
  "scworkbench.operation_pack.derived_fitted_session.v1",
  "session projection excluding session_identity", full_session_value,
  "session_identity")
full_grant_value <- grant_value
full_grant_value$session_projection <- full_session_case$value
full_grant_value$grant_identity <- NULL
full_grant_case <- signed("dfa_full_axis_provisional_grant",
  "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
  "provisional grant excluding grant_identity", full_grant_value,
  "grant_identity")
full_declaration_value <- list(schema =
    "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
  provisional_grant_identity = unscoped(full_grant_case$identity),
  fitted_cell_ids = full_session_value$session_cell_ids,
  fitted_cell_count = 4L)
full_declaration_case <- signed("dfa_full_axis_declaration",
  "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
  "declaration excluding declaration_identity", full_declaration_value,
  "declaration_identity")
full_seal_value <- seal_value
full_seal_value$provisional_grant_identity <- unscoped(full_grant_case$identity)
full_seal_value$declaration_identity <- unscoped(full_declaration_case$identity)
full_seal_value$session_identity <- unscoped(full_session_case$identity)
full_seal_value$fitted_cell_ids <- full_declaration_value$fitted_cell_ids
full_seal_value$fitted_cell_count <- 4L
full_seal_value$fitted_cell_order_identity <- parent_value$
  full_cell_order_identity
full_seal_value$seal_identity <- NULL
full_seal_case <- signed("dfa_full_axis_seal",
  "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
  "seal excluding seal_identity", full_seal_value, "seal_identity")
# Complete schema-valid request/receipt envelopes. These are deliberately
# synthetic but internally coherent: every grant, descriptor, seal and
# observation reference is the identity of the exact nested fixture value.
full_input_descriptor <- list(kind = "space",
  storage_profile = "space_dense_v1", reader = "read_space",
  dimensions = list(3L, 3L), alignment = "cell_ordered",
  content_identity = session_value$source_input_content_identity,
  ancestry_identity = token("7", "scworkbench.provenance.ancestry.v1"),
  payload_manifest_identity = token("8", "scworkbench.payload.manifest.v2"),
  cell_order_identity = session_value$session_cell_order_identity)
full_input_descriptor$descriptor_identity <- scoped(
  "scworkbench.operation_pack.input_descriptor.v2",
  "descriptor excluding descriptor_identity", full_input_descriptor)
request_output <- function(name_value, allocated, kind, storage, writer,
    dimensions, alignment, ancestry, linkage_value, constraints,
    cell_order = NULL, contained = FALSE) {
  descriptor <- list(category = "terminal_artifact", kind = kind,
    storage_profile = storage, writer = writer,
    relative_root = paste0("outputs/", name_value),
    expected_dimensions = as.list(dimensions),
    expected_alignment = alignment,
    expected_ancestry_identity = ancestry,
    expected_model_linkage = linkage_value,
    semantic_constraints = constraints)
  if (!is.null(cell_order)) descriptor$expected_cell_order_identity <-
    cell_order
  if (contained) descriptor$contained_payload_requirements <- list(
    contained = TRUE, no_symlinks = TRUE, manifest_scheme =
      "scworkbench.operation_pack.payload_manifest.v2")
  descriptor$grant_identity <- scoped(
    "scworkbench.operation_pack.output_grant.v3",
    "descriptor excluding grant_identity", descriptor)
  list(name = name_value, allocated_id = allocated, descriptor = descriptor)
}
full_outputs <- list(
  request_output("model", "model_id_fixture", "model_ref",
    "model_ref_contained_tree_v1", "write_model_ref", 1L, "model_linked",
    token("9", "scworkbench.provenance.ancestry.v1"),
    list(mode = "input", reference_name = "source", reference_identity =
      unscoped(full_input_descriptor$descriptor_identity)),
    list(engine = "fixture", contained = TRUE, no_symlinks = TRUE),
    contained = TRUE),
  request_output("embedding", "embedding_id_fixture", "cell_vector",
    "terminal_primitive_v1", "write_terminal_primitive", 3L,
    "cell_ordered", token("0", "scworkbench.provenance.ancestry.v1"),
    list(mode = "none"), list(value_kind = "continuous",
      missing_values = "forbidden"),
    session_value$session_cell_order_identity),
  request_output("weights", "weights_id_fixture", "cell_vector_family",
    "terminal_primitive_v1", "write_terminal_primitive", c(3L, 3L),
    "cell_ordered", token("a", "scworkbench.provenance.ancestry.v1"),
    list(mode = "none"), list(value_kind = "continuous",
      missing_values = "forbidden"),
    session_value$session_cell_order_identity))
transition <- list(transition_id = "transition_fixture",
  session_id = "session_fixture", run_id = "run_fixture",
  checkpoint_generation = "ephemeral", source_state_identity = token("4",
    "scworkbench.scientific_state.v1"))
transition$transition_identity <- scoped(
  "scworkbench.operation_pack.transition.v2",
  "transition excluding transition_identity", transition)
full_grant_value <- grant_value
full_grant_value$transition_identity <- unscoped(
  transition$transition_identity)
full_grant_value$session_projection$source_input_descriptor_identity <-
  unscoped(full_input_descriptor$descriptor_identity)
full_grant_value$session_projection$session_identity <- NULL
full_grant_value$session_projection$session_identity <- scoped(
  "scworkbench.operation_pack.derived_fitted_session.v1",
  "session projection excluding session_identity",
  full_grant_value$session_projection)
full_grant_value$model_base_grant$grant_identity <- unscoped(
  full_outputs[[1L]]$descriptor$grant_identity)
full_grant_value$sibling_base_grants[[1L]]$grant_identity <- unscoped(
  full_outputs[[2L]]$descriptor$grant_identity)
full_grant_value$sibling_base_grants[[2L]]$grant_identity <- unscoped(
  full_outputs[[3L]]$descriptor$grant_identity)
full_grant_value$grant_identity <- NULL
envelope_grant_case <- signed("dfa_complete_provisional_grant",
  "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
  "provisional grant excluding grant_identity", full_grant_value,
  "grant_identity")
full_decl_value <- declaration_value
full_decl_value$provisional_grant_identity <- unscoped(
  envelope_grant_case$identity)
full_decl_value$declaration_identity <- NULL
full_decl_case <- signed("dfa_complete_private_declaration",
  "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
  "declaration excluding declaration_identity", full_decl_value,
  "declaration_identity")
full_seal2_value <- seal_value
full_seal2_value$provisional_grant_identity <- unscoped(
  envelope_grant_case$identity)
full_seal2_value$declaration_identity <- unscoped(full_decl_case$identity)
full_seal2_value$session_identity <- unscoped(
  full_grant_value$session_projection$session_identity)
full_seal2_value$seal_identity <- NULL
full_seal2_case <- signed("dfa_complete_seal",
  "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
  "seal excluding seal_identity", full_seal2_value, "seal_identity")
full_sidecar <- sidecar
full_sidecar$session_identity <- full_seal2_value$session_identity
full_sidecar$seal_identity <- unscoped(full_seal2_case$identity)
full_evidence <- list(relative_path = ".scworkbench/selected-axis-v1.json",
  sha256 = hash(full_sidecar), evidence_identity = plain(
    "scworkbench.operation_pack.selected_axis_evidence.v1", full_sidecar))
full_model_grant <- model_grant_value
full_model_grant$base_grant_identity <-
  full_grant_value$model_base_grant$grant_identity
full_model_grant$fitted_axis_seal_identity <- unscoped(full_seal2_case$identity)
full_model_grant$selected_axis_evidence <- full_evidence
full_model_grant$sealed_grant_identity <- NULL
full_model_grant$sealed_grant_identity <- scoped(
  "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
  "sealed model grant excluding sealed_grant_identity", full_model_grant)
full_sibling_grants <- lapply(seq_along(
  full_grant_value$sibling_base_grants), function(index) {
    base_value <- full_grant_value$sibling_base_grants[[index]]
    value <- list(schema =
        "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
      name = base_value$name, kind = base_value$kind,
      coverage_policy = base_value$coverage_policy,
      base_grant_identity = base_value$grant_identity,
      fitted_axis_seal_identity = unscoped(full_seal2_case$identity),
      promotion_group = base_value$promotion_group)
    value$sealed_grant_identity <- scoped(
      "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
      "sealed sibling grant excluding sealed_grant_identity", value)
    value
  })
full_linkage <- linkage_value
full_linkage$session_identity <- full_seal2_value$session_identity
full_linkage$fitted_axis_seal_identity <- unscoped(full_seal2_case$identity)
full_linkage$selected_axis_evidence <- full_evidence
full_linkage$linkage_identity <- NULL
full_linkage$linkage_identity <- scoped(
  "scworkbench.operation_pack.model_source_linkage.v3",
  "linkage excluding linkage_identity", full_linkage)
full_tree_observation <- tree_observation_value
full_tree_observation$sealed_model_grant_identity <- unscoped(
  full_model_grant$sealed_grant_identity)
full_tree_observation$model_source_linkage_identity <- unscoped(
  full_linkage$linkage_identity)
full_tree_observation$observation_identity <- NULL
full_tree_observation$observation_identity <- scoped(
  "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1",
  "observation excluding observation_identity", full_tree_observation)
observed_output <- function(request_item, dimensions, content, payload,
    cell_order = NULL, model = FALSE) {
  descriptor <- list(category = request_item$descriptor$category,
    kind = request_item$descriptor$kind,
    storage_profile = request_item$descriptor$storage_profile,
    writer = request_item$descriptor$writer,
    grant_identity = request_item$descriptor$grant_identity,
    dimensions = as.list(dimensions),
    alignment = request_item$descriptor$expected_alignment,
    ancestry_identity = request_item$descriptor$expected_ancestry_identity,
    model_linkage = request_item$descriptor$expected_model_linkage,
    content_identity = content, payload_manifest_identity = payload,
    semantic_metadata_identity = token("c",
      "scworkbench.operation_pack.semantic_metadata.v2"),
    semantic_validation = list(constraints_identity = token("d",
      "scworkbench.operation_pack.semantic_constraints.v2"),
      status = "passed"))
  if (!is.null(cell_order)) descriptor$cell_order_identity <- cell_order
  if (model) {
    descriptor$model_linkage_identity <- unscoped(
      full_linkage$linkage_identity)
    descriptor$contained_payload <- list(contained = TRUE,
      no_symlinks = TRUE, payload_tree_identity = token("e",
        "scworkbench.operation_pack.contained_payload.v2"))
    descriptor$contained_model_sibling_tree <- full_tree_observation
  }
  descriptor$observed_descriptor_identity <- scoped(
    "scworkbench.operation_pack.observed_output.v3",
    "descriptor excluding observed_descriptor_identity", descriptor)
  list(name = request_item$name, allocated_id = request_item$allocated_id,
    descriptor = descriptor)
}
full_model_content <- plain("scworkbench.model_ref.content.v1", list(
  engine = "fixture", model_type = "derived_axis_model",
  linkage_identity = unscoped(full_linkage$linkage_identity),
  tree_manifest_identity = unscoped(tree_manifest_case$identity)))
full_observed <- list(
  observed_output(full_outputs[[1L]], 1L, full_model_content,
    payload_manifest_case$identity, model = TRUE),
  observed_output(full_outputs[[2L]], 2L,
    token("f", "scworkbench.cell_vector.content.v1"), token("1",
      "scworkbench.operation_pack.payload_manifest.v2"),
    full_seal2_value$fitted_cell_order_identity),
  observed_output(full_outputs[[3L]], c(3L, 3L),
    token("2", "scworkbench.cell_vector_family.content.v1"), token("3",
      "scworkbench.operation_pack.payload_manifest.v2"),
    plain("scworkbench.cell_order.v1",
      as.list(c("cell_2", "cell_3", "cell_2")))))
full_coverage <- list(exact_coverage_case$value, sparse_coverage_case$value)
for (index in seq_along(full_coverage)) {
  full_coverage[[index]]$sealed_sibling_grant_identity <- unscoped(
    full_sibling_grants[[index]]$sealed_grant_identity)
  full_coverage[[index]]$fitted_axis_seal_identity <- unscoped(
    full_seal2_case$identity)
  full_coverage[[index]]$output_observed_descriptor_identity <- unscoped(
    full_observed[[index + 1L]]$descriptor$observed_descriptor_identity)
  full_coverage[[index]]$output_content_identity <-
    full_observed[[index + 1L]]$descriptor$content_identity
  full_coverage[[index]]$observation_identity <- NULL
  full_coverage[[index]]$observation_identity <- scoped(
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
    "coverage observation excluding observation_identity",
    full_coverage[[index]])
}
full_observation <- observation_value
full_observation$provisional_grant_identity <- unscoped(
  envelope_grant_case$identity)
full_observation$declaration_identity <- unscoped(full_decl_case$identity)
full_observation$seal <- full_seal2_case$value
full_observation$sealed_model_grant <- full_model_grant
full_observation$sealed_sibling_grants <- full_sibling_grants
full_observation$selected_axis_evidence <- full_evidence
full_observation$model_source_linkage <- full_linkage
full_observation$model_observed_descriptor_identity <- unscoped(
  full_observed[[1L]]$descriptor$observed_descriptor_identity)
full_observation$sibling_coverage_observations <- full_coverage
full_observation$observation_identity <- NULL
full_observation$observation_identity <- scoped(
  "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
  "observation excluding observation_identity", full_observation)
capability <- list(capability_id = "capability_fixture",
  mode = "private_staging_write", transition_identity =
    transition$transition_identity, session_id = "session_fixture",
  run_id = "run_fixture", checkpoint_generation = "ephemeral",
  source_state_identity = transition$source_state_identity,
  staging_root_identity = token("5",
    "scworkbench.operation_pack.staging_root.v1"), lease_id = "lease_fixture",
  pack_identity = token("6", "scworkbench.operation_pack.pack.v3"),
  distribution_identity = token("7",
    "scworkbench.operation_pack.content.v1"), manifest_source_identity =
    token("8", "scworkbench.operation_pack.manifest_source.bytes.v1"),
  operation_definition_identity = token("9",
    "scworkbench.operation_pack.definition.v3"), entry_point_identity =
    token("0", "scworkbench.operation_pack.entry_point.v2"),
  selected_requirement_set_identity = token("a",
    "scworkbench.operation_pack.dependencies.v2"),
  preflight_report_identity = token("b",
    "scworkbench.operation_pack.preflight.v2"), reader_grants = list(list(
      input_name = "source", reader = "read_space", descriptor_identity =
        full_input_descriptor$descriptor_identity)), writer_grants = lapply(
      full_outputs, function(item) list(output_name = item$name,
        writer = item$descriptor$writer,
        grant_identity = item$descriptor$grant_identity)), single_use = TRUE,
  derived_fitted_axis_grant_identities = list(unscoped(
    envelope_grant_case$identity)))
capability$capability_identity <- scoped(
  "scworkbench.operation_pack.capability.v3",
  "capability excluding capability_identity", capability)
request_value <- list(schema =
    "scworkbench.operation_pack.transition_request.v3",
  message_type = "request", process_protocol_version = "pybench-op-v4",
  pack_abi_version = "3", canonical_json_scheme =
    "scworkbench.operation_pack.canonical_json.v1", transition = transition,
  operation_authentication = list(name = "fixture::derived_fit",
    pack_identity = capability$pack_identity,
    manifest_identity = token("c", "scworkbench.operation_pack.manifest.v3"),
    manifest_source_identity = capability$manifest_source_identity,
    distribution_identity = capability$distribution_identity,
    operation_definition_identity = capability$operation_definition_identity,
    entry_point = list(value = "fixture::register", identity =
      capability$entry_point_identity)), engine_contract = list(
    implementation = "scworkbench", implementation_version = "0.1.0",
    scientific_state_scheme = "scworkbench.scientific_state.v1",
    scientific_state_schema_identity = token("d",
      "scworkbench.scientific_state.schema.v1"), reader_api =
      "scworkbench.operation_pack.typed_readers.v2", writer_api =
      "scworkbench.operation_pack.staged_writers.v2"),
  dependency_resolution = list(declared_requirement_set_identity =
      capability$selected_requirement_set_identity,
    selected_requirement_set_identity =
      capability$selected_requirement_set_identity,
    dynamic_resolutions = list(), preflight_report_identity =
      capability$preflight_report_identity, network_policy = "deny"),
  inputs = list(list(name = "source", reference = "space:source",
    descriptor = full_input_descriptor)), params = list(dims = list(1L, 3L),
      fitted_cells = list("cell_2", "cell_3")), outputs = full_outputs,
  execution_capability = capability,
  derived_fitted_axis_grants = list(envelope_grant_case$value))
request_case <- signed("dfa_success_request",
  "scworkbench.operation_pack.transition_request.v3",
  "request excluding request_identity", request_value, "request_identity")
mutation <- list(entries_identity = plain(
    "scworkbench.operation_pack.mutation_entries.v2",
    lapply(full_observed, function(item) item$descriptor$
      payload_manifest_identity)), entry_count = 3L, unexpected_entries = 0L)
mutation$mutation_identity <- scoped(
  "scworkbench.operation_pack.mutation_manifest.v2",
  "mutation manifest excluding mutation_identity", mutation)
runtime <- list(schema = "scworkbench.operation_pack.runtime.v3",
  backend = "R", pack_identity = capability$pack_identity,
  manifest_source_identity = capability$manifest_source_identity,
  distribution_identity = capability$distribution_identity,
  operation_definition_identity = capability$operation_definition_identity,
  entry_point = request_value$operation_authentication$entry_point,
  declared_requirement_set_identity = request_value$dependency_resolution$
    declared_requirement_set_identity,
  selected_requirement_set_identity = capability$
    selected_requirement_set_identity, dynamic_resolutions = list(),
  preflight_report_identity = capability$preflight_report_identity,
  path_policy = "no_absolute_paths")
runtime$runtime_identity <- scoped(
  "scworkbench.operation_pack.runtime.v3",
  "runtime attestation excluding runtime_identity", runtime)
receipt_value <- list(schema =
    "scworkbench.operation_pack.transition_receipt.v3",
  message_type = "receipt", process_protocol_version = "pybench-op-v4",
  pack_abi_version = "3", canonical_json_scheme =
    "scworkbench.operation_pack.canonical_json.v1", status = "ok",
  transition_id = transition$transition_id, session_id = transition$session_id,
  run_id = transition$run_id, transition_identity =
    transition$transition_identity, request_identity = request_case$identity,
  capability_identity = capability$capability_identity,
  outputs = full_observed, registry_requests = list(),
  mutation_manifest = mutation, runtime_attestation = runtime,
  derived_fitted_axis_observations = list(full_observation))
receipt_case <- signed("dfa_success_receipt",
  "scworkbench.operation_pack.transition_receipt.v3",
  "receipt excluding receipt_identity", receipt_value, "receipt_identity")
model_descriptor_case <- list(name = "dfa_model_observed_descriptor",
  preimage = full_observed[[1L]]$descriptor[names(
    full_observed[[1L]]$descriptor) != "observed_descriptor_identity"],
  identity = full_observed[[1L]]$descriptor$observed_descriptor_identity,
  value = full_observed[[1L]]$descriptor)
observation_case <- list(name = "dfa_complete_observation",
  preimage = full_observation[names(full_observation) !=
    "observation_identity"], identity = full_observation$observation_identity,
  value = full_observation)
new_cases <- list(policy_case, parent_case, session_case, grant_case,
  declaration_case, seal_case, sidecar_case, model_grant_case,
  embedding_grant_case, weights_grant_case, linkage_case,
  exact_coverage_case, sparse_coverage_case, tree_observation_case,
  model_content_case, model_descriptor_case, observation_case,
  full_session_case, full_grant_case, full_declaration_case, full_seal_case,
  request_case, receipt_case)
existing_names <- vapply(fixture$cases, `[[`, character(1), "name")
new_names <- vapply(new_cases, `[[`, character(1), "name")
fixture$cases <- lapply(fixture$cases, function(item) {
  index <- match(item$name, new_names)
  if (is.na(index)) item else new_cases[[index]]
})
fixture$cases <- c(fixture$cases, new_cases[!new_names %in% existing_names])
clone <- function(x) unserialize(serialize(x, NULL))
negative <- function(name, schema_file, definition, value, expected,
    expected_code) list(name = name, schema_file = schema_file,
  definition = definition, value = value, expected = expected,
  expected_code = expected_code)
n1 <- clone(full_sidecar); n1$content_sha256 <- paste(rep("0", 64L),
  collapse = "")
n2 <- clone(full_evidence); n2$relative_path <- "/tmp/selected-axis.json"
n3 <- clone(envelope_grant_case$value); n3$seal_identity <- token("0")
n4 <- clone(full_linkage); n4$model_tree_manifest_identity <- token("1")
n5 <- clone(full_coverage[[1L]]); n5$coverage_policy <-
  "per_key_source_relative_subset_v1"
n6 <- clone(full_coverage[[2L]]); n6$observed_keys <- list();
n6$per_key_coverage <- list()
n7 <- clone(full_grant_value$session_projection)
n7$session_cell_ids <- list("cell_2", "cell_2")
n8 <- clone(full_seal2_case$value)
n8$fitted_cell_ids <- list("cell_2", "cell_2")
n9 <- clone(request_case$value)
n9$derived_fitted_axis_grants[[1L]]$model_base_grant$grant_identity <-
  token("7", "scworkbench.operation_pack.output_grant.v3")
n9$derived_fitted_axis_grants[[1L]]$grant_identity <- NULL
n9$derived_fitted_axis_grants[[1L]]$grant_identity <- scoped(
  "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
  "provisional grant excluding grant_identity",
  n9$derived_fitted_axis_grants[[1L]])
n9$execution_capability$derived_fitted_axis_grant_identities <- list(
  unscoped(n9$derived_fitted_axis_grants[[1L]]$grant_identity))
n9$execution_capability$capability_identity <- NULL
n9$execution_capability$capability_identity <- scoped(
  "scworkbench.operation_pack.capability.v3",
  "capability excluding capability_identity", n9$execution_capability)
n9$request_identity <- NULL
n9$request_identity <- scoped(
  "scworkbench.operation_pack.transition_request.v3",
  "request excluding request_identity", n9)
n10 <- clone(receipt_case$value)
n10$derived_fitted_axis_observations[[1L]]$seal$fitted_cell_ids <-
  list("cell_2")
n10$derived_fitted_axis_observations[[1L]]$seal$fitted_cell_count <- 1L
n10$derived_fitted_axis_observations[[1L]]$seal$seal_identity <- NULL
n10$derived_fitted_axis_observations[[1L]]$seal$seal_identity <- scoped(
  "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
  "seal excluding seal_identity",
  n10$derived_fitted_axis_observations[[1L]]$seal)
n10$derived_fitted_axis_observations[[1L]]$observation_identity <- NULL
n10$derived_fitted_axis_observations[[1L]]$observation_identity <- scoped(
  "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
  "observation excluding observation_identity",
  n10$derived_fitted_axis_observations[[1L]])
n10$receipt_identity <- NULL
n10$receipt_identity <- scoped(
  "scworkbench.operation_pack.transition_receipt.v3",
  "receipt excluding receipt_identity", n10)
n11 <- clone(receipt_case$value)
n11$derived_fitted_axis_observations[[1L]]$
  sibling_coverage_observations[[1L]]$output_content_identity <- token("8",
    "scworkbench.cell_vector.content.v1")
n11$derived_fitted_axis_observations[[1L]]$
  sibling_coverage_observations[[1L]]$observation_identity <- NULL
n11$derived_fitted_axis_observations[[1L]]$
  sibling_coverage_observations[[1L]]$observation_identity <- scoped(
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
    "coverage observation excluding observation_identity",
    n11$derived_fitted_axis_observations[[1L]]$
      sibling_coverage_observations[[1L]])
n11$derived_fitted_axis_observations[[1L]]$observation_identity <- NULL
n11$derived_fitted_axis_observations[[1L]]$observation_identity <- scoped(
  "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
  "observation excluding observation_identity",
  n11$derived_fitted_axis_observations[[1L]])
n11$receipt_identity <- NULL
n11$receipt_identity <- scoped(
  "scworkbench.operation_pack.transition_receipt.v3",
  "receipt excluding receipt_identity", n11)
n12 <- clone(full_linkage)
n12$linkage_identity$scheme <- "unknown.identity.scheme"
n13 <- clone(full_sibling_grants[[1L]])
n13$coverage_policy <- "per_key_source_relative_subset_v1"
n14 <- clone(full_model_grant)
n14$limits$maximum_total_bytes <- 1.5
retained_negative_cases <- Filter(function(item)
  !startsWith(as.character(item$name)[1], "dfa_"),
  fixture$negative_cases)
fixture$negative_cases <- c(list(
  negative("dfa_sidecar_self_hash_forbidden", request_name,
    "selected_axis_evidence_sidecar", n1, "schema_reject",
    "PYBENCH_CAPABILITY_MISMATCH"),
  negative("dfa_sidecar_absolute_path_forbidden", receipt_name,
    "selected_axis_evidence_descriptor", n2, "schema_reject",
    "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_provisional_downstream_seal_forbidden", request_name,
    "derived_fitted_axis_grant", n3, "schema_reject",
    "PYBENCH_CAPABILITY_MISMATCH"),
  negative("dfa_linkage_tree_cycle_forbidden", receipt_name,
    "model_source_linkage_v3", n4, "schema_reject",
    "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_vector_sparse_coverage_forbidden", receipt_name,
    "observed_sealed_sibling_coverage", n5, "schema_reject",
    "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_family_empty_keys_forbidden", receipt_name,
    "observed_sealed_sibling_coverage", n6, "schema_reject",
    "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_duplicate_session_ids_forbidden", request_name,
    "derived_fitted_session", n7, "schema_reject",
    "PYBENCH_CAPABILITY_MISMATCH"),
  negative("dfa_duplicate_fitted_ids_forbidden", receipt_name,
    "derived_fitted_axis_seal", n8, "schema_reject",
    "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_request_cross_grant_substitution", request_name, "root",
    n9, "semantic_reject", "PYBENCH_CAPABILITY_MISMATCH"),
  negative("dfa_receipt_cross_seal_substitution", receipt_name, "root",
    n10, "semantic_reject", "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_receipt_payload_identity_substitution", receipt_name,
    "root", n11, "semantic_reject", "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_unknown_linkage_scheme", receipt_name,
    "model_source_linkage_v3", n12, "schema_reject",
    "PYBENCH_RECEIPT_MISMATCH"),
  negative("dfa_vector_sparse_sealed_grant_forbidden", request_name,
    "sealed_sibling_output_grant", n13, "schema_reject",
    "PYBENCH_CAPABILITY_MISMATCH"),
  negative("dfa_fractional_tree_byte_limit_forbidden", request_name,
    "sealed_model_sibling_grant", n14, "schema_reject",
    "PYBENCH_CAPABILITY_MISMATCH")), retained_negative_cases)
write(fixture, fixture_name)
