# Execution Flow and Outputs

[← Snakemake Workflow](Snakemake-Workflow)

This page traces the complete sequence of events from invoking `snakemake --cores 2` to a finished run, explains the DAG structure, and documents the output directory layout.

---

## The DAG

Snakemake builds a **Directed Acyclic Graph (DAG)** of jobs before running anything. For this pipeline with 2 samples, the DAG is:

```
calc_RMS_Power(test1) ──┬──► combine_site_totals(test1) ──► plot_site_totals(test1) ──┐
                        │                                                             │
                        ├──────────────► collate_summary ─────────────────────────────┤──► rule all
                        │                                                             │      │
calc_RMS_Power(test2) ──┴──► combine_site_totals(test2) ──► plot_site_totals(test2) ──┘      ▼
                                                                    results/full_pipeline_run_log.log
```

For 2 samples that is 8 jobs: 2 × `calc_RMS_Power`, 2 × `combine_site_totals`, 2 × `plot_site_totals`, 1 × `collate_summary`, 1 × `rule all`.

The two `calc_RMS_Power` jobs have **no dependency on each other** — they read from different input directories and write to different output directories. With `--cores 2`, Snakemake runs them in parallel. Each site's combine and plot jobs then chain off its own `calc_RMS_Power`, so site 1 can be plotting while site 2 is still measuring.

`collate_summary` waits for **every** sample, because it builds one table spanning all of them.

Snakemake constructs this graph by:

1. Starting at `rule all` (the default target, being first in the file)
2. Seeing its `input` requires the per-sample directories, the combined CSVs, the plots and the cross-site summary
3. None exist on disk → searching for rules that produce them
4. `rule calc_RMS_Power` matches with `{sample}` = `"test1"` and `{sample}` = `"test2"`
5. Those rules have no `input:` block → no further dependencies → schedule both immediately

### Why `collate_summary` depends on `RMS_Power/`, not `Total_RMSE/`

`Total_RMSE/` is written as a **side effect** of `code/01_calcRMS_Power.R` — it is not a declared Snakemake output. Snakemake therefore knows nothing about it and cannot use it to order jobs. Both `collate_summary` and `combine_site_totals` take the `results/RMS_Power/{sample}.RMS_Power` directories as input instead, since those *are* declared and are what guarantee the totals exist before anything reads them.

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
│   │           └── Write to results/Total_RMSE/{sample}.RMS_Power/{date}_total_RMSE.csv
│   │
│   └── Directory results/RMS_Power/{sample}.RMS_Power/ exists → job complete
│
├── Per sample, once its calc_RMS_Power finishes:
│   ├── combine_site_totals → awk concatenates the per-date files, keeping one header
│   │   └── results/Summary/{sample}_combined_daily_totals.csv
│   └── plot_site_totals → 03_plotSiteTotals.R
│       ├── Reduce one-row-per-second to one row per night
│       ├── Fit a GAM smooth if 4+ nights exist, otherwise skip it
│       └── results/plots/{sample}_nightly_rmse.png
│
├── Once ALL calc_RMS_Power jobs finish:
│   └── collate_summary → 02_collateSummary.R
│       └── results/Summary/all_samples_nightly_totals.csv
│
└── Everything complete → run rule all
    └── Concatenate every log in pipeline order
        └── results/full_pipeline_run_log.log
```

---

## Output Directory Structure

After a successful run with 2 samples, each spanning 1 date:

```
SnakeBat/
│
├── logs/                                      ← one log per rule, per sample
│   ├── test1.log                              ← R console output, calc_RMS_Power
│   ├── test1_combine.log
│   ├── test1_plot.log
│   ├── collate_summary.log
│   └── ...
│
└── results/                                   ← every pipeline output lives here
    │
    ├── RMS_Power/
    │   ├── test1.RMS_Power/
    │   │   └── 20250529/
    │   │       ├── PAB_BB_052925_AM68_000000_RMSPower_1Second.csv
    │   │       └── ...                        ← one file per original .WAV
    │   └── test2.RMS_Power/
    │       └── 20250529/
    │
    ├── Total_RMSE/
    │   ├── test1.RMS_Power/
    │   │   └── 20250529_total_RMSE.csv        ← all seconds for this date + totals
    │   └── test2.RMS_Power/
    │       └── 20250529_total_RMSE.csv
    │
    ├── Summary/
    │   ├── test1_combined_daily_totals.csv    ← every second, one file per site
    │   ├── test2_combined_daily_totals.csv
    │   └── all_samples_nightly_totals.csv     ← one row per site per night
    │
    ├── plots/
    │   ├── test1_nightly_rmse.png
    │   └── test2_nightly_rmse.png
    │
    └── full_pipeline_run_log.log              ← every log, concatenated in order
```

The root is set by the `RESULTS` variable at the top of the `Snakefile`; changing that one string relocates everything above.

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

### Cross-site summary (`results/Summary/all_samples_nightly_totals.csv`)

One row per sample per night — the file to open in Excel.

| Column | Type | Description |
|--------|------|-------------|
| `sample` | character | Sample name from `folders.csv` |
| `date` | character | `"YYYY-MM-DD"` |
| `Julian` | integer | Day of year |
| `n_seconds` | integer | Number of 1-second segments contributing to that night |
| `total_raw_rmse` | numeric | Sum of `rmsEnergy` for the night |
| `total_adj_rmse` | numeric | Sum of `AdjustedValue` for the night |
| `mean_rmsEnergy` | numeric | Mean of `rmsEnergy` across the night |
| `min_rmsEnergy` / `max_rmsEnergy` | numeric | Quietest and loudest second |

### Combined per-site CSVs (`results/Summary/{sample}_combined_daily_totals.csv`)

Same schema as the per-date files above, with every date for that site stacked and a single header retained. Large — roughly 3,600 rows per night.

### Log files (`logs/{sample}.log`)

Contains the full R console output (`stdout` + `stderr`) for that sample's run, including:
- Every parameter value logged at startup
- One timestamped line per recording, with status and timing
- An end-of-run summary counting processed / skipped / failed files
- Any errors that caused the job to fail

Each rule writes its own log: `{sample}.log`, `{sample}_combine.log`, `{sample}_plot.log` and `collate_summary.log`.

### Full run log (`results/full_pipeline_run_log.log`)

Written by `rule all` as the final step. Every log above, concatenated in the order the pipeline produced them, each under a labelled header. Its presence is what tells Snakemake the pipeline finished — it replaced the old `done.txt` sentinel.

---

## Concatenating Daily Summary Files

This no longer needs doing by hand. `rule combine_site_totals` runs the same `awk` automatically, once per site:

```bash
awk 'FNR==1 && NR!=1 { next } { print }' \
    results/Total_RMSE/{sample}.RMS_Power/*_total_RMSE.csv \
    > results/Summary/{sample}_combined_daily_totals.csv
```

It keeps the header from the first file and drops headers from all subsequent files. The output deliberately lands in `Summary/` rather than inside the folder being globbed, so the glob can never swallow its own output on a rerun.

Note that inside the `Snakefile` the awk braces appear doubled (`{{ }}`) — Snakemake runs shell blocks through Python string formatting first, so single braces would be read as field references.

---

## Re-running the Pipeline

**If you add new samples to `folders.csv`:**
Snakemake will detect that their output directories do not exist and run only those new jobs. Completed samples are untouched.

**If you want to reprocess everything from scratch:**
```bash
rm -rf results/ logs/
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
