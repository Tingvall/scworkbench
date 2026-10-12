lib <- "/tmp/scwb-legacy-inspection-566.e46ahol2/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
e <- new.env(parent=asNamespace("scworkbench"))
sys.source("notes/generic_graph_implementation/evidence/580_peakvi_report_diagnostic_test.R",e)
e$test_phase6_peakvi_no_pack_catalog_and_historical_inspection_contract()
