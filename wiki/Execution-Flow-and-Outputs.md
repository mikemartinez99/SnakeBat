# Execution Flow and Outputs

[← Snakemake Workflow](Snakemake-Workflow)

This page traces the complete sequence of events from invoking `snakemake --cores 2` to a finished run, explains the DAG structure, and documents the output directory layout.

---

## The DAG

Snakemake builds a **Directed Acyclic Graph (DAG)** of jobs before running anything. For this pipeline with 2 samples, the DAG is:

```
calc_RMS_Power(test1) ──┐
                         ├──► rule all ──► done.txt
calc_RMS_Power(test2) ──┘
```

The two `calc_RMS_Power` jobs have **no dependency on each other** — they read from different input directories and write to different output directories. With `--cores 2`, Snakemake runs them in parallel. `rule all` cannot begin until both output directories exist.

Snakemake constructs this graph by:

1. Starting at `rule all` (the default target, being first in the file)
2. Seeing its `input` requires `RMS_Power/test1.RMS_Power` and `RMS_Power/test2.RMS_Power`
3. Neither exists on disk → searching for rules that produce them
4. `rule calc_RMS_Power` matches with `{sample}` = `"test1"` and `{sample}` = `"test2"`
5. Those rules have no `input:` block → no further dependencies → schedule both immediately

---

## End-to-End Execution Trace

```
snakemake --cores 2
│
├── Read Snakefile (Python header executes)
│   ├── Parse config.yaml → config dict
│   ├── Read folders.csv → samples_df DataFrame
│   └── Build sample_list = ["test1", "test2"]
│
├── Build DAG
│   ├── rule all needs: RMS_Power/test1.RMS_Power, RMS_Power/test2.RMS_Power
│   ├── Neither exists → schedule calc_RMS_Power for each
│   └── Both have no inputs → schedule both immediately (parallel)
│
├── [PARALLEL] Run calc_RMS_Power(test1) and calc_RMS_Power(test2)
│
│   For each sample, the sequence is:
│   │
│   ├── Activate snakeBat conda environment
│   ├── Execute: Rscript code/01_calcRMS_Power.R [8 args] &> logs/{sample}.log
│   │
│   │   ── Inside 01_calcRMS_Power.R ──────────────────────────────────────
│   │   │
│   │   ├── Load libraries (seewave, lubridate, tuneR, tools)
│   │   ├── source("code/BatFunctions.R")
│   │   ├── Parse 8 command-line arguments
│   │   ├── Validate dataDir exists
│   │   ├── Log all 8 parameters to stderr → log file
│   │   │
│   │   ├── [PHASE 1] Call rmsPower()
│   │   │   │
│   │   │   ├── Validate dataDir and outputDir
│   │   │   ├── List all .WAV files recursively in dataDir
│   │   │   ├── Initialize progress bar
│   │   │   │
│   │   │   └── For each .WAV file:
│   │   │       ├── Check if output CSV already exists → skip if yes (idempotency)
│   │   │       ├── tryCatch: readWave() → raw.wav (skip on corrupt file)
│   │   │       ├── bwfilter(30–70 kHz, Butterworth) → wav
│   │   │       ├── Calculate num_segments = floor(duration / segmentDuration)
│   │   │       ├── Preallocate rmsenergy vector (length = num_segments)
│   │   │       │
│   │   │       └── For each 1-second segment j:
│   │   │           ├── Compute start/end sample indices
│   │   │           ├── Slice wav[start:end] → segment
│   │   │           ├── segment@left / 32768 → MLV (normalize to [–1, 1])
│   │   │           ├── rms(MLV) → RMS amplitude
│   │   │           ├── 20 × log10(rms / 1) → dBFS
│   │   │           ├── dBFS + gainOffset (6.3) → gain-adjusted dBFS
│   │   │           └── Store in rmsenergy[j]
│   │   │
│   │   │           write.csv(rmsenergy, outputDir/{stem}_RMSPower_1Second.csv)
│   │   │
│   │   ├── [PHASE 2] Reorganize CSVs by date (mclapply, up to 4 cores)
│   │   │   │
│   │   │   ├── For each flat CSV in outputDir/:
│   │   │   │   ├── Extract date from filename: regex .*_(\d{8})_.* → "YYYYMMDD"
│   │   │   │   ├── Create outputDir/YYYYMMDD/ if absent
│   │   │   │   ├── Read CSV, rename columns to rmsEnergy
│   │   │   │   ├── na.omit() → skip if empty
│   │   │   │   ├── Drop index columns (X, X.1)
│   │   │   │   ├── Compute AdjustedValue = rmsEnergy + abs(min(rmsEnergy))
│   │   │   │   └── Write to outputDir/YYYYMMDD/{filename}
│   │   │   │
│   │   │   └── Delete original flat CSVs from outputDir/ top level
│   │   │
│   │   └── [PHASE 3] Collate per-date totals (mclapply, up to 4 cores)
│   │       │
│   │       ├── List date subdirectories in outputDir/
│   │       ├── Create Total_RMSE/{sample}/ directory
│   │       │
│   │       └── For each date subdirectory:
│   │           ├── Call calcTotalRMSE(folder, date)
│   │           │   ├── Read all CSVs in the date folder
│   │           │   ├── Validate rmsEnergy and AdjustedValue columns
│   │           │   ├── Parse "YYYYMMDD" → "YYYY-MM-DD" + Julian day
│   │           │   ├── do.call(rbind, ...) → one long dataframe
│   │           │   ├── Compute total_raw_rmse = sum(rmsEnergy)
│   │           │   └── Compute total_adj_rmse = sum(AdjustedValue)
│   │           └── Write to Total_RMSE/{sample}/{date}_total_RMSE.csv
│   │
│   └── Directory RMS_Power/{sample}.RMS_Power/ exists → job complete
│
└── Both calc_RMS_Power jobs complete → run rule all
    └── touch done.txt
```

