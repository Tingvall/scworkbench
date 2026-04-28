# Dataset Brief for Agent

## Overview

The bundle contains **9 single-cell datasets** representing hematopoietic progenitor and lymphoid populations from mouse:

1. **LSK**
2. **FTL3**
3. **IL7Ra**
4. **CD19**
5. **DN**
6. **CD3**
7. **IL7RSP**
8. **LPAMSP**
9. **DP**

These datasets collectively span early progenitor states and lymphoid differentiation toward B and T cell lineages.

The goal is to reconstruct biologically meaningful developmental structure using the latent representation provided.

---

## Biological Context (High-Level)

These populations are expected to represent:

* **Early hematopoietic progenitors**

  * LSK
  * FTL3
  * IL7Ra

* **B-lineage committed cells**

  * CD19

* **T-lineage populations**

  * DN
  * DP
  * CD3
  * IL7RSP
  * LPAMSP

The datasets were generated under consistent experimental conditions and integrated into a shared latent representation.

No guarantee is made that labels perfectly reflect biological ordering.
The agent should infer structure from the data rather than assuming label hierarchy.

---

## Representation

* A denoised latent space is available: **`peakvi_space`**
* This space captures chromatin accessibility structure across all datasets.
* It should be treated as the primary manifold for neighborhood graph construction and trajectory inference.

---

## Objective


Identify a biologically plausible B-cell trajectory. 
Validate that trajectory using canonical marker trends usinga small feature set/
Perform pathway analysis along the main B-cell trajectory using gene sets namespaced as:

```
bcell_gsea::*
```

5. Produce a full scientific manuscript describing the results.

---

## Expectations

* The inferred trajectory should align with known principles of B-cell development:

  * early progenitor → commitment → maturation
* Marker dynamics should follow coherent biological ordering.
* T-lineage structure may be present in the space but is not the focus of this analysis.
* The analysis should not rely purely on dataset labels; labels are informative but not authoritative.

---

## Deliverable

A full manuscript including:

* Developmental reconstruction in latent space
* Justification of trajectory start/end states
* Marker validation
* Pathway dynamics along B pseudotime
* Interpretation in biological context

---

