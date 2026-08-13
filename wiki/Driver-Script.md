# Driver Script — `01_calcRMS_Power.R`

[← `calcTotalRMSE()`](Signal-Processing-calcTotalRMSE) | [Next: Snakemake Configuration →](Snakemake-Configuration)

**File:** `code/01_calcRMS_Power.R`

This is the entry point called by Snakemake for every sample. It does not contain signal processing logic — its responsibilities are:

1. Load libraries and source `BatFunctions.R`
2. Parse 8 command-line arguments passed by Snakemake
3. Validate input and log all parameters
4. **Phase 1** — call `rmsPower()` to produce per-file RMS CSVs
5. **Phase 2** — reorganize flat CSVs into date subdirectories, compute `AdjustedValue`
6. **Phase 3** — call `calcTotalRMSE()` per date to produce daily summary CSVs

---

## Library Loading and Sourcing (Lines 1–6)

```r
library(seewave)
library(lubridate)
library(tuneR)
library(tools)

source("code/BatFunctions.R")
```

| Library | Provides |
|---------|----------|
| `seewave` | `bwfilter()` (bandpass filter) and `rms()` (RMS calculation) |
| `lubridate` | `yday()` (Julian day-of-year) |
| `tuneR` | `readWave()` (binary WAV file reader) |
| `tools` | `file_path_sans_ext()` (strip file extensions from paths) |

`source("code/BatFunctions.R")` executes the functions file in the current R session, making `rmsPower()` and `calcTotalRMSE()` available. The path is relative to the **Snakemake working directory** (the SnakeBat repo root), not relative to the script itself — Snakemake always runs jobs from the project root regardless of where the script lives.

---

## Command-Line Argument Parsing (Lines 8–24)

```r
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 8 | length(args) > 7) {
    stop("Usage: RScript 01_calcRMS_Power.R <dataDir> <segmentDuration> ...")
}

dataDir         = args[1]
segmentDuration = as.numeric(args[2])
fileType        = args[3]
samplingRate    = as.numeric(args[4])
gainOffset      = as.numeric(args[5])
bwFilterFrom    = as.numeric(args[6])
bwFilterTo      = as.numeric(args[7])
outputDir       = args[8]
```

`commandArgs(trailingOnly = TRUE)` returns only the arguments passed after the script name on the command line. When Snakemake runs:

```bash
Rscript code/01_calcRMS_Power.R /data/test1 1 .WAV 192000 6.3 30000 70000 RMS_Power/test1.RMS_Power
```

this vector contains exactly those 8 strings.

Arguments 2, 4, 5, 6, and 7 are cast with `as.numeric()` because `commandArgs()` returns everything as character strings. Attempting arithmetic on them as strings would produce `NA` silently.

> **Known bug:** The validation condition `length(args) < 8 | length(args) > 7` is a tautology — for any integer n, either `n < 8` or `n > 7` is always true. For n = 8: `FALSE | TRUE = TRUE`, so the `stop()` fires even with the correct number of arguments. The intended condition is `length(args) != 8`. In practice Snakemake always passes exactly 8 arguments, so this check never runs in normal use, but the `stop()` line is currently unreachable by design.

---

## Directory Check and Parameter Logging (Lines 27–46)

```r
if (!dir.exists(dataDir)) {
    stop(paste(dataDir, "Does not exist or is empty!\n"))
}

message("Starting RMS power calculation with the following arguments:")
message(paste("\tdataDir:", dataDir))
message(paste("\tsegmentDuration:", segmentDuration))
message(paste("\tfileType:", fileType))
message(paste("\tsamplingRate:", samplingRate))
message(paste("\tgainOffset:", gainOffset))
message(paste("\tbwFilterFrom:", bwFilterFrom))
message(paste("\tbwFilterTo:", bwFilterTo))
message(paste("\toutputDir:", outputDir))
```

`dataDir` is validated here before entering any function (the function also checks, but this gives a cleaner error at the top level before the function call stack gets involved).

All 8 parameters are logged via `message()`, which writes to `stderr` and therefore to the Snakemake log file at `logs/{sample}.log`. This means every log file records exactly which parameters were used for that sample's run — essential for debugging and for reproducibility across re-runs.

---

## Phase 1 — Calling `rmsPower()` (Lines 49–56)

```r
rmsPower(dataDir         = dataDir,
         segmentDuration = segmentDuration,
         fileType        = fileType,
         samplingRate    = samplingRate,
         gainOffset      = gainOffset,
         bwFilterFrom    = bwFilterFrom,
         bwFilterTo      = bwFilterTo,
         outputDir       = outputDir)
```

All 8 parsed arguments are forwarded by name to `rmsPower()`. Using named arguments (rather than positional) protects against accidentally swapping arguments of the same type. After this call returns, `outputDir` (e.g., `RMS_Power/test1.RMS_Power/`) contains one flat CSV per `.WAV` file, each named `{stem}_RMSPower_1Second.csv`.

See [Signal Processing — `rmsPower()`](Signal-Processing-rmsPower) for a full breakdown of what happens inside this call.

---

## Phase 2 — File Reorganization by Date (Lines 63–88)

After Phase 1, all per-file CSVs are flat in `outputDir`. Phase 2 reorganizes them into `YYYYMMDD/` subdirectories and adds the `AdjustedValue` column.

