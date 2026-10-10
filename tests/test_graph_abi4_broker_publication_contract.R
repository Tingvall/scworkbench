test_graph_broker_atomic_response_and_ack_contract <- function() {
  ns <- asNamespace("scworkbench")
  original <- get(".wb_operation_pack_v2_atomic_json", ns)
  root <- tempfile("graph_broker_publication_")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  on.exit(assignInNamespace(".wb_operation_pack_v2_atomic_json", original,
    ns = "scworkbench"), add = TRUE)
  token <- paste(rep("a", 64L), collapse = "")
  identity <- list(scheme = "test", sha256 = paste(rep("b", 64L), collapse = ""))
  grant <- list(input_name = "source", grant_identity = identity)
  request <- list(transition = list(transition_identity = identity),
    graph_read_grants = list(grant))
  observed <- 0L
  for (attack in c("none", "substituted_response", "substituted_token")) {
    spool <- file.path(root, attack); dir.create(spool)
    accepted <- 0L
    cursor <- new.env(parent = emptyenv())
    cursor$complete <- FALSE; cursor$offset <- "0"
    cursor$expected <- function() "header"
    cursor$peek <- function() scworkbench:::.wb_graph_partition("header", "0",
      list(list(schema = "scworkbench.graph.content.v1", direction_mode = "mixed")))
    cursor$accept <- function(part) accepted <<- accepted + 1L
    control <- list(schema = "scworkbench.graph.broker_read_request.v1",
      input_name = "source", component = "header", first_ordinal = "0",
      read_grant_identity = identity, transition_identity = identity,
      authorization_token = token)
    control$call_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
      "scworkbench.graph.broker_read_request.v1", "call excluding call_identity", control)
    original(control, file.path(spool, "request.json"))
    publish <- function(value, path) {
      stopifnot(identical(path, file.path(spool, "response.pending", "manifest.json")),
        !file.exists(file.path(spool, "response")))
      original(value, path)
      stopifnot(!file.exists(file.path(spool, "response")), file.exists(path))
      observed <<- observed + 1L
      ack <- list(schema = "scworkbench.graph.broker_read_acknowledgement.v1",
        call_identity = control$call_identity, response_identity = value$response_identity,
        status = "consumed", authorization_token = token)
      if (attack == "substituted_response") ack$response_identity$sha256 <- identity$sha256
      if (attack == "substituted_token") ack$authorization_token <- paste(rep("c", 64L), collapse = "")
      ack$acknowledgement_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
        "scworkbench.graph.broker_read_acknowledgement.v1",
        "acknowledgement excluding acknowledgement_identity", ack)
      original(ack, file.path(spool, "acknowledgement.json"))
    }
    assignInNamespace(".wb_operation_pack_v2_atomic_json", publish, ns = "scworkbench")
    result <- tryCatch(scworkbench:::.wb_operation_pack_v4_graph_service(spool,
      request, NULL, list(source = cursor), token, Sys.time() + 1), error = function(e) e)
    assignInNamespace(".wb_operation_pack_v2_atomic_json", original, ns = "scworkbench")
    if (attack == "none") stopifnot(!inherits(result, "error"), accepted == 1L,
      !file.exists(file.path(spool, "response")), !file.exists(file.path(spool, "acknowledgement.json")))
    else stopifnot(inherits(result, "wb_graph_error"), result$code == "GRAPH_GRANT_INVALID",
      accepted == 0L, file.exists(file.path(spool, "response", "manifest.json")))
    stopifnot(!file.exists(file.path(spool, "response.pending")))
  }
  stopifnot(observed == 3L)
  TRUE
}
