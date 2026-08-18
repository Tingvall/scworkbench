library(scworkbench)
library(jsonlite)
library(ggplot2)
library(patchwork)
library(ggrastr)

bundle_path <- "/work/bundles/GSE270605_honeybee_raw_counts.bundle"
out_dir <- "/work/output"
b <- wb_open_bundle(bundle_path, read_only = TRUE, validate = FALSE)
on.exit(wb_close_bundle(b), add = TRUE)

ctx <- fromJSON(file.path(out_dir, "run_context.json"), simplifyVector = FALSE)
promoted <- utils::read.csv(file.path(out_dir, "promoted_artifacts.csv"), stringsAsFactors = FALSE)
output_col <- if ("output_name" %in% names(promoted)) "output_name" else "output"

find_artifact <- function(run_id, output_name) {
  hit <- promoted[promoted$run_id == run_id & promoted[[output_col]] == output_name & promoted$status == "ok", , drop = FALSE]
  stopifnot(nrow(hit) == 1L)
  hit$artifact_id[[1L]]
}

vector_runs <- unlist(ctx$vector_runs, use.names = TRUE)
association_runs <- unlist(ctx$association_runs, use.names = TRUE)
vector_artifacts <- vapply(vector_runs, find_artifact, character(1), output_name = "vector")

vectors <- lapply(vector_artifacts, function(id) wb_art_load(b, id, expected_kind = "cell_vector"))
vector_tables <- lapply(vectors, wb_primitive_to_table)

spaces <- c(
  conventional_RNA = "rna.umap.all.vst2000.pcs30",
  unbatched_scVI = "rna.umap.scvi.all.unbatched.latent30",
  sample_id_aware_scVI = "rna.umap.scvi.all.sample_id.latent30"
)
space_titles <- c(
  conventional_RNA = "Conventional RNA\nPCA (30 PCs) → UMAP",
  unbatched_scVI = "Unbatched scVI\nlatent (30D) → UMAP",
  sample_id_aware_scVI = "sample_id-aware scVI\nlatent (30D) → UMAP"
)

space_coverage <- lapply(names(spaces), function(key) {
  sid <- spaces[[key]]
  info <- wb_space_info(b, sid)
  ids <- wb_cells_with_space(b, sid)
  data.frame(
    representation = key,
    space_id = sid,
    n_cells = length(ids),
    n_dims = 2L,
    same_as_all_cells = identical(sort(as.character(ids)), sort(as.character(wb_cells(b, "all")))),
    stringsAsFactors = FALSE
  )
})
space_coverage <- do.call(rbind, space_coverage)
utils::write.csv(space_coverage, file.path(out_dir, "representation_coverage.csv"), row.names = FALSE)

palettes <- list(
  sample_id = c(
    GSM8348194 = "#332288", GSM8348195 = "#88CCEE", GSM8348196 = "#44AA99",
    GSM8348198 = "#117733", GSM8348200 = "#999933", GSM8348202 = "#DDCC77",
    GSM8348203 = "#CC6677", GSM8348204 = "#882255", GSM8348205 = "#AA4499",
    `__MISSING__` = "#BDBDBD"
  ),
  developmental_stage = c(Adult = "#0072B2", Pupa = "#D55E00", `__MISSING__` = "#BDBDBD"),
  biological_replicate = c(`1` = "#009E73", `2` = "#E69F00", `3` = "#CC79A7", `__MISSING__` = "#BDBDBD"),
  biological_group = c(Forager = "#E69F00", Nurse = "#0072B2", Pupa = "#D55E00", `__MISSING__` = "#BDBDBD")
)
field_titles <- c(
  sample_id = "Sample",
  developmental_stage = "Developmental stage",
  biological_replicate = "Biological replicate",
  biological_group = "Recorded biological group"
)

category_counts <- list()
overlay_specs <- list()
field_figures <- list()