---

## Output Directory Structure

After a successful run with 2 samples, each spanning 1 date:

```
SnakeBat/
│
├── done.txt                                   ← pipeline complete sentinel
│
├── logs/
│   ├── test1.log                              ← full R console output for test1
│   └── test2.log                              ← full R console output for test2
│
├── RMS_Power/
│   ├── test1.RMS_Power/
│   │   └── 20250529/
│   │       ├── PAB_BB_052925_AM68_000000_RMSPower_1Second.csv
│   │       ├── PAB_BB_052925_AM68_001000_RMSPower_1Second.csv
│   │       └── ...                            ← one file per original .WAV
│   └── test2.RMS_Power/
│       └── 20250529/
│           └── ...
│
└── Total_RMSE/
    ├── test1.RMS_Power/
    │   └── 20250529_total_RMSE.csv            ← all seconds for this date + totals
    └── test2.RMS_Power/
        └── 20250529_total_RMSE.csv
```

---

## Output File Schemas

### Per-file RMS CSVs (`RMS_Power/{sample}/{date}/*.csv`)

One file per original `.WAV` recording. Each row is one time segment.

| Column | Type | Description |
|--------|------|-------------|
| *(row index)* | integer | Written by `write.csv(..., row.names = TRUE)` |
| `rmsEnergy` | numeric | Gain-adjusted RMS energy in dBFS (negative, typically –90 to –20) |
| `AdjustedValue` | numeric | `rmsEnergy` shifted so the minimum value = 0 (non-negative) |

### Daily Summary CSVs (`Total_RMSE/{sample}/{date}_total_RMSE.csv`)

One file per date per sample. Each row is one second of audio from one recording file — all files for that date are row-bound together.

| Column | Type | Description |
|--------|------|-------------|
| *(row index)* | integer | Row number from the combined dataframe |
| `rmsEnergy` | numeric | Gain-adjusted RMS energy in dBFS |
| `AdjustedValue` | numeric | Zero-anchored adjusted RMS energy |
| `date` | character | Recording date as `"YYYY-MM-DD"` |
| `Julian` | integer | Day of year (1–365 or 1–366 in leap years) |
| `total_raw_rmse` | numeric | Sum of all `rmsEnergy` values for this date (scalar, replicated on every row) |
| `total_adj_rmse` | numeric | Sum of all `AdjustedValue` values for this date (scalar, replicated on every row) |

### Log files (`logs/{sample}.log`)

Contains the full R console output (`stdout` + `stderr`) for that sample's run, including:
- All 8 parameter values logged at startup
- Per-file progress messages from `rmsPower()`
- The text progress bar output (may appear garbled in a log file viewer)
- Any warnings from `tryCatch` about skipped corrupt files
- Any errors that caused the job to fail

---

## Concatenating Daily Summary Files

To combine all per-date summary files for a sample into one flat file:

```bash
cd Total_RMSE/test1.RMS_Power/
awk 'FNR==1 && NR!=1 { next } { print }' *.csv > combined_daily_totals.csv
```

This keeps the header from the first file and drops headers from all subsequent files before concatenating.

---

## Re-running the Pipeline

**If you add new samples to `folders.csv`:**
Snakemake will detect that their output directories do not exist and run only those new jobs. Completed samples are untouched.

**If you want to reprocess everything from scratch:**
```bash
rm -rf RMS_Power/ Total_RMSE/ logs/ done.txt
snakemake --cores 2
```

**If the pipeline crashed mid-run:**
```bash
snakemake --unlock   # remove the directory lock left by the crashed process
snakemake --cores 2  # resume — already-finished files are skipped by the idempotency check in rmsPower()
```

**If you modified config parameters and want to rerun:**
Snakemake does not automatically detect config changes. Move or delete the output directories manually, then rerun.

---

[← Snakemake Workflow](Snakemake-Workflow) | [↑ Home](Home)
