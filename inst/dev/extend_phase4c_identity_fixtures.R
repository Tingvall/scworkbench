#!/usr/bin/env Rscript

development_library <- Sys.getenv("PHASE4C_R_LIBRARY", unset = "")
if (nzchar(development_library))
  .libPaths(c(development_library, .libPaths()))

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
path <- file.path(root, "inst", "protocol", "fixtures",
  "operation-pack-v3", "identities.json")
fixture <- jsonlite::read_json(path, simplifyVector = FALSE)
plain <- function(scheme, value) getFromNamespace(
  ".wb_operation_pack_v2_identity_plain", "scworkbench")(scheme, value)
scoped <- function(scheme, scope, value) getFromNamespace(
  ".wb_operation_pack_v2_identity_scoped", "scworkbench")(scheme, scope,
    value)
case <- function(name, preimage, field, identity) {
  value <- preimage; value[[field]] <- identity
  list(name = name, preimage = preimage, identity = identity, value = value)
}
id <- function(value) list(scheme = value$scheme, sha256 = value$sha256)
cells <- c("c2", "c1", "c3"); features <- c("g2", "g1", "g3",
  "g4", "g5")
cell_order <- plain("scworkbench.cell_order.v1", as.list(cells))
feature_order <- plain("scworkbench.feature_order.v1", as.list(features))
axis <- list(schema = "scworkbench.operation_pack.parameter_axis_grant.v1",
  name = "principal_components", parameter = "n_components", value = 3L,
  minimum = 2L, maximum = 3L, labels = as.list(paste0("PC", 1:3)),
  source = list(typed_slice_grant_identity = list(scheme =
    "scworkbench.operation_pack.typed_slice_grant.v1", sha256 =
    paste(rep("1", 64L), collapse = "")), cell_axis_count = 3L,
    feature_axis_count = 5L), axis_order_identity = plain(
      "scworkbench.dimension_order.v1", as.list(paste0("PC", 1:3))))
axis_identity <- scoped("scworkbench.operation_pack.parameter_axis_grant.v1",
  "grant excluding grant_identity", axis)
source_parts <- list(
  list(ordinal = 1L, source_fragment_identity = list(scheme =
    "scworkbench.operation_pack.source_matrix_fragment.v1", sha256 =
    paste(rep("2", 64L), collapse = "")), cell_start = 1L,
    cell_count = 2L, cell_order_identity = plain(
      "scworkbench.cell_order.v1", as.list(cells[1:2]))),
  list(ordinal = 2L, source_fragment_identity = list(scheme =
    "scworkbench.operation_pack.source_matrix_fragment.v1", sha256 =
    paste(rep("3", 64L), collapse = "")), cell_start = 3L,
    cell_count = 1L, cell_order_identity = plain(
      "scworkbench.cell_order.v1", as.list(cells[3]))))
schedule <- list(schema =
    "scworkbench.operation_pack.source_fragment_schedule.v1",
  input_descriptor_identity = list(scheme =
    "scworkbench.operation_pack.input_descriptor.v2", sha256 =
    paste(rep("4", 64L), collapse = "")), matrix_content_identity = list(
      scheme = "scworkbench.matrix.content.v1", sha256 =
      paste(rep("5", 64L), collapse = "")),
  source_fragment_manifest_identity = plain(
    "scworkbench.operation_pack.source_fragment_manifest.v1", source_parts),
  fragments = source_parts)
schedule_identity <- scoped(
  "scworkbench.operation_pack.source_fragment_schedule.v1",
  "schedule excluding schedule_identity", schedule)
fragment <- function(ordinal, start, count, source) list(
  ordinal = ordinal, source_fragment_ordinal = ordinal,
  source_fragment_identity = source_parts[[source]]$source_fragment_identity,
  part_ordinal = 1L, cell_start = start, cell_count = count,
  dimensions = list(5L, count), feature_order_identity = feature_order,
  cell_order_identity = plain("scworkbench.cell_order.v1",
    as.list(cells[seq.int(start, start + count - 1L)])),
  content_identity = list(scheme =
    "scworkbench.operation_pack.matrix_slice.content.v1", sha256 =
    paste(rep(as.character(5L + ordinal), 64L), collapse = "")),
  payload_manifest_identity = list(scheme =
    "scworkbench.operation_pack.payload_manifest.v2", scope =
    "matrix fragment payload tree", sha256 =
    paste(rep(as.character(7L + ordinal), 64L), collapse = "")))
parts <- list(fragment(1L, 1L, 2L, 1L), fragment(2L, 3L, 1L, 2L))
manifest <- list(schema =
    "scworkbench.operation_pack.matrix_fragment_manifest.v1",
  source_fragment_schedule_identity = schedule_identity,
  dimensions = list(5L, 3L), feature_order_identity = feature_order,
  cell_order_identity = cell_order, fragment_count = 2L,
  fragments = parts)
manifest_identity <- scoped(
  "scworkbench.operation_pack.matrix_fragment_manifest.v1",
  "manifest excluding fragment_manifest_identity", manifest)
preimage <- list(state = "absent", registry_absence_identity = list(
    scheme = "scworkbench.operation_pack.registry_absence.v1", sha256 =
    paste(rep("a", 64L), collapse = "")),
  transition_source_state_identity = list(scheme =
    "scworkbench.scientific_state.v1", sha256 =
    paste(rep("b", 64L), collapse = "")))
publication <- list(schema =
    "scworkbench.operation_pack.materialization_publication_grant.v1",
  output = "matrix", promotion_group = "normalization",
  closure_outputs = list("matrix", "summary"), target_kind = "matrix",
  target_id = "RNA_log", mode = "add",
  conflict_policy = "require_absent_v1", preimage = preimage)
publication_identity <- scoped(
  "scworkbench.operation_pack.materialization_publication_grant.v1",
  "grant excluding publication_grant_identity", publication)
phase4c <- list(
  case("parameter_axis_three_of_five", axis, "grant_identity", axis_identity),
  case("source_fragment_schedule_two", schedule, "schedule_identity",
    schedule_identity),
  case("matrix_fragment_manifest_two", manifest,
    "fragment_manifest_identity", manifest_identity),
  case("materialization_publication_add", publication,
    "publication_grant_identity", publication_identity))
fixture$cases <- c(Filter(function(x) !as.character(x$name) %in%
  vapply(phase4c, `[[`, character(1), "name"), fixture$cases), phase4c)
jsonlite::write_json(fixture, path, auto_unbox = TRUE, null = "null",
  digits = NA)
