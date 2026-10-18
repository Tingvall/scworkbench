# Matched Xenopus direct comparator specification

No scientific code or pack changes. Inspected pinned scwbRNA
`151dd29211b219343dce6247c5e48fc932b4c83d` and scwbRepresentation
`be51127ca0d7c11a0667be826c24449a5c7e8912`.

Complete direct execution must include source RDS reading, source BPCells
storage, normalized BPCells fragment writing, selected-feature tables, PCA HDF5
coordinates/tables, UMAP coordinates and saved `uwot` model, then close/reopen
and numerical comparison. A raw arithmetic-only timer is not equivalent.
Input/analysis/output IO should be timed separately from bundle-only services
(provenance, closures, finalization, recipient validation).

1. RNA `R/matrix_log_normalize.R:1-64`: for each source fragment, partition
   cells by 2,000; `library_size <- as.numeric(Matrix::colSums(values))`;
   replace non-finite or <=0 denominators with Inf;
   `normalized <- log1p(t(t(as.matrix(values)) * (10000 / denom)))`.
   Write double, uncompressed BPCells, preserving exact feature/cell names.
   Do not substitute BPCells lazy SIMD `log1p` (previous comparison showed
   precision differs), sparse-only arithmetic or a changed partition size.
2. RNA `R/helpers.R:37-54`, `R/hvg_select.R:1-84`: feature chunks 256;
   `mu <- as.numeric(Matrix::rowMeans(x))`,
   `ss <- as.numeric(Matrix::rowSums(x*x))`,
   `variance <- pmax((ss-n*mu*mu)/(n-1),0)`,
   `detected <- as.numeric(Matrix::rowSums(x>0))`;
   `dispersion <- variance/pmax(mean,.Machine$double.eps)`;
   vst score `log1p(pmax(dispersion,0))` (not Seurat vst).
   No batch key/filter. Rank with
   `order(!passes,-score,-variance,feature_id,na.last=TRUE)`.
   Select 2,000 passing rows. Preserve complete ranked table, not just IDs.
3. Representation `R/pca_fit.R:1-112`: read selected features in chunks 256,
   transpose each to cells-by-features and bind in declared feature order.
   Calculate `feature_mean <- colMeans(x)` and
   `feature_var <- apply(x,2L,stats::var)`; retain finite variance >0.
   `set.seed(1L)` immediately before
   `irlba::prcomp_irlba(fit_x,n=50L,center=TRUE,scale.=TRUE)`.
   Coordinates fit$x[,1:50]; loadings zero-filled for filtered features;
   variance `sdev^2`, proportion divided by `sum(fit$sdev^2)`.
   IRLBA signs/subspaces must be compared with a declared policy if exact
   reproducibility is not obtained under otherwise identical libraries.
4. Representation `R/umap.R:26-67`: select PCA dims 1:30 in declared cell
   order; immediately `set.seed(1L)` before
   `uwot::umap(x,n_neighbors=30L,min_dist=.3,metric='euclidean',
   nn_method='nndescent',spread=1,n_threads=1L,n_sgd_threads=1L,
   seed=1L,ret_model=TRUE,verbose=FALSE)`.
   Save with `uwot::save_uwot(fit,path,verbose=FALSE)`; load saved model
   for verification. Merely retaining embedding while omitting model writing
   understates direct IO. Do not replace nn_method or algorithms for speed.

Determinism requires identical process/package versions, explicit seeds, exact
ordered features and cells and identical thread arguments. Independent direct
computation can follow these expressions without invoking private pack runners.
This document is source inspection, not an executed full-size comparison.
