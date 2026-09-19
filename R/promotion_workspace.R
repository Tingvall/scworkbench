# Commit-private payload workspace for observable-atomic promotion.

.wb_promotion_workspace_new <- function(bundle, commit_id) {
  pending_root <- file.path(bundle$dir, "provenance", ".pending", as.character(commit_id))
  .wb_assert(!dir.exists(pending_root), paste0("Promotion workspace already exists: ", pending_root))
  dir.create(pending_root, recursive = TRUE, showWarnings = FALSE)
  workspace <- new.env(parent = emptyenv())
  workspace$bundle <- bundle
  workspace$commit_id <- as.character(commit_id)
  workspace$pending_root <- pending_root
  workspace$mappings <- list()
  workspace$published <- character(0)
  workspace$retire_after_commit <- character(0)
  class(workspace) <- "wb_promotion_workspace"
  workspace
}

.wb_promotion_workspace_retire_after_commit <- function(workspace, path) {
  .wb_assert(inherits(workspace, "wb_promotion_workspace"), "workspace must be wb_promotion_workspace")
  status <- .wb_path_status(workspace$bundle$dir, path, expected_type = "either",
                            must_exist = FALSE, purpose = "superseded promotion payload")
  .wb_assert(isTRUE(status$ok), paste0(status$code, ": unsafe retirement payload path"))
  workspace$retire_after_commit <- unique(c(workspace$retire_after_commit, status$absolute))
  invisible(workspace)
}

.wb_promotion_workspace_retire <- function(workspace) {
  for (path in workspace$retire_after_commit) {
    if (file.exists(path) || dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

.wb_promotion_workspace_path <- function(workspace, final_rel) {
  .wb_assert(inherits(workspace, "wb_promotion_workspace"), "workspace must be wb_promotion_workspace")
  final_rel <- as.character(final_rel)[1]
  status <- .wb_path_status(workspace$bundle$dir,final_rel,expected_type="either",must_exist=FALSE,
                            purpose="promotion final payload")
  .wb_assert(isTRUE(status$ok),paste0(status$code,": final_rel must be bundle-relative and contained"))
  final_rel <- status$relative
  final_abs <- status$absolute
  .wb_assert(!file.exists(final_abs) && !dir.exists(final_abs), paste0("Promotion final path already exists: ", final_rel))
  pending_abs <- file.path(workspace$pending_root, final_rel)
  dir.create(dirname(pending_abs), recursive = TRUE, showWarnings = FALSE)
  workspace$mappings[[final_rel]] <- list(pending = pending_abs, final = final_abs)
  pending_abs
}

.wb_promotion_workspace_publish <- function(workspace) {
  final_paths <- names(workspace$mappings)
  for (i in seq_along(final_paths)) {
    final_rel <- final_paths[i]
    m <- workspace$mappings[[final_rel]]
    .wb_assert(file.exists(m$pending) || dir.exists(m$pending), paste0("Missing pending payload: ", m$pending))
    dir.create(dirname(m$final), recursive = TRUE, showWarnings = FALSE)
    .wb_assert(!file.exists(m$final) && !dir.exists(m$final), paste0("Promotion final path already exists: ", m$final))
    if (isTRUE(workspace$target_reproduction_atomicity)) {
      .wb_target_reproduction_atomicity_hook(
        "during_payload_publication", workspace = workspace,
        final_rel = final_rel, publication_index = i
      )
    }
    hook <- getOption("scworkbench.promotion_workspace_publish_hook", NULL)
    if (is.function(hook)) hook(workspace, final_rel)
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

.wb_promotion_workspace_final_rel_for_source <- function(workspace, source_path) {
  raw <- gsub("\\\\", "/", as.character(source_path %||% "")[1])
  if (!nzchar(raw)) return(NULL)
  source_path <- normalizePath(raw, winslash = "/", mustWork = FALSE)
  for (final_rel in names(workspace$mappings)) {
    mapped <- as.character(workspace$mappings[[final_rel]]$source %||% "")[1]
    if (!.wb_path_is_absolute(raw) && nzchar(mapped) &&
        endsWith(gsub("\\\\", "/", mapped), paste0("/", raw)))
      return(final_rel)
    if (nzchar(mapped) && identical(mapped, source_path)) return(final_rel)
    if (nzchar(mapped) && dir.exists(mapped) &&
        startsWith(source_path, paste0(mapped, "/"))) {
      suffix <- substring(source_path, nchar(mapped) + 2L)
      return(file.path(final_rel, suffix))
    }
  }
  NULL
}