for (field in names(vectors)) {
  count_ds <- wb_wrangle_plot_dataset(
    plot_type = "category_count_bar",
    inputs = list(vector = vectors[[field]]),
    bundle = b
  )
  stopifnot(isTRUE(wb_plot_validate_dataset("category_count_bar", count_ds)))
  cc <- count_ds$table
  cc$metadata_field <- field
  cc$vector_artifact_id <- vector_artifacts[[field]]
  category_counts[[field]] <- cc

  plots <- list()
  overlay_specs[[field]] <- list()
  for (rep_name in names(spaces)) {
    sid <- spaces[[rep_name]]
    ds <- wb_wrangle_plot_dataset(
      plot_type = "embedding_overlay",
      inputs = list(space = wb_prim_space_2d(sid), color = vectors[[field]]),
      bundle = b
    )
    stopifnot(
      isTRUE(wb_plot_validate_dataset("embedding_overlay", ds)),
      nrow(ds$table) == 120895L,
      setequal(as.character(ds$table$cell_id), as.character(vector_tables[[field]]$cell_id))
    )
    overlay_specs[[field]][[rep_name]] <- list(
      plot_contract = wb_plot_spec("embedding_overlay", ds),
      representation = rep_name,
      space_id = sid,
      vector_artifact_id = vector_artifacts[[field]],
      cell_count = nrow(ds$table),
      palette = as.list(palettes[[field]])
    )

    dd <- ds$table
    dd$color_value <- factor(as.character(dd$color_value), levels = names(palettes[[field]]))
    p <- ggplot(dd, aes(x = x, y = y, colour = color_value)) +
      ggrastr::geom_point_rast(size = 0.16, alpha = 0.48, stroke = 0, raster.dpi = 300) +
      scale_colour_manual(
        values = palettes[[field]],
        breaks = names(palettes[[field]]),
        limits = names(palettes[[field]]),
        labels = ifelse(names(palettes[[field]]) == "__MISSING__", "Missing (0)", names(palettes[[field]])),
        drop = FALSE,
        na.value = palettes[[field]][["__MISSING__"]],
        name = field_titles[[field]]
      ) +
      coord_equal() +
      labs(title = unname(space_titles[[rep_name]]), x = NULL, y = NULL) +
      theme_void(base_size = 10) +
      theme(
        plot.title = element_text(face = "bold", size = 10.5, hjust = 0.5, margin = margin(b = 4)),
        legend.title = element_text(face = "bold"),
        legend.text = element_text(size = 8),
        legend.key.height = grid::unit(3.2, "mm"),
        plot.margin = margin(4, 4, 4, 4)
      ) +
      guides(colour = guide_legend(override.aes = list(size = 2.4, alpha = 1)))
    plots[[rep_name]] <- p
  }

  assembled <- wrap_plots(plots, nrow = 1, guides = "collect") +
    plot_annotation(
      title = paste0("Honeybee brain cells coloured by ", tolower(field_titles[[field]])),
      subtitle = "Identical 120,895-cell universe; coordinates are representation-specific and axes are not directly comparable",
      theme = theme(
        plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(size = 9.5, colour = "grey30")
      )
    ) & theme(legend.position = "right")
  field_figures[[field]] <- assembled

  png_path <- file.path(out_dir, paste0("figure_", field, "_three_representations.png"))
  pdf_path <- file.path(out_dir, paste0("figure_", field, "_three_representations.pdf"))
  ggsave(png_path, assembled, device = ragg::agg_png, width = 14.5, height = 5.4, units = "in", dpi = 300, bg = "white")
  ggsave(pdf_path, assembled, device = cairo_pdf, width = 14.5, height = 5.4, units = "in", bg = "white")
}

category_counts <- do.call(rbind, category_counts)
rownames(category_counts) <- NULL
utils::write.csv(category_counts, file.path(out_dir, "metadata_category_counts.csv"), row.names = FALSE)
missingness <- do.call(rbind, lapply(names(vectors), function(field) {
  hit <- category_counts[category_counts$metadata_field == field & category_counts$category == "__MISSING__", , drop = FALSE]
  data.frame(
    metadata_field = field,
    missing_label = "__MISSING__",
    missing_count = if (nrow(hit)) hit$count[[1L]] else 0L,
    missing_fraction = if (nrow(hit)) hit$pct[[1L]] else 0,
    policy = "as_category",
    vector_artifact_id = vector_artifacts[[field]],
    stringsAsFactors = FALSE
  )
}))
utils::write.csv(missingness, file.path(out_dir, "metadata_missingness.csv"), row.names = FALSE)

