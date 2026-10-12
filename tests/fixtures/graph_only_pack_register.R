.emit_graph <- function(readers, writers, params, context) {
  writers$write_graph("result", scworkbench::wb_prim_graph(
    list(list(node_id = "HEL"), list(node_id = "ARN"), list(node_id = "TLL")),
    list(), list(), direction_mode = "undirected"))
  list(status = "ok")
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(system.file("scworkbench",
    "operation-pack.json", package = "scwbGraphOnlyFixture"),
    list(`graphonlyfixture::emit_graph` = .emit_graph))
}
