test_analysis_capsule_documentation_policy_contract <- function() {
  root<-normalizePath(Sys.getenv("SCWORKBENCH_SOURCE_ROOT",unset="."),winslash="/",mustWork=TRUE)
  paths<-file.path(root,c("inst/onboarding/ANALYSIS_CAPSULES.md","inst/onboarding/AGENT_OPERATOR_GUIDE.md","inst/onboarding/AGENT_ENGINEER_GUIDE.md","inst/onboarding/SHARED_FOUNDATION.md","README.md","man/wb_capsule_register.Rd","man/wb_capsule_scaffold.Rd","man/wb_capsule_emit_reproduction.Rd"))
  stopifnot(all(file.exists(paths)))
  text<-paste(vapply(paths,function(p)paste(readLines(p,warn=FALSE),collapse="\n"),character(1)),collapse="\n")
  required<-c("Ad hoc analysis is permitted; unrecorded durable evidence is not.","A capsule should contain only the irreducibly dataset- or question-specific terminal portion","Inspect registered operation, wrangler, and plotting contracts first","paper-specific three-panel representation figure","custom matrix or space","exploratory script -> registered capsule -> reviewed op candidate -> tested op","externally_executed","not_verified","use_existing_op","split_standard_and_custom","bounded parsed-source review","positional `op_name` form","Comments, report prose","unrelated string literals do not count as calls","analysis/capsules/.pending/<capsule_id>","provably uncommitted","read-only open fail closed while unresolved residue remains")
  stopifnot(all(vapply(required,function(x)grepl(x,text,fixed=TRUE),logical(1))))
  capsule_public<-paste(readLines(file.path(root,"inst/onboarding/ANALYSIS_CAPSULES.md"),warn=FALSE),paste(readLines(file.path(root,"R/analysis_capsules.R"),warn=FALSE),collapse="\n"),collapse="\n")
  internal_names<-c("Forge","Scout","Controller","Quill","Lumen")
  stopifnot(!any(vapply(internal_names,function(x)grepl(x,capsule_public,fixed=TRUE),logical(1))))
  mutations<-wb_mutation_catalog_semantic()$records;mi<-which(vapply(mutations,function(x)identical(x$function_name,"wb_capsule_register"),logical(1)))
  stopifnot(!"wb_capsule_register"%in%wb_list_ops(),length(mi)==1L,mutations[[mi]]$route=="exclusive_atomic_capsule_publication")
  getters<-vapply(wb_getter_catalog_semantic()$getters,`[[`,character(1),"function_name")
  stopifnot(all(c("wb_capsules","wb_capsule","wb_capsule_inputs","wb_capsule_outputs","wb_capsule_script_path","wb_capsule_output_path")%in%getters))
  TRUE
}
