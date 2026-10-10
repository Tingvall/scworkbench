# Graph calls share the existing serial broker spool and process supervisor.
.wb_operation_pack_v4_scoped_assert <- function(value, field, scheme, scope) {
  observed <- value[[field]]
  .wb_graph_closed(observed, c("scheme", "scope", "sha256"), "scoped identity")
  .wb_graph_require(identical(observed$scheme, scheme) && identical(observed$scope, scope),
    "GRAPH_GRANT_INVALID", "Unknown or substituted graph identity scheme/scope.")
  preimage <- value; preimage[[field]] <- NULL
  .wb_graph_require(identical(observed, .wb_operation_pack_v2_identity_scoped(scheme, scope, preimage)),
    "GRAPH_CONTENT_IDENTITY_MISMATCH", "Self-rehashed or malformed graph identity.")
  invisible(TRUE)
}

.wb_operation_pack_v4_graph_control <- function(control, request, grant, cursor, token) {
  .wb_graph_closed(control, c("schema", "input_name", "component", "first_ordinal",
    "read_grant_identity", "transition_identity", "authorization_token", "call_identity"), "graph broker call")
  .wb_graph_require(identical(control$schema, "scworkbench.graph.broker_read_request.v1") &&
    identical(control$input_name, grant$input_name) && identical(control$read_grant_identity, grant$grant_identity) &&
    identical(control$transition_identity, request$transition$transition_identity) &&
    identical(control$authorization_token, token) && !cursor$complete &&
    identical(control$component, cursor$expected()) && identical(control$first_ordinal, cursor$offset),
    "GRAPH_GRANT_INVALID", "Graph broker call violates its private grant or ordered schedule.")
  .wb_operation_pack_v4_scoped_assert(control, "call_identity",
    "scworkbench.graph.broker_read_request.v1", "call excluding call_identity")
  invisible(TRUE)
}

.wb_operation_pack_v4_graph_ack <- function(ack, control, response, token) {
  .wb_graph_closed(ack, c("schema", "call_identity", "response_identity", "status",
    "authorization_token", "acknowledgement_identity"), "graph broker acknowledgement")
  .wb_graph_require(identical(ack$schema, "scworkbench.graph.broker_read_acknowledgement.v1") &&
    identical(ack$call_identity, control$call_identity) &&
    identical(ack$response_identity, response$response_identity) &&
    identical(ack$status, "consumed") && identical(ack$authorization_token, token),
    "GRAPH_GRANT_INVALID", "Graph acknowledgement differs from the outstanding exact response.")
  .wb_operation_pack_v4_scoped_assert(ack, "acknowledgement_identity",
    "scworkbench.graph.broker_read_acknowledgement.v1", "acknowledgement excluding acknowledgement_identity")
  invisible(TRUE)
}

.wb_operation_pack_v4_graph_service <- function(spool, request, bundle, cursors, token, deadline) {
  path <- file.path(spool, "request.json")
  .wb_graph_require(file.exists(path) && !nzchar(Sys.readlink(path)) && file.info(path)$size <= 16384,
    "GRAPH_RESOURCE_EXCEEDED", "Oversized or linked graph broker control.")
  raw <- readChar(path, file.info(path)$size, useBytes = TRUE)
  .wb_operation_pack_v2_assert_strict_json(raw)
  control <- .wb_graph_parse(raw)
  name <- control$input_name
  .wb_graph_require(.wb_graph_string(name) && !is.null(cursors[[name]]),
    "GRAPH_GRANT_INVALID", "Unknown graph reader name.")
  grant <- Filter(function(x) identical(x$input_name, name), request$graph_read_grants)[[1L]]
  cursor <- cursors[[name]]
  .wb_operation_pack_v4_graph_control(control, request, grant, cursor, token)
  part <- cursor$peek()
  response <- list(schema = "scworkbench.graph.broker_read_response.v1", partition = part,
    complete = is.null(part), call_identity = control$call_identity)
  response$response_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.graph.broker_read_response.v1", "response excluding response_identity", response)
  unlink(path)
  response_root <- file.path(spool, "response")
  pending <- file.path(spool, "response.pending")
  .wb_graph_require(!file.exists(response_root) && !file.exists(pending),
    "GRAPH_GRANT_INVALID", "Outstanding broker response was not consumed.")
  .wb_graph_require(dir.create(pending), "GRAPH_GRANT_INVALID",
    "Could not create the private graph response workspace.")
  on.exit(if (dir.exists(pending)) unlink(pending, recursive = TRUE), add = TRUE)
  .wb_operation_pack_v2_atomic_json(response, file.path(pending, "manifest.json"))
  # A process consumer treats the directory's existence as publication. Never
  # expose it before the complete manifest is durable in the private spool.
  .wb_graph_require(file.rename(pending, response_root), "GRAPH_GRANT_INVALID",
    "Could not atomically publish the complete graph response.")
  ack_path <- file.path(spool, "acknowledgement.json")
  while (!file.exists(ack_path)) {
    .wb_graph_require(Sys.time() <= deadline, "GRAPH_READER_INCOMPLETE", "Graph broker acknowledgement timed out.")
    .wb_graph_require(!file.exists(file.path(spool, "stop.json")),
      "GRAPH_READER_INCOMPLETE", "Graph broker stopped with an unacknowledged partition.")
    Sys.sleep(.02)
  }
  .wb_graph_require(!nzchar(Sys.readlink(ack_path)) && file.info(ack_path)$size <= 16384,
    "GRAPH_RESOURCE_EXCEEDED", "Oversized or linked graph acknowledgement.")
  raw <- readChar(ack_path, file.info(ack_path)$size, useBytes = TRUE)
  .wb_operation_pack_v2_assert_strict_json(raw)
  ack <- .wb_graph_parse(raw)
  .wb_operation_pack_v4_graph_ack(ack, control, response, token)
  # Only an exact authenticated ACK advances the core observation.
  cursor$accept(part)
  unlink(ack_path); unlink(response_root, recursive = TRUE)
  invisible(TRUE)
}
