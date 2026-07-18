# Commit-private payload workspace for observable-atomic promotion.

.wb_promotion_workspace_new <- function(bundle, commit_id) {
  pending_root <- file.path(bundle$dir, "provenance", ".pending", as.character(commit_id))
  .wb_assert(!dir.exists(pending_root), paste0("Promotion workspace already exists: ", pending_root))
  dir.create(pending_root, recursive = TRUE, showWarnings = FALSE)
  structure(list(bundle = bundle, commit_id = as.character(commit_id), pending_root = pending_root,
                 mappings = list(), published = character(0)), class = "wb_promotion_workspace")
}

.wb_promotion_workspace_path <- function(workspace, final_rel) {
  .wb_assert(inherits(workspace, "wb_promotion_workspace"), "workspace must be wb_promotion_workspace")
  final_rel <- as.character(final_rel)[1]
  .wb_assert(nzchar(final_rel) && !startsWith(final_rel, "/") && !grepl("(^|/)\\.\\.(/|$)", final_rel), "final_rel must be bundle-relative")
  final_abs <- file.path(workspace$bundle$dir, final_rel)
  .wb_assert(!file.exists(final_abs) && !dir.exists(final_abs), paste0("Promotion final path already exists: ", final_rel))
  pending_abs <- file.path(workspace$pending_root, final_rel)
  dir.create(dirname(pending_abs), recursive = TRUE, showWarnings = FALSE)
  workspace$mappings[[final_rel]] <- list(pending = pending_abs, final = final_abs)
  list(workspace = workspace, pending_path = pending_abs)
}

.wb_promotion_workspace_publish <- function(workspace) {
  for (m in workspace$mappings) {
    .wb_assert(file.exists(m$pending) || dir.exists(m$pending), paste0("Missing pending payload: ", m$pending))
    dir.create(dirname(m$final), recursive = TRUE, showWarnings = FALSE)
    .wb_assert(!file.exists(m$final) && !dir.exists(m$final), paste0("Promotion final path already exists: ", m$final))
    ok <- file.rename(m$pending, m$final)
    .wb_assert(isTRUE(ok), paste0("Failed to publish promotion payload: ", m$final))
    workspace$published <- c(workspace$published, m$final)
  }
  workspace
}

.wb_promotion_workspace_cleanup <- function(workspace) {
  if (dir.exists(workspace$pending_root)) unlink(workspace$pending_root, recursive = TRUE, force = TRUE)
  for (path in workspace$published) if (file.exists(path) || dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}
