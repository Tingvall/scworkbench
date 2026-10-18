args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
ns <- asNamespace('scworkbench')
patch <- new.env(parent = ns)
sys.source('R/graph_storage.R', patch)
unlockBinding('.wb_graph_page', ns)
assign('.wb_graph_page', patch$.wb_graph_page, ns)
lockBinding('.wb_graph_page', ns)
source('tests/test_engine_graph_page_contract.R')
tests <- ls(pattern = '^test_engine_graph_page_')
source('tests/test_graph_primitive_contract.R')
tests <- c(tests, 'test_graph_sql_stream_identity_contract')
for (name in tests) {
  stopifnot(isTRUE(get(name)()))
  cat(name, ' PASS\n', sep = '')
}
cat(sprintf('GRAPH_PAGE_FOCUSED discovered=%d executed=%d passed=%d skipped=0 failed=0\n',
  length(tests), length(tests), length(tests)))
