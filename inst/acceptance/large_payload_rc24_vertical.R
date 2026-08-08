#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly=TRUE)
bundle_arg <- grep("^--bundle=",args,value=TRUE)
if(length(bundle_arg)!=1L) stop("Usage: large_payload_rc24_vertical.R --bundle=/path",call.=FALSE)
unknown <- setdiff(args,bundle_arg)
if(length(unknown)) stop("Unknown argument(s): ",paste(unknown,collapse=", "),call.=FALSE)
source_root <- Sys.getenv("SCWORKBENCH_SOURCE_ROOT",unset="")
if(nzchar(source_root)) devtools::load_all(source_root,quiet=TRUE) else library(scworkbench)

options(stringsAsFactors=FALSE,warn=2)
bundle_dir <- normalizePath(sub("^--bundle=","",bundle_arg[[1L]]),winslash="/",mustWork=TRUE)
matrix_id <- "RNA_log1p_cp10k"
pca_id <- "rna_pca_hvg2000"
umap_id <- "rna_umap_pca30"

b <- wb_open_bundle(bundle_dir)
on.exit(try(wb_close_bundle(b),silent=TRUE),add=TRUE)
stopifnot(
  !matrix_id %in% wb_matrices(b)$matrix_id,
  !pca_id %in% wb_spaces(b)$space_id,
  !umap_id %in% wb_spaces(b)$space_id,
  nrow(wb_prov_list_heads(b))==3L,
  nrow(wb_art_list(b))==2L
)

s <- wb_session_new()
r_norm <- wb_session_run_op(s,b,"matrix_log_normalize",inputs=list(
  matrix="RNA_counts",cell_set="all",min_cells=10L,output_matrix_id=matrix_id,
  scale_factor=10000,overwrite=FALSE
),notes="Conventional all-cell RNA library-size normalization: log1p(counts / cell library size * 10,000).")
s <- r_norm$session
r_hvg <- wb_session_run_op(s,b,"hvg_select",inputs=list(
  matrix=matrix_id,cell_set="all",min_cells=10L,n_features=2000L,method="vst",
  seed=1L,chunk_size=256L
),notes="Select 2,000 highly variable features across all imported cells using the registered VST score.")
s <- r_hvg$session
r_pca <- wb_session_run_op(s,b,"pca_fit",inputs=list(
  matrix=matrix_id,features=wb_ref_run(r_hvg$run$run_id,"selected_features"),
  cell_set="all",min_cells=10L,n_components=50L,center=TRUE,scale=TRUE,
  backend="irlba",seed=1L,space_id_out=pca_id,overwrite=FALSE,max_dense_gb=4
),notes="Conventional PCA on all cells using the 2,000 selected HVGs; 50 centered and scaled components with IRLBA.")
s <- r_pca$session
r_umap <- wb_session_run_op(s,b,"umap_fit",inputs=list(
  space=pca_id,cell_set="all",min_cells=10L,dims=1:30,space_id_out=umap_id,
  n_neighbors=30L,min_dist=0.3,metric="euclidean",nn_method="annoy",spread=1,
  seed=1L
),notes="Conventional all-cell UMAP from PCs 1-30; 30 neighbors, min_dist 0.3, Euclidean metric, Annoy backend, seed 1.")
s <- r_umap$session

staged <- wb_session_view(s)
stopifnot(matrix_id %in% wb_matrices(staged)$matrix_id,pca_id %in% wb_spaces(staged)$space_id,umap_id %in% wb_spaces(staged)$space_id)

