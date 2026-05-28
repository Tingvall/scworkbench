# Agent Protocol

This folder defines the multi-agent operating protocol for `scworkbench` workflows.

## Team Roles

- Engineer agent: extends engine/client capabilities (ops, wranglers, contracts, tests).
- Biologist agent: runs analyses only via engine ops/wranglers and interprets results.
- Scientific writer agent: composes manuscript-ready narrative from evidence packages.

## Core Principle

All scientific claims must be traceable to run/artifact evidence.

## Required Files Per Cycle

1. `analysis_request.md`
2. `run_ledger.csv`
3. `session_log.md`
4. Optional: `capability_request.md` + `engine_change_note.md`
5. `analysis_report.md/html` + run context + DAG exports
6. `claim_evidence_map.csv`

## Pilot Cycle Steps

1. Fill `analysis_request.md`.
2. Biologist runs initial workflow with existing ops.
3. If blocked, biologist opens `capability_request.md`.
4. Engineer delivers change with `engine_change_note.md` and passing gate.
5. Biologist reruns and updates report + ledger.
6. Freeze evidence package and hand to writer.
7. Writer drafts manuscript using `manuscript_outline.md` + `claim_evidence_map.csv`.
