.emit_scenario <- function(readers, writers, params, context) {
  # Authentication is core-owned. This fixture consumes the declared input,
  # then emits an ordinary scientific constant from its own installed assets.
  invisible(readers$matrix())
  corpus <- jsonlite::read_json(system.file("scenarios.json",
    package = "scwbGraphScenarioFixture"), simplifyVector = FALSE)
  selected <- Filter(function(case) case$id == params$case, corpus$cases)
  stopifnot(length(selected) == 1L)
  content <- selected[[1L]]$content
  attrs <- content$attributes
  writers$write_graph("result", scworkbench::wb_prim_graph(content$nodes,
    content$edges, content$incidences, attrs$graph, attrs$node, attrs$edge,
    attrs$incidence, direction_mode = content$direction_mode))
  list(status = "ok")
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(system.file("scworkbench",
    "operation-pack.json", package = "scwbGraphScenarioFixture"),
    list(`graphscenariofixture::emit_scenario` = .emit_scenario))
}
