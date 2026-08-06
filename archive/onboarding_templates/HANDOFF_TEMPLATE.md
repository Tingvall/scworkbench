# Cross-Repo Agent Handoff

Save the completed form under `lymphocyte_trajectory/handoffs/` and paste it
into the controller/accountant thread after a local agent changes any repo.

Filename convention:

```text
YYYY-MM-DD_short_description.md
```

```text
Repo:
Branch/commit:
Agent role:

Files changed:

Behavior changed:

Contract changed: yes/no
If yes, describe the contract:

Bundle schema changed: yes/no
If yes, list tables/columns/payloads:

Artifact/primitive shape changed: yes/no
If yes, list affected kinds:

Op/getter/selector/wrangler changed: yes/no
If yes, list exported functions or catalog ids:

Semantic catalog updated: yes/no/not needed
If not needed, why:

R/Python parity affected: yes/no
If yes, list pybench parity map/test updates:

Client boundary risk: yes/no
If yes, explain Shiny/agent/client logic touched:

Tests run:

Fullstack check run: yes/no
If no, why:

Known failures or warnings:

Downstream risks:

Questions for controller:
```

## Quick Rules

- Mark `Contract changed: yes` for any change to bundle schema, primitive shape,
  artifact payload, op interface, getter semantics, selector semantics, semantic
  catalog records, pybench protocol, promotion/provenance, or client-facing
  behavior.
- If the change is in Shiny or `scwb-agent`, explain which engine API it calls.
- If Python writes bundle payloads, state whether R `wb_art_load()` can read
  them and which parity test covers it.
- If semantic records changed, run or mention `wb_refresh_semantic_catalogs()`.
- If possible, run:

```sh
/home/dirk/Projects/lymphocyte_trajectory/scworkbench/inst/fullstack/check_fullstack_contracts.sh
```