promotion <- wb_session_promote_current(b,s,outputs=list(
  wb_ref_run(r_norm$run$run_id,"summary"),
  wb_ref_run(r_hvg$run$run_id,"selected_features"),
  wb_ref_run(r_hvg$run$run_id,"fit_summary"),
  wb_ref_run(r_pca$run$run_id,"loadings"),
  wb_ref_run(r_pca$run$run_id,"variance"),
  wb_ref_run(r_pca$run$run_id,"fit_summary"),
  wb_ref_run(r_umap$run$run_id,"model"),
  wb_ref_run(r_umap$run$run_id,"space_2d")
),name_prefix="all_cells_rna",created_by="forge-large-payload-acceptance",fail_fast=TRUE)
ok <- promotion$promoted[promotion$promoted$status=="ok",,drop=FALSE]
stopifnot(nrow(ok)==8L,all(ok$lineage_status=="complete"))

schemes <- DBI::dbGetQuery(b$con,"SELECT run_hash,run_hash_scheme,contract_hash,contract_hash_scheme FROM prov_runs WHERE snapshot_id=?;",params=list(promotion$provenance_snapshot_id))
stopifnot(nrow(schemes)==4L,all(grepl("^[0-9a-f]{64}$",schemes$run_hash)),all(grepl("^[0-9a-f]{64}$",schemes$contract_hash)),all(schemes$run_hash_scheme==scworkbench:::.wb_identity_schemes()[["run"]]),all(schemes$contract_hash_scheme==scworkbench:::.wb_identity_schemes()[["contract"]]))

artifacts <- wb_art_list(b)
model_art <- as.character(ok$artifact_id[ok$output=="model"])[1]
cert <- wb_art_birth_certificate(b,model_art)
stopifnot(identical(as.character(cert$artifact$artifact_id),model_art),nrow(wb_prov_bundle_dag(b)$nodes)>0L,nrow(wb_kg_provenance_graph(b)$nodes)>0L)
stopifnot(matrix_id %in% wb_matrices(b)$matrix_id,pca_id %in% wb_spaces(b)$space_id,umap_id %in% wb_spaces(b)$space_id)

readiness <- wb_finalize_recipient_bundle(b)
stopifnot(isTRUE(readiness$ready))
wb_close_bundle(b); b <- NULL

validation <- wb_bundle_validation_report(bundle_dir,"recipient",progress=TRUE)
stopifnot(isTRUE(validation$ok),identical(validation$pre_validation_fingerprint,validation$post_validation_fingerprint))
ro <- wb_open_bundle(bundle_dir,read_only=TRUE,validate=TRUE)
on.exit(try(wb_close_bundle(ro),silent=TRUE),add=TRUE)
ro_spaces <- wb_spaces(ro)
stopifnot(matrix_id %in% wb_matrices(ro)$matrix_id,pca_id %in% ro_spaces$space_id,umap_id %in% ro_spaces$space_id,
          as.integer(ro_spaces$dims[ro_spaces$space_id==pca_id])==50L,
          as.integer(ro_spaces$dims[ro_spaces$space_id==umap_id])==2L,
          nrow(wb_prov_bundle_dag(ro)$nodes)>0L,nrow(wb_kg_provenance_graph(ro)$nodes)>0L)
wb_close_bundle(ro); ro <- NULL

cat("PROMOTION_SNAPSHOT=",promotion$provenance_snapshot_id,"\n",sep="")
cat("PROMOTED_OUTPUTS=",nrow(ok),"\n",sep="")
cat("ARTIFACTS=",nrow(artifacts),"\n",sep="")
cat("RECIPIENT_STATUS=",validation$status,"\n",sep="")
cat("RECIPIENT_ELAPSED_SECONDS=",validation$elapsed_seconds,"\n",sep="")
cat("RECIPIENT_PROCESS_PEAK_RSS_MB=",validation$process_peak_rss_mb,"\n",sep="")
cat("FINGERPRINT_EQUAL=",identical(validation$pre_validation_fingerprint,validation$post_validation_fingerprint),"\n",sep="")
cat("PCA_DIMS=50 UMAP_DIMS=2\n")
cat("ALL_RNA_ANALYSIS_AND_VALIDATION_CHECKS_PASSED\n")