```r
files <- list.files(outputDir, full.names = TRUE)
library(parallel)
nCores <- min(4, detectCores())

mclapply(files, function(i) {
    fname   <- basename(i)
    date    <- sub(".*_(\\d{8})_.*", "\\1", fname)
    dateDir <- file.path(outputDir, date)
    if (!dir.exists(dateDir)) dir.create(dateDir)

    curFile <- read.csv(i)
    colnames(curFile) <- c("X", "rmsEnergy")
    curFile <- na.omit(curFile)
    if (nrow(curFile) == 0) return(NULL)

    if ("X" %in% colnames(curFile)) curFile$X <- NULL
    if ("X.1" %in% colnames(curFile)) {
        rownames(curFile) <- curFile$X.1
        curFile$X.1 <- NULL
    }
    if ("rmsenergy" %in% colnames(curFile)) colnames(curFile) <- c("rmsEnergy")

    curFile$AdjustedValue <- curFile$rmsEnergy + abs(min(curFile$rmsEnergy))
    write.csv(curFile, file = file.path(dateDir, fname), row.names = TRUE)
}, mc.cores = nCores)
```

### Date Extraction from Filename

```r
date <- sub(".*_(\\d{8})_.*", "\\1", fname)
```

AudioMoth filenames follow the pattern `DEVICEID_YYYYMMDD_HHMMSS.WAV`. The regex `.*_(\\d{8})_.*` matches this structure and the capture group `(\\d{8})` isolates exactly 8 consecutive digits (the date component). `sub()` replaces the entire filename with only that captured group, producing e.g. `"20250529"`. This date string names the subdirectory where the file will be moved.

### Column Cleanup

`write.csv(rmsenergy, ...)` in Phase 1 writes a two-column CSV: an auto-generated row-number index (no header name, read back as `"X"`) and the values column. The cleanup block:

1. Renames columns to `c("X", "rmsEnergy")` for consistency
2. Removes `NA` rows via `na.omit()`, skipping files that become empty
3. Drops the `X` index column
4. Guards against a `X.1` double-index (can occur if `write.csv` was called on a dataframe that already had row names)
5. Normalizes a lowercase `rmsenergy` column name to `rmsEnergy` (case inconsistency guard)

### `AdjustedValue` Computation

```r
curFile$AdjustedValue <- curFile$rmsEnergy + abs(min(curFile$rmsEnergy))
```

All dBFS values from `rmsPower()` are negative (0 dBFS = theoretical maximum, typical values are –90 to –20). This operation shifts the entire column upward so the quietest 1-second window maps to 0 and all other values are positive.

**Why?** Summing negative dB values partially cancels them — a very quiet second reduces the total. The zero-anchored `AdjustedValue` makes daily totals grow monotonically with acoustic activity, which is more interpretable as a bat activity index and more suitable for visualization (bar charts, heatmaps) where negative values on the y-axis are confusing.

### Parallel Execution

```r
nCores <- min(4, detectCores())
mclapply(files, ..., mc.cores = nCores)
```

`parallel::mclapply()` is a drop-in parallel replacement for `lapply()` using Unix `fork()`-based multiprocessing. Each CSV is processed independently, making this embarrassingly parallel. The core count is capped at 4 to avoid overwhelming machines with many cores, keeping the pipeline usable on shared compute nodes.

---

## Phase 2 Cleanup (Lines 90–92)

```r
csv_files <- list.files(outputDir, pattern = "\\.csv$", full.names = TRUE)
file.remove(csv_files)
```

After all files have been reorganized into date subdirectories and the adjusted versions written, the original flat CSVs at the top level of `outputDir` are deleted. This prevents double-counting during Phase 3 collation and keeps the output directory tidy.

---

## Phase 3 — Collation into Daily Totals (Lines 99–124)

```r
subdirs <- list.dirs(outputDir, recursive = FALSE, full.names = TRUE)
dates   <- basename(subdirs)
names(subdirs) <- dates
names(dates)   <- dates

opDir <- "Total_RMSE/"
if (!dir.exists(opDir)) dir.create(opDir)
sample      <- basename(outputDir)
resultsPath <- paste0(opDir, sample, "/")
if (!dir.exists(resultsPath)) dir.create(resultsPath)

mclapply(names(subdirs), function(dateName) {
    folder <- subdirs[dateName]
    total  <- calcTotalRMSE(folder, dateName)
    write.csv(total, file = paste0(resultsPath, dateName, "_total_RMSE.csv"))
}, mc.cores = nCores)
```

`list.dirs(outputDir, recursive = FALSE)` returns the date subdirectories created in Phase 2 (e.g., `RMS_Power/test1.RMS_Power/20250529/`). `basename()` extracts the date string from each path.

A **named vector** is built where names are date strings and values are full paths:

```r
names(subdirs) <- dates
```

This lets the `mclapply` lambda look up the full path from the date name: `subdirs[dateName]`.

`basename(outputDir)` extracts the sample name from the output path. For `outputDir = "RMS_Power/test1.RMS_Power"`, `basename` returns `"test1.RMS_Power"`, which becomes the sample-level subdirectory within `Total_RMSE/`.

For each date, `calcTotalRMSE()` is called with the date's directory and the date string. It returns a long dataframe (one row per second of audio) with date, Julian day, and totals columns, which is written to `Total_RMSE/test1.RMS_Power/20250529_total_RMSE.csv`.

See [Signal Processing — `calcTotalRMSE()`](Signal-Processing-calcTotalRMSE) for the full breakdown.

---

## Summary of Phases

| Phase | Input | Operation | Output |
|-------|-------|-----------|--------|
| Phase 1 | `.WAV` files in `dataDir` | Bandpass filter + RMS per second | Flat CSVs in `outputDir/` |
| Phase 2 | Flat CSVs in `outputDir/` | Date extraction, `AdjustedValue`, reorganization | CSVs in `outputDir/YYYYMMDD/` |
| Phase 3 | Date subdirectories | `calcTotalRMSE()` per date | Summary CSVs in `Total_RMSE/` |

---

*Next: [Snakemake Configuration](Snakemake-Configuration)*
