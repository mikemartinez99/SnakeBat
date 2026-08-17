# Repository Overview

[← Home](Home)

This page describes the role of every file in the SnakeBat repository and summarizes the high-level data flow through the pipeline.

---

## File Tree

```
SnakeBat/
├── Snakefile                  # Snakemake workflow definition (Python-based DSL)
├── pixi.toml                  # Software environment + named tasks (recommended)
├── pixi.lock                  # Exact resolved package versions - commit this
├── config.yaml                # User-facing parameter configuration
├── folders.csv                # Maps sample names to raw data directories
├── env_config/
│   └── snakeBat.yaml          # Conda environment definition (alternative to pixi)
├── code/
│   ├── BatFunctions.R         # Signal processing functions + logging helpers
│   ├── 01_calcRMS_Power.R     # Rule 1 driver: RMS power per sample
│   ├── 02_collateSummary.R    # Rule 3 driver: cross-site nightly summary
│   └── 03_plotSiteTotals.R    # Rule 4 driver: nightly RMS plot per site
├── logs/                      # One log per rule, per sample (created at runtime)
├── results/                   # ALL pipeline output (created at runtime)
└── img/
    ├── SnakeBat_logo.png
    └── dag.png                # Snakemake DAG visualization
```

---

## Role of Each File

### `Snakefile`
The orchestration layer. Written in Snakemake's Python-based DSL, it reads configuration, discovers samples from `folders.csv`, and defines the rules that tell Snakemake what to build and how. Users should never need to edit this file directly. See [Snakemake Workflow](Snakemake-Workflow).

### `config.yaml`
The single user-facing control panel. Contains all tunable parameters: segment duration, file type, sampling rate, gain offset, and bandpass filter frequencies. See [Snakemake Configuration](Snakemake-Configuration).

### `folders.csv`
A two-column CSV (`sample`, `folder`) that maps short sample identifiers to the absolute paths of raw `.WAV` data directories. Add one row per recording session you want to process. See [Snakemake Configuration](Snakemake-Configuration).

### `env_config/snakeBat.yaml`
A conda environment specification that pins all Python and R dependencies. Snakemake uses this file to activate the correct environment before running any rule. See [Snakemake Configuration](Snakemake-Configuration).

### `code/BatFunctions.R`
Defines two functions: `rmsPower()` (the signal processing engine) and `calcTotalRMSE()` (the collation function). This file is never called directly — it is `source()`'d by the driver script. See:
- [Signal Processing — `rmsPower()`](Signal-Processing-rmsPower)
- [Signal Processing — `calcTotalRMSE()`](Signal-Processing-calcTotalRMSE)

### `code/01_calcRMS_Power.R`
The entry point called by Snakemake via `Rscript`. Parses command-line arguments, calls `rmsPower()`, reorganizes outputs by date, and calls `calcTotalRMSE()` to produce daily summaries. See [Driver Script](Driver-Script).

---

## Data Flow Summary

```
config.yaml ──────────────────────────────────────────────┐
folders.csv ──► Snakefile (DAG construction) ──► one job  │
                                                  per      │
                                                  sample   │
                                                    │      │
                                                    ▼      ▼
                                           Rscript 01_calcRMS_Power.R
                                                    │
                          ┌─────────────────────────┤
                          │                         │
                          ▼                         ▼
                    BatFunctions.R           [post-processing]
                    rmsPower()               │
                    │                        ├── reorganize by date
                    │                        │   (regex date extract,
                    │                        │    AdjustedValue compute)
                    │                        │
                    │                        └── calcTotalRMSE()
                    │                            (per-date totals,
                    │                             Julian day)
                    ▼                            ▼
              RMS_Power/{sample}/           Total_RMSE/{sample}/
              YYYYMMDD/*.csv                YYYYMMDD_total_RMSE.csv
```

**Step by step:**

1. Snakemake reads `config.yaml` and `folders.csv` to know what to process and with what parameters.
2. For each sample (row in `folders.csv`), Snakemake spawns one job that calls `01_calcRMS_Power.R` via `Rscript`.
3. `01_calcRMS_Power.R` sources `BatFunctions.R`, parses command-line arguments, and delegates to `rmsPower()`.
4. `rmsPower()` applies a Butterworth bandpass filter to each `.WAV` file, then computes RMS energy per time segment.
5. After `rmsPower()` returns, `01_calcRMS_Power.R` reorganizes flat CSVs into date subdirectories and computes `AdjustedValue`.
6. `calcTotalRMSE()` is called for each date subdirectory, producing one summary CSV per date with totals and Julian dates.

---

*Next: [Signal Processing — `rmsPower()`](Signal-Processing-rmsPower)*