association_summary <- list()
association_detail <- list()
pair_labels <- list(
  sample_by_stage = c("sample_id", "developmental_stage"),
  sample_by_replicate = c("sample_id", "biological_replicate"),
  sample_by_group = c("sample_id", "biological_group"),
  stage_by_replicate = c("developmental_stage", "biological_replicate"),
  stage_by_group = c("developmental_stage", "biological_group"),
  replicate_by_group = c("biological_replicate", "biological_group")
)
for (key in names(association_runs)) {
  run_id <- association_runs[[key]]
  sum_id <- find_artifact(run_id, "summary")
  det_id <- find_artifact(run_id, "detail")
  sm <- wb_primitive_to_table(wb_art_load(b, sum_id, expected_kind = "obs_table"))
  dt <- wb_primitive_to_table(wb_art_load(b, det_id, expected_kind = "obs_table"))
  sm$comparison <- key
  sm$field_a <- pair_labels[[key]][[1L]]
  sm$field_b <- pair_labels[[key]][[2L]]
  sm$run_id <- run_id
  sm$summary_artifact_id <- sum_id
  sm$detail_artifact_id <- det_id
  dt$comparison <- key
  dt$run_id <- run_id
  dt$detail_artifact_id <- det_id
  association_summary[[key]] <- sm
  association_detail[[key]] <- dt
}
association_summary <- do.call(rbind, association_summary)
association_detail <- do.call(rbind, association_detail)
rownames(association_summary) <- NULL
rownames(association_detail) <- NULL
utils::write.csv(association_summary, file.path(out_dir, "metadata_association_metrics.csv"), row.names = FALSE)
utils::write.csv(association_detail, file.path(out_dir, "metadata_association_details.csv"), row.names = FALSE)

dag <- wb_prov_bundle_dag(b)
flatten_lists <- function(df) {
  for (nm in names(df)) if (is.list(df[[nm]])) {
    df[[nm]] <- vapply(df[[nm]], function(x) toJSON(x, auto_unbox = TRUE, null = "null"), character(1))
  }
  df
}
utils::write.csv(flatten_lists(dag$nodes), file.path(out_dir, "dag_nodes.csv"), row.names = FALSE)
utils::write.csv(flatten_lists(dag$edges), file.path(out_dir, "dag_edges.csv"), row.names = FALSE)
write_json(dag, file.path(out_dir, "dag.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

space_certificates <- lapply(spaces, function(sid) wb_entity_certificate(b, "space", sid))
vector_certificates <- lapply(vector_artifacts, function(id) wb_entity_certificate(b, "artifact", id))
association_certificates <- lapply(association_runs, function(run_id) wb_entity_certificate(b, "run", run_id))

evidence <- list(
  schema = "honeybee.rc30.representation_comparison.evidence.v1",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  scope = list(
    claim_type = "descriptive_embedding_geometry",
    excluded_claims = c("batch_correction_quality", "biological_superiority", "causality"),
    cell_set = "all",
    n_cells = 120895L,
    missing_policy = "as_category",
    missing_label = "__MISSING__"
  ),
  representations = as.list(spaces),
  representation_coverage = space_coverage,
  vector_artifacts = as.list(vector_artifacts),
  association_runs = as.list(association_runs),
  category_counts = category_counts,
  missingness = missingness,
  association_metrics = association_summary,
  overlay_specs = overlay_specs,
  palettes = palettes,
  space_certificates = space_certificates,
  vector_certificates = vector_certificates,
  association_run_certificates = association_certificates,
  capability_boundary = paste(
    "RC30 provides provenance-backed metadata vectors, categorical association diagnostics,",
    "and embedding overlay wranglers, but no registered representation-specific metadata",
    "mixing/separation metric. Geometry conclusions are therefore visual and descriptive."
  )
)
write_json(evidence, file.path(out_dir, "evidence.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("EVIDENCE_AND_FIGURES_OK\n")
print(space_coverage)
print(category_counts)
print(association_summary)
