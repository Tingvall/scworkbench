# Pilot Run Instructions

## 1) Initialize a new cycle folder

Create a timestamped working folder under your bundle reports area, for example:

`<bundle>/reports/<timestamp>_agent_cycle_001/`

Copy templates into it:
- `analysis_request_template.md` -> `analysis_request.md`
- `run_ledger_template.csv` -> `run_ledger.csv`
- `session_log_template.md` -> `session_log.md`
- `claim_evidence_map_template.csv` -> `claim_evidence_map.csv`

## 2) Biologist kickoff

- Fill `analysis_request.md`.
- Execute initial workflow with existing ops.
- Log each run/artifact in `run_ledger.csv`.

## 3) Engineer escalation (if blocked)

- Open `capability_request.md` from template.
- Engineer implements and fills `engine_change_note.md`.
- Validate tests + smoke run, then hand back.

## 4) Biologist rerun and report

- Re-run with new capability.
- Generate report, plots, and replay script.
- Complete `claim_evidence_map.csv`.

## 5) Writer handoff

- Verify `evidence_bundle_checklist.md` is complete.
- Writer uses `manuscript_outline_template.md` for draft.
