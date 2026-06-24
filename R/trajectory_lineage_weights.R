.wb_trajectory_ref_artifact_id <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.character(x) && length(x) == 1L && nzchar(x)) {
    return(sub("^artifact:", "", as.character(x)[1]))
  }
  if (is.list(x) && identical(as.character(x$ref_type %||% "")[1], "artifact")) {
    aid <- as.character(x$artifact_id %||% "")[1]
    if (nzchar(aid)) return(aid)
  }
  NULL
}

.wb_trajectory_lineage_weights_meta <- function(promoted = TRUE) {
  list(
    family_kind = "trajectory_membership_weight",
    engine = "slingshot",
    value_semantics = "lineage_membership_weight",
    range = c(0, 1),
    promoted = isTRUE(promoted)
  )
}

.wb_trajectory_attach_weight_meta <- function(prim, promoted = TRUE, artifact_id = NULL) {
  .wb_assert_kind(prim, "cell_vector_family")
  prim$meta <- modifyList(.wb_trajectory_lineage_weights_meta(promoted = promoted), prim$meta %||% list())
  if (!is.null(artifact_id)) prim$meta$artifact_id <- as.character(artifact_id)[1]
  prim
}

.wb_trajectory_sibling_lineage_weights_artifact <- function(bundle, artifact_id) {
  aid <- as.character(artifact_id %||% "")[1]
  if (!nzchar(aid) || !.wb_table_exists(bundle$con, "prov_run_outputs")) return(NULL)

  rows <- DBI::dbGetQuery(
    bundle$con,
    "SELECT snapshot_id, run_id
     FROM prov_run_outputs
     WHERE artifact_id = ?
     ORDER BY snapshot_id DESC, run_id DESC
     LIMIT 1;",
    params = list(aid)
  )
  if (!nrow(rows)) return(NULL)

  sib <- DBI::dbGetQuery(
    bundle$con,
    "SELECT artifact_id
     FROM prov_run_outputs
     WHERE snapshot_id = ?
       AND run_id = ?
       AND output_name = 'lineage_weights'
       AND artifact_id IS NOT NULL
       AND artifact_id <> ''
     LIMIT 1;",
    params = list(as.character(rows$snapshot_id[1]), as.character(rows$run_id[1]))
  )
  if (!nrow(sib)) return(NULL)
  out <- as.character(sib$artifact_id[1])
  if (nzchar(out)) out else NULL
}

.wb_trajectory_lineage_weights_from_model <- function(model_ref) {
  .wb_assert_kind(model_ref, "model_ref")
  .wb_assert(identical(as.character(model_ref$engine %||% "")[1], "slingshot"),
             "lineage weight fallback currently supports only model_ref(engine='slingshot').")
  sds <- model_ref$model_obj %||% NULL
  .wb_assert(!is.null(sds),
             "lineage weight fallback requires an in-memory Slingshot model payload.")
  prim <- .wb_slingshot_lineage_weights_prim(sds)
  .wb_trajectory_attach_weight_meta(prim, promoted = FALSE)
}

#' Load Slingshot Lineage Membership Weights
#'
#' Resolve trajectory lineage membership weights as a `cell_vector_family`.
#' Prefer promoted `lineage_weights` artifacts; optional in-memory extraction
#' from a Slingshot model_ref is a fallback for session-only workflows.
#'
#' @param bundle Open scworkbench bundle.
#' @param model_ref Optional model_ref primitive, model artifact id, or
#'   `wb_ref_artifact()` pointing to a promoted model.
#' @param pseudotime_artifact Optional promoted pseudotime artifact id or
#'   artifact ref. Used to resolve a sibling `lineage_weights` artifact from
#'   the same provenance run/snapshot.
#' @param lineage_weights_artifact Optional promoted lineage_weights artifact
#'   id or artifact ref.
#'
#' @return A `cell_vector_family` primitive whose keys are lineage ids such as
#'   `L1`, `L2`, and whose numeric values are Slingshot membership weights.
#' @export
wb_trajectory_lineage_weights <- function(bundle,
                                          model_ref = NULL,
                                          pseudotime_artifact = NULL,
                                          lineage_weights_artifact = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  weight_aid <- .wb_trajectory_ref_artifact_id(lineage_weights_artifact)
  if (!is.null(weight_aid)) {
    prim <- wb_art_load(bundle, artifact_id = weight_aid, expected_kind = "cell_vector_family")
    return(.wb_trajectory_attach_weight_meta(prim, promoted = TRUE, artifact_id = weight_aid))
  }

  for (src in list(pseudotime_artifact, model_ref)) {
    src_aid <- .wb_trajectory_ref_artifact_id(src)
    if (is.null(src_aid)) next
    sib <- .wb_trajectory_sibling_lineage_weights_artifact(bundle, src_aid)
    if (!is.null(sib)) {
      prim <- wb_art_load(bundle, artifact_id = sib, expected_kind = "cell_vector_family")
      return(.wb_trajectory_attach_weight_meta(prim, promoted = TRUE, artifact_id = sib))
    }
  }

  if (.wb_is_primitive(model_ref)) {
    warning(
      "wb_trajectory_lineage_weights(): no promoted lineage_weights artifact resolved; extracting from in-memory Slingshot model_ref.",
      call. = FALSE
    )
    return(.wb_trajectory_lineage_weights_from_model(model_ref))
  }

  stop(
    "wb_trajectory_lineage_weights(): could not resolve lineage_weights. ",
    "Supply lineage_weights_artifact, or a pseudotime/model artifact promoted from a slingshot_fit run, ",
    "or an in-memory Slingshot model_ref.",
    call. = FALSE
  )
}
