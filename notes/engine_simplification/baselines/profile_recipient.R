args<-commandArgs(TRUE);.libPaths(c(args[[1]],.libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root<-args[[3]];stopifnot(!dir.exists(root));dir.create(root,recursive=TRUE)
Rprof(file.path(root,'recipient.Rprof'),interval=.01)
t<-proc.time();report<-wb_bundle_validation_report(args[[2]],level='recipient');t<-proc.time()-t
Rprof(NULL)
stopifnot(report$ok,identical(report$pre_validation_fingerprint,report$post_validation_fingerprint))
write.csv(report$elapsed_by_check_class,file.path(root,'classes.csv'),row.names=FALSE)
prof<-summaryRprof(file.path(root,'recipient.Rprof'))
write.csv(prof$by.self,file.path(root,'by_self.csv'))
write.csv(prof$by.total,file.path(root,'by_total.csv'))
print(head(prof$by.self,25L));print(head(prof$by.total,30L))
cat('PROFILE_RECIPIENT_READONLY_OK elapsed=',t[['elapsed']],
  ' sampled=',prof$sampling.time,' seconds\n',sep='')
