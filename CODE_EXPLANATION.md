# SnakeBat — Detailed Code Explanation

**Authors:** Mike Martinez M.S. and Megan Graham

This document provides an exhaustive, line-by-line walkthrough of the SnakeBat pipeline, covering the R signal processing logic first, then how everything is orchestrated by Snakemake. Original signal processing code was written by Valerie Eddington. 

---

# Table of Contents

1. [Repository Overview](#repository-overview)
2. [Part 1 — R Code](#part-1--r-code)
   - [BatFunctions.R — `rmsPower()`](#batfunctionsr--rmspower)
   - [BatFunctions.R — `calcTotalRMSE()`](#batfunctionsr--calctotalrmse)
   - [01_calcRMS_Power.R — The Driver Script](#01_calcrms_powerr--the-driver-script)
3. [Part 2 — Snakemake Workflow](#part-2--snakemake-workflow)
   - [config.yaml](#configyaml)
   - [folders.csv](#folderscsv)
   - [env_config/snakeBat.yaml](#env_configsnakeBatyaml)
   - [Snakefile](#snakefile)
   - [How the Rules Connect](#how-the-rules-connect)
   - [Execution Flow End-to-End](#execution-flow-end-to-end)
4. [Output Directory Structure](#output-directory-structure)

---

# Repository Overview

Before diving into individual files, here is the full file tree and the role of each component:

```
SnakeBat/
├── Snakefile                  # Snakemake workflow definition (Python-based DSL)
├── config.yaml                # User-facing parameter configuration
├── folders.csv                # Maps sample names to raw data directories
├── env_config/
│   └── snakeBat.yaml          # Conda environment definition
├── code/
│   ├── BatFunctions.R         # All acoustic signal processing functions
│   └── 01_calcRMS_Power.R     # Entry-point driver script (called by Snakemake)
└── img/
    ├── SnakeBat_logo.png
    └── dag.png                # Snakemake DAG visualization
```

**Data flow summary:**

1. Snakemake reads `config.yaml` and `folders.csv` to know what to process and with what parameters.
2. For each sample (row in `folders.csv`), Snakemake spawns one job that calls `01_calcRMS_Power.R` via `Rscript`.
3. `01_calcRMS_Power.R` sources `BatFunctions.R`, parses command-line arguments, and delegates to the `rmsPower()` function.
4. `rmsPower()` applies a Butterworth bandpass filter to each `.WAV` file, then computes RMS energy per time segment.
5. After `rmsPower()` returns, `01_calcRMS_Power.R` reorganizes outputs by date and calls `calcTotalRMSE()` to produce per-date aggregate summaries.

---

# Part 1 — R Code

## `BatFunctions.R` — `rmsPower()`

**File:** [`code/BatFunctions.R`](code/BatFunctions.R), Lines 19–149

This function is the acoustic signal processing engine. It accepts a directory of `.WAV` files and, for each file, applies a bandpass filter and then computes root mean square (RMS) energy in decibels for fixed-duration time segments. It never runs on its own — it is always `source()`'d by the driver script.

---

### Function Signature (Line 19)

```r
rmsPower <- function(dataDir,        # path to folder containing .WAV files
                     segmentDuration, # length of each time window in seconds
                     fileType,        # file extension to match (e.g. ".WAV")
                     samplingRate,    # audio sampling rate in Hz (e.g. 192000)
                     gainOffset,      # microphone calibration correction in dB
                     bwFilterFrom,    # lower frequency cutoff of bandpass filter in Hz
                     bwFilterTo,      # upper frequency cutoff of bandpass filter in Hz
                     outputDir)       # where to write output CSV files
```

Every argument is user-defined. Nothing is hardcoded, which makes the function reusable across different microphone setups, bat species ranges, and recording hardware.

---

### Step 1 — Directory Validation (Lines 27–39)

```r
if (!dir.exists(dataDir)) {
  stop("Data directory does not exist!")
} else {
  message("Raw data directory located!")
}

if (!dir.exists(outputDir)) {
  dir.create(outputDir)
} else {
  message("Output directory located!")
}
```

Before touching any audio data, the function validates that the input directory is real and ensures the output directory exists (creating it if not). Failing early with a clear message here prevents cryptic errors from surfacing much later inside the loop when R tries to open a file from a path that never existed.

---

### Step 2 — File Discovery (Lines 47–51)

```r
dataFiles <- list.files(dataDir,
                        pattern = fileType,
                        full.names = TRUE,
                        recursive = TRUE)
```

`list.files()` walks the entire directory tree under `dataDir` (`recursive = TRUE`) and returns every file whose name matches `fileType` (used here as a literal string match, e.g. `".WAV"`). `full.names = TRUE` returns complete absolute paths rather than bare filenames, which is required because `tuneR::readWave()` needs a resolvable path to open the binary audio file. The recursive walk is important — AudioMoth recorders often produce output organized into date-named subdirectories, so a flat `list.files()` would miss deeply nested files.

---

### Step 3 — Progress Bar Initialization (Lines 53–55)

```r
numFiles <- length(dataFiles)
pb <- txtProgressBar(min = 0, max = numFiles, style = 3)
```

`txtProgressBar()` creates a terminal progress bar. `style = 3` produces the `[=====>   ] 45%` format with a ratio and percentage. This is purely aesthetic but practically important: processing hundreds of 10-minute `.WAV` files at 192 kHz can take hours, and without feedback the user has no way to know whether the job is progressing or hung. The bar is updated at the bottom of every iteration of the outer loop.

---

### Step 4 — The Outer Loop: Iterating Over Each File (Lines 58–141)

```r
for (f in seq_along(dataFiles)) {
    i <- dataFiles[f]
```

`seq_along(dataFiles)` generates the integer index vector `c(1, 2, 3, ..., numFiles)`. The loop variable `f` is the index and `i` is the actual file path. The reason both are needed is that the progress bar update at the end requires the numeric position `f`, while all file operations use the path `i`.

#### Skip Check — Idempotency (Lines 66–72)

```r
short_name <- tools::file_path_sans_ext(basename(i))
out_file <- file.path(outputDir, paste0(short_name, "_RMSPower_1Second.csv"))
if (file.exists(out_file)) {
  message(paste("File already exists. Skipping:", out_file))
  setTxtProgressBar(pb, f)
  next
}
```

`tools::file_path_sans_ext(basename(i))` strips the directory path and the `.WAV` extension, leaving just the stem of the filename (e.g., `PAB_20250529_000000` from `/data/PAB_20250529_000000.WAV`). A predictable output filename is then constructed by appending `_RMSPower_1Second.csv`. Before doing any expensive work, the function checks whether this output CSV already exists. If it does, the file is skipped. This makes the function **idempotent** — if a run is interrupted and restarted, it resumes from where it left off rather than reprocessing already-finished files. The progress bar is still updated before `next` to keep the displayed percentage accurate.

#### Corrupt File Handling — `tryCatch` (Lines 75–85)

```r
raw.wav <- tryCatch({
  tuneR::readWave(i)
}, error = function(e) {
  if (grepl("non-conformable arguments", e$message)) {
    warning(paste("Skipping file due to readBin error:", i))
  } else {
    warning(paste("Skipping file due to unknown error:", i, "\nError:", e$message))
  }
  setTxtProgressBar(pb, f)
  NULL
})

if (is.null(raw.wav)) { next }
```

`tuneR::readWave()` parses the binary RIFF/WAV format. Corrupted files (e.g., incomplete recordings from a battery-dying AudioMoth) cause `readWave()` to throw a hard error, which without `tryCatch` would crash the entire loop and lose all progress on that sample. The `tryCatch` block intercepts any error, issues a `warning()` (which goes to the log but does not abort), returns `NULL`, updates the progress bar, and then the `is.null()` check triggers `next` to continue to the next file. This makes the pipeline robust to field recording imperfections.

---

### Step 5 — Butterworth Bandpass Filter (Lines 93–99)

```r
wav <- bwfilter(raw.wav,
                f = samplingRate,
                from = bwFilterFrom,
                to = bwFilterTo,
                bandpass = TRUE,
                output = "Wave")
```

`seewave::bwfilter()` implements a Butterworth infinite impulse response (IIR) filter. A Butterworth filter is maximally flat in the passband — it does not introduce ripple in the frequencies it retains. The parameters:

- `f = samplingRate` (192,000 Hz): tells the filter the sample rate of the recording so it can correctly normalize the frequency cutoffs.
- `from = bwFilterFrom` (30,000 Hz): lower edge of the passband — all energy below 30 kHz is attenuated.
- `to = bwFilterTo` (70,000 Hz): upper edge of the passband — all energy above 70 kHz is attenuated.
- `bandpass = TRUE`: retains the range *between* the two cutoffs. Setting `FALSE` would instead create a band-stop (notch) filter that removes that range.
- `output = "Wave"`: returns the result as a `tuneR::Wave` object rather than a raw numeric vector, which preserves the sample-rate metadata needed downstream.

**Why 30–70 kHz?** North American bat echolocation calls typically span this range (big brown bats call around 25–50 kHz; little brown bats around 40–80 kHz; this range captures the core activity zone). By filtering to this band *before* computing RMS, you measure only the acoustic energy that is actually echolocation, not wind noise, insect sounds, or electrical interference, which typically live outside this range.

---

### Step 6 — Segment Count Calculation (Lines 101–102)

```r
num_segments <- floor(seewave::duration(wav) / segmentDuration)
```

`seewave::duration(wav)` returns the total length of the filtered `.WAV` in seconds (e.g., 600 seconds for a 10-minute AudioMoth file). Dividing by `segmentDuration` (1 second) and taking `floor()` gives the number of complete, non-overlapping windows that fit in the recording. `floor()` is critical — if a file is 599.8 seconds long, you get 599 complete 1-second segments, not 600 partial ones. The `seewave::` namespace prefix is explicitly used to avoid a conflict with `lubridate::duration()`, which is also loaded and has a completely different meaning (it creates time period objects, not scalar seconds).

---

### Step 7 — Preallocated Results Vector (Line 106)

```r
rmsenergy <- numeric(num_segments)
```

`numeric(num_segments)` allocates a zero-filled numeric vector of exactly the length needed before the inner loop begins. This is a significant performance optimization. The naive alternative — starting with `rmsenergy <- c()` and appending inside the loop — causes R to copy the entire vector into a new memory allocation on every iteration, resulting in O(n²) memory operations. For a 10-minute file at 1-second resolution, that's 600 iterations. For large datasets with hundreds of files, the difference between preallocating and growing-by-append can be many minutes of wasted computation.

---

### Step 8 — The Inner Loop: RMS Per Segment (Lines 109–133)

```r
for (j in 1:num_segments) {
  start_time <- (j - 1) * segmentDuration
  end_time   <- j * segmentDuration
  segment <- wav[round(start_time * samplingRate):round(end_time * samplingRate)]
  MLV <- (segment@left) / 32768
  rms_energy <- rms(MLV)
  rel_rmsenergy <- 20 * log(rms_energy / 1, base = 10)
  rel_rmsenergy_gainAdj <- rel_rmsenergy + gainOffset
  rmsenergy[j] <- rel_rmsenergy_gainAdj
}
```

This inner loop processes one time window at a time. Here is what each line does:

**Time window boundaries:**
```r
start_time <- (j - 1) * segmentDuration  # e.g. segment 3 starts at 2.0 seconds
end_time   <- j * segmentDuration         # e.g. segment 3 ends at 3.0 seconds
```
For `segmentDuration = 1`, this produces non-overlapping 1-second windows: [0,1), [1,2), [2,3), ...

**Converting time to sample indices:**
```r
segment <- wav[round(start_time * samplingRate):round(end_time * samplingRate)]
```
A `.WAV` file is a discrete sequence of amplitude samples in memory. `start_time * samplingRate` converts a time in seconds to the sample index where that time falls. At 192,000 Hz, second 1 starts at sample 192,000. `round()` handles the case where floating-point arithmetic produces something like 191999.9999, ensuring the index is always a valid integer. Subsetting `wav[start:end]` uses `tuneR`'s `Wave` subsetting operator, which returns a new `Wave` object covering only that window.

**Normalizing the amplitude:**
```r
MLV <- (segment@left) / 32768
```
`segment@left` accesses the left audio channel (the `@` is R's slot accessor for S4 objects). For standard 16-bit PCM `.WAV` files (which AudioMoth produces), each sample is an integer in the range –32,768 to +32,767, where –32,768 and +32,767 represent the maximum negative and positive deflections the recording hardware can represent. Dividing by 32,768 (which is 2^15) rescales this to the range [–1, 1], where ±1 represents the maximum possible signal amplitude. This normalization is necessary because the RMS formula and the dBFS scale both assume a reference amplitude of 1. `MLV` stands for "maximum linear value" in this context.

**Root Mean Square (RMS):**
```r
rms_energy <- rms(MLV)
```
`seewave::rms()` computes the root mean square of the amplitude vector:

```
RMS = sqrt( (1/N) * sum(x_i^2) )
```

RMS is the standard measure of signal power in acoustics because it reflects the *effective* amplitude — it is always positive, it weights large deflections more than small ones (due to squaring), and it is directly related to the acoustic energy carried by the wave. For a pure sine wave, RMS = peak_amplitude / sqrt(2). For complex waveforms like bat calls, it gives a meaningful single-number summary of the sound intensity in that time window.

**Converting to decibels relative to full scale (dBFS):**
```r
rel_rmsenergy <- 20 * log(rms_energy / 1, base = 10)
```
This is the standard dBFS formula: `20 * log10(measured / reference)`. The reference here is 1 (full scale, the maximum possible RMS value on the [–1, 1] scale). Since `rms_energy` is always less than 1 for any real recording (you never saturate the entire window), `log10(value < 1)` is always negative, so `rel_rmsenergy` will always be a negative number in dB. A value of 0 dBFS means the signal was at maximum possible amplitude; –60 dBFS means it was 60 dB quieter than maximum. The factor of 20 (not 10) is used because we are working with amplitude values, not power values directly — amplitude is the square root of power, and log rules mean the squaring adds the factor of 2, giving `10 * log10(amplitude^2) = 20 * log10(amplitude)`.

**Applying the gain offset:**
```r
rel_rmsenergy_gainAdj <- rel_rmsenergy + gainOffset  # gainOffset = 6.3 dB
```
The `gainOffset` corrects for the known difference between what the microphone records and the true acoustic pressure in the environment. Real microphone/amplifier chains have a gain that shifts the measured dB value away from the physical acoustic dB. If the recording system has a 6.3 dB gain, then a measured signal at –40 dBFS corresponds to a true acoustic level of –40 + 6.3 = –33.7 dBFS (relative to the microphone's reference). Adding the offset calibrates each measurement to the true acoustic level. The exact value (6.3 dB) comes from the hardware specification of the recording setup and is set in `config.yaml`.

**Storing the result:**
```r
rmsenergy[j] <- rel_rmsenergy_gainAdj
```
The gain-adjusted dBFS value for this 1-second window is stored in the preallocated vector at position `j`.

---

### Step 9 — Write Output and Update Progress (Lines 135–140)

```r
write.csv(rmsenergy, out_file)
message(paste0("Output saved to ", outputDir))
setTxtProgressBar(pb, f)
```

The completed `rmsenergy` vector (one dBFS value per 1-second segment) is written as a CSV. `write.csv()` by default adds a row-number column (`""` header) and wraps values in quotes. The file is written to `outputDir/{short_name}_RMSPower_1Second.csv`. After writing, the progress bar is updated to position `f` (the current file index).

---

## `BatFunctions.R` — `calcTotalRMSE()`

**File:** [`code/BatFunctions.R`](code/BatFunctions.R), Lines 153–218

This function takes a directory of adjusted RMS CSV files (all from the same date) and collapses them into a single per-date summary with total raw and adjusted RMS energy values.

---

### Function Signature (Line 153)

```r
calcTotalRMSE <- function(dataDirs, date)
```

- `dataDirs`: path to a directory containing CSV files for one particular date (e.g. `RMS_Power/test1.RMS_Power/20250529/`)
- `date`: a string in `YYYYMMDD` format (e.g. `"20250529"`), used for date column creation

---

### File Loop and Validation (Lines 165–208)

```r
files <- list.files(dataDirs, full.names = TRUE)

for (j in files) {
  x <- read.csv(j, header = TRUE)

  if (nrow(x) == 0) {
    message(paste(j, " has 0 rows."))
    next()
  }

  neededCols1 <- c("rmsEnergy")
  if (!neededCols1 %in% colnames(x)) {
    stop("rmsEnergy missing in data")
  }

  neededCols2 <- c("AdjustedValue")
  if (!neededCols2 %in% colnames(x)) {
    stop("AdjustedValue missing in data")
  }
```

Each CSV is loaded and validated for the presence of both required columns (`rmsEnergy` and `AdjustedValue`). Empty files are skipped with `next()` rather than causing an error, because an AudioMoth might produce a recording that was too quiet for any non-NA values to survive the earlier filtering step. Missing columns, however, indicate a structural problem (a bug or misprocessed file) and use `stop()` to abort with a clear message.

---

### Date Parsing and Julian Date (Lines 194–201)

```r
date <- as.character(date)
parts <- strsplit(date, "")[[1]]
year  <- paste(parts[1:4], collapse = "")
month <- paste(parts[5:6], collapse = "")
day   <- paste(parts[7:8], collapse = "")
formatDate <- paste(year, month, day, sep = "-")
x$date   <- formatDate
x$Julian <- lubridate::yday(formatDate)
```

The `date` parameter arrives as `"20250529"` (YYYYMMDD). This block manually splits it into characters and reconstructs it as `"2025-05-29"` (YYYY-MM-DD), which is a standard ISO 8601 format that `lubridate::yday()` can parse. `lubridate::yday()` returns the Julian day-of-year (1–365/366), which is essential for time-series analysis of seasonal bat activity patterns where you want to compare across years without calendar date confusion. Both the formatted date string and the Julian day are added as new columns to the dataframe.

---

### Binding and Totals (Lines 210–216)

```r
fullResults <- do.call(rbind, dataList)
fullResults$total_raw_rmse <- sum(fullResults$rmsEnergy)
fullResults$total_adj_rmse <- sum(fullResults$AdjustedValue)
return(fullResults)
```

`do.call(rbind, dataList)` is the idiomatic R way to row-bind a list of dataframes. It is equivalent to `rbind(dataList[[1]], dataList[[2]], ...)` but works regardless of list length. The result is a single long dataframe where each row is one second of audio from one file. Two scalar summary columns are added: `total_raw_rmse` (the sum of all `rmsEnergy` values across the entire date) and `total_adj_rmse` (the sum of all `AdjustedValue` values). Since these scalars are assigned to a column, every row in `fullResults` will have the same value for these columns — they represent the date-level totals, replicated across all rows. This means you can extract the total for a date from any single row, or use `unique()` to get it cleanly.

---

## `01_calcRMS_Power.R` — The Driver Script

**File:** [`code/01_calcRMS_Power.R`](code/01_calcRMS_Power.R)

This is the entry point called by Snakemake via `Rscript`. It does not contain signal processing logic — it handles argument parsing, orchestrates the calls to `BatFunctions.R`, and implements the two post-processing phases (file reorganization and collation).

---

### Library Loading and Sourcing (Lines 1–6)

```r
library(seewave)
library(lubridate)
library(tuneR)
library(tools)

source("code/BatFunctions.R")
```

The four libraries provide:
- **`seewave`**: `bwfilter()` and `rms()` — the core acoustic signal processing tools.
- **`lubridate`**: `yday()` — Julian date calculation.
- **`tuneR`**: `readWave()` — reading binary `.WAV` files into R objects.
- **`tools`**: `file_path_sans_ext()` — stripping file extensions from paths.

`source("code/BatFunctions.R")` executes the functions file in the current session's environment, making `rmsPower()` and `calcTotalRMSE()` available as if they were defined in this file. The path `"code/BatFunctions.R"` is relative to the Snakemake working directory (the root of the SnakeBat repo), not relative to the script file itself — Snakemake always runs jobs from the project root.

---

### Command-Line Argument Parsing (Lines 8–24)

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

`commandArgs(trailingOnly = TRUE)` returns only the arguments passed after the script name on the command line. When Snakemake calls `Rscript code/01_calcRMS_Power.R arg1 arg2 ...`, this vector contains exactly those 8 values.

> **Note:** The validation condition `length(args) < 8 | length(args) > 7` is a tautology — for any integer n, either n < 8 or n > 7 is always true (when n = 8: `FALSE | TRUE = TRUE`). The intended condition is most likely `length(args) != 8`. In practice this means the `stop()` line is unreachable under any argument count, and the script will simply fail later with an `out-of-bounds` subscript error if too few arguments are passed. This is a known bug.

Arguments 2, 4, 5, 6, and 7 are cast to `numeric` because `commandArgs()` returns everything as character strings — mathematical operations on them would silently fail otherwise.

---

### Directory Check and Logging (Lines 27–46)

```r
message("--------------------------------------------------")
message("Checking that dataDir exists...")
if (!dir.exists(dataDir)) {
    stop(paste(dataDir, "Does not exist or is empty!\n"))
} else {
    message(paste(dataDir, "exists!\n"))
}

message("Starting RMS power calculation with the following arguments:")
message(paste("\tdataDir:", dataDir))
# ... etc for all 8 arguments
```

This section redundantly validates `dataDir` (the function also checks, but checking here gives a cleaner error before entering R's function call stack). All parameters are logged via `message()`, which goes to `stderr` and therefore to the Snakemake log file (`logs/{sample}.log`). This means when you look at a log file, you can see exactly what parameters were used for that sample run, which is essential for debugging and reproducibility.

---

### Phase 1 — Calling `rmsPower()` (Lines 49–56)

```r
rmsPower(dataDir        = dataDir,
         segmentDuration = segmentDuration,
         fileType        = fileType,
         samplingRate    = samplingRate,
         gainOffset      = gainOffset,
         bwFilterFrom    = bwFilterFrom,
         bwFilterTo      = bwFilterTo,
         outputDir       = outputDir)
```

All 8 command-line arguments are forwarded by name to `rmsPower()`. After this call returns, `outputDir` (e.g., `RMS_Power/test1.RMS_Power/`) contains one flat CSV per `.WAV` file, each named `{stem}_RMSPower_1Second.csv`.

---

### Phase 2 — File Reorganization by Date (Lines 63–88)

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

This block reorganizes the flat CSVs from Phase 1 into date-named subdirectories. Here is each operation explained:

**Date extraction from filename:**
```r
date <- sub(".*_(\\d{8})_.*", "\\1", fname)
```
The regex `.*_(\\d{8})_.*` matches AudioMoth filenames which follow the pattern `DEVICEID_YYYYMMDD_HHMMSS.WAV`. The capture group `(\\d{8})` captures exactly 8 consecutive digits (the date). `sub()` replaces the entire filename with just that captured group, giving e.g. `"20250529"`. This date string is used to create a subdirectory like `RMS_Power/test1.RMS_Power/20250529/`.

**Column cleanup:**
The CSV written by `write.csv(rmsenergy, out_file)` in Phase 1 has an auto-generated row-number column with no header name (which R reads back as `"X"`). The code normalizes this by explicitly naming the two columns `c("X", "rmsEnergy")`, then dropping the index column `X`. The `X.1` guard handles cases where `write.csv` was called on a dataframe that already had row names, producing two index columns.

**`AdjustedValue` computation:**
```r
curFile$AdjustedValue <- curFile$rmsEnergy + abs(min(curFile$rmsEnergy))
```
Because all dBFS values are negative (with 0 dBFS being the theoretical maximum), `rmsEnergy` values are typically in the range –90 to –20. The minimum value in the file represents the quietest 1-second window. Adding `abs(min(rmsEnergy))` shifts the entire column up so that the quietest window maps to 0 and all other values are positive. This "zero-anchored" adjusted value is more intuitive for visualization (bar charts, heatmaps) and for summing into daily totals, since negative dB values would partially cancel each other and produce a total that is smaller in magnitude than many individual observations.

**Parallel execution:**
```r
nCores <- min(4, detectCores())
mclapply(files, ..., mc.cores = nCores)
```
`parallel::mclapply()` is a drop-in parallel replacement for `lapply()` using `fork()`-based multiprocessing. `min(4, detectCores())` caps the parallelism at 4 to avoid overwhelming the system on machines with many cores. Each CSV is reorganized independently, so there are no data dependencies between files, making this embarrassingly parallel.

---

### Phase 2 Cleanup (Lines 90–92)

```r
csv_files <- list.files(outputDir, pattern = "\\.csv$", full.names = TRUE)
file.remove(csv_files)
```

After all flat CSVs have been moved into date subdirectories and the adjusted files written there, the original flat files are deleted from the top level of `outputDir`. This prevents double-counting during collation and keeps the output directory tidy.

---

### Phase 3 — Collation into Daily Totals (Lines 99–124)

```r
subdirs <- list.dirs(outputDir, recursive = FALSE, full.names = TRUE)
dates <- basename(subdirs)
names(subdirs) <- dates
names(dates) <- dates

opDir <- "Total_RMSE/"
if (!dir.exists(opDir)) dir.create(opDir)
sample <- basename(outputDir)
resultsPath <- paste0(opDir, sample, "/")
if (!dir.exists(resultsPath)) dir.create(resultsPath)

mclapply(names(subdirs), function(dateName) {
    folder <- subdirs[dateName]
    total  <- calcTotalRMSE(folder, dateName)
    write.csv(total, file = paste0(resultsPath, dateName, "_total_RMSE.csv"))
}, mc.cores = nCores)
```

`list.dirs(outputDir, recursive = FALSE)` returns the date subdirectories created in Phase 2 (e.g. `RMS_Power/test1.RMS_Power/20250529/`). `basename()` on each gives the date string (e.g. `"20250529"`). A named vector `subdirs` is built where the names are dates and the values are full paths, allowing the `mclapply` lambda to look up the path from the date name.

`basename(outputDir)` extracts the sample name from the output path. For `outputDir = "RMS_Power/test1.RMS_Power"`, `basename` returns `"test1.RMS_Power"`. This becomes the name of the sample's subdirectory within `Total_RMSE/`.

For each date, `calcTotalRMSE()` is called with the date subdirectory and the date string. It returns a long dataframe with one row per second of audio, annotated with date and Julian day columns and two summary total columns. This is written to `Total_RMSE/test1.RMS_Power/20250529_total_RMSE.csv`.

---

# Part 2 — Snakemake Workflow

Snakemake is a Python-based workflow management system. Its core idea is **rule-based dependency resolution**: you declare what you want (outputs) and how to make it (rules), and Snakemake figures out which rules need to run, in what order, and which can run in parallel.

---

## `config.yaml`

**File:** [`config.yaml`](config.yaml)

```yaml
folders: "folders.csv"
segmentDuration: "1"
fileType: ".WAV"
samplingRate: 192000
gainOffset: 6.3
bwFilterFrom: "30000"
bwFilterTo: "70000"
```

This is the single user-facing control panel for the pipeline. Every value here is read by the `Snakefile` into a Python dictionary called `config`, and individual values are passed as parameters to the R script. Separating parameters into a YAML file means:

1. Users never touch the `Snakefile` itself (reducing the risk of introducing syntax errors into the workflow logic).
2. The config file can be version-controlled independently, giving a clear record of what parameters were used for each analysis.
3. Different projects can reuse the same `Snakefile` with different config files.

Note that `segmentDuration`, `bwFilterFrom`, and `bwFilterTo` are quoted strings in the YAML (`"1"`, `"30000"`, `"70000"`) while `samplingRate` and `gainOffset` are bare numbers. YAML allows both; Snakemake passes all config values to the shell command as their string representation, so the distinction matters only if you were using these values in Python within the Snakefile itself (you are not here).

---

## `folders.csv`

**File:** [`folders.csv`](folders.csv)

```
sample,folder
test1,/Users/mike/Desktop/SCRIPTS/Pipelines//SnakeBat/test_data/PAB_BB_052925_AM68_ML_LGE
test2,/Users/mike/Desktop/SCRIPTS/Pipelines//SnakeBat/test_data/PAB_BB_052925_AM78_M_LGE
```

This two-column CSV defines the unit of work. Each row is one "sample" — one recording session, one AudioMoth unit, one night's worth of data, etc. The `sample` column is the short identifier used to name output files and directories. The `folder` column is the absolute path to the raw `.WAV` files for that sample.

By using a CSV rather than hardcoding paths in the `Snakefile`, you can add or remove samples just by editing a spreadsheet, without touching any workflow logic. The double slash in the paths (`//`) is harmless — most operating systems treat `//` identically to `/`.

---

## `env_config/snakeBat.yaml`

**File:** [`env_config/snakeBat.yaml`](env_config/snakeBat.yaml)

```yaml
name: snakeBat
channels:
  - conda-forge
  - bioconda
  - defaults
dependencies:
  - python=3.10
  - snakemake
  - pandas
  - numpy<2
  - r-base
  - r-dplyr
  - r-ggplot2
  - r-data.table
  - r-foreach
  - r-doparallel
  - r-lubridate
```

This conda environment file pins the complete software environment for the pipeline. Snakemake's `conda:` directive in a rule (see below) means Snakemake will activate this environment before running that rule's shell command. This provides **environment isolation**: even if the user's base system has different versions of R or Python, the rule always runs with exactly the packages listed here.

`numpy<2` is a version pin that prevents NumPy 2.x, which introduced breaking API changes incompatible with some bioconda packages, from being installed. Note that `tuneR` and `seewave` are not listed here — the README instructs users to install them manually via `R install.packages()` because they are not available as standard conda packages. This is a known limitation of the environment specification.

---

## `Snakefile`

**File:** [`Snakefile`](Snakefile)

The `Snakefile` is a Python file with special Snakemake syntax mixed in. The top portion is pure Python; each `rule` block is Snakemake DSL.

---

### Header — Imports and Config (Lines 1–12)

```python
import pandas as pd

configfile: "config.yaml"

sample_file = config["folders"]
samples_df  = pd.read_csv(sample_file).set_index("sample", drop=False)
sample_list = list(samples_df['sample'])
```

`configfile: "config.yaml"` is a Snakemake directive (not standard Python). It tells Snakemake to parse `config.yaml` using PyYAML and make it available as the global dictionary `config`. After this line, `config["segmentDuration"]` returns `"1"`, `config["samplingRate"]` returns `192000`, etc.

`pd.read_csv(sample_file)` reads `folders.csv` into a pandas DataFrame. `.set_index("sample", drop=False)` sets the `sample` column as the DataFrame's row index while keeping the column — this enables `.loc[sample_name, "folder"]` lookups by sample name later in the rule's `params` block. `list(samples_df['sample'])` extracts the list of all sample names: `["test1", "test2"]`.

---

### `rule all` — The Terminal Rule (Lines 19–25)

```python
rule all:
    input:
        expand("RMS_Power/{sample}.RMS_Power", sample = sample_list),
    output: "done.txt"
    shell: """
    touch done.txt
    """
```

`rule all` is a Snakemake convention — it is the first rule in the file and therefore the default target when you run `snakemake` without specifying a target rule. Snakemake builds backwards from the inputs of `rule all` to determine what needs to be run.

`expand("RMS_Power/{sample}.RMS_Power", sample = sample_list)` is a Snakemake function that generates all combinations of the path template with the values in `sample_list`. With `sample_list = ["test1", "test2"]`, this produces:

```python
["RMS_Power/test1.RMS_Power", "RMS_Power/test2.RMS_Power"]
```

Snakemake sees these as required inputs. Since they don't exist yet, it searches for rules that produce them. It finds `rule calc_RMS_Power` (see below) which produces `directory("RMS_Power/{sample}.RMS_Power")`. Snakemake instantiates this rule once for each sample, substituting `{sample}` with `"test1"` and `"test2"` respectively.

After all inputs exist, `rule all` runs `touch done.txt`, creating an empty sentinel file that signals pipeline completion. The `done.txt` file has no scientific meaning — it is purely a Snakemake bookkeeping artifact.

---

### `rule calc_RMS_Power` — The Processing Rule (Lines 28–60)

```python
rule calc_RMS_Power:
    output:
        rms_power = directory("RMS_Power/{sample}.RMS_Power")
    params:
        sample       = lambda wildcards: wildcards.sample,
        folder       = lambda wildcards: samples_df.loc[wildcards.sample, "folder"],
        rms_code     = "code/01_calcRMS_Power.R",
        segDur       = config["segmentDuration"],
        fileType     = config["fileType"],
        samplingRate = config["samplingRate"],
        gainOffset   = config["gainOffset"],
        bwFilterFrom = config["bwFilterFrom"],
        bwFilterTo   = config["bwFilterTo"]
    conda:
        "env_config/snakeBat.yaml",
    log:
        "logs/{sample}.log"
    shell: """
        RScript {params.rms_code} \
            {params.folder} \
            {params.segDur} \
            {params.fileType} \
            {params.samplingRate} \
            {params.gainOffset} \
            {params.bwFilterFrom} \
            {params.bwFilterTo} \
            {output.rms_power} \
            &> {log}
    """
```

#### `output` block

```python
output:
    rms_power = directory("RMS_Power/{sample}.RMS_Power")
```

`{sample}` is a **wildcard** — Snakemake fills it in based on which sample is being processed. `directory()` tells Snakemake that the output is a directory, not a file. This is important because Snakemake normally checks for the existence of output files to determine if a rule needs to run. Wrapping in `directory()` changes this check to verify the directory's existence instead.

The output path pattern `RMS_Power/{sample}.RMS_Power` matches the `expand()` in `rule all`, which is how Snakemake connects the two rules. When Snakemake needs `RMS_Power/test1.RMS_Power`, it matches `{sample}` = `"test1"` and runs `calc_RMS_Power` with that substitution.

#### `params` block

```python
params:
    sample       = lambda wildcards: wildcards.sample,
    folder       = lambda wildcards: samples_df.loc[wildcards.sample, "folder"],
    rms_code     = "code/01_calcRMS_Power.R",
    segDur       = config["segmentDuration"],
    ...
```

The `params` block is for values that are needed in the `shell` command but are not direct file inputs or outputs. Static values (like `rms_code` and config values) are assigned directly. Dynamic values that depend on the current wildcard are assigned via **lambda functions**.

`lambda wildcards: wildcards.sample` is a Python anonymous function that receives the current wildcards object and returns `wildcards.sample` (e.g., `"test1"`). This is how you access the wildcard value inside a `params` block.

`lambda wildcards: samples_df.loc[wildcards.sample, "folder"]` looks up the absolute path to the raw data folder in the pandas DataFrame using the current sample name as the row index. For `sample = "test1"`, this returns `"/Users/mike/Desktop/SCRIPTS/Pipelines//SnakeBat/test_data/PAB_BB_052925_AM68_ML_LGE"`. This is the value passed as `dataDir` to the R script.

#### `conda` block

```python
conda:
    "env_config/snakeBat.yaml"
```

Before executing the `shell` command, Snakemake activates (or creates if absent) the conda environment described in `snakeBat.yaml`. This guarantees the rule runs with the correct Python, R, and package versions regardless of what is installed in the user's base environment.

#### `log` block

```python
log:
    "logs/{sample}.log"
```

The log path pattern resolves to `logs/test1.log` or `logs/test2.log`. The `{sample}` wildcard is the same one used in `output`. Log files in Snakemake are special: they are not deleted if a rule fails (unlike output files, which Snakemake removes on failure to prevent incomplete artifacts from being mistaken for successful outputs).

#### `shell` block

```python
shell: """
    RScript {params.rms_code} \
        {params.folder} \
        {params.segDur} \
        {params.fileType} \
        {params.samplingRate} \
        {params.gainOffset} \
        {params.bwFilterFrom} \
        {params.bwFilterTo} \
        {output.rms_power} \
        &> {log}
"""
```

Snakemake resolves all `{...}` placeholders to their actual values and then passes the resulting string to `bash -c "..."`. For `sample = "test1"`, this expands to something like:

```bash
RScript code/01_calcRMS_Power.R \
    /path/to/PAB_BB_052925_AM68_ML_LGE \
    1 \
    .WAV \
    192000 \
    6.3 \
    30000 \
    70000 \
    RMS_Power/test1.RMS_Power \
    &> logs/test1.log
```

`&>` redirects both `stdout` and `stderr` to the log file. Since R's `message()` writes to `stderr`, all of the progress messages from `01_calcRMS_Power.R` and from `BatFunctions.R` will appear in `logs/test1.log`. The trailing `\` on each line is a bash line-continuation character, allowing the long command to span multiple lines for readability.

> **Note:** There is a subtle bug on line 54 of the Snakefile. The `gainOffset` parameter line reads:
> ```
>     {params.gainOffset} \
> ```
> The backslash continuation character appears after `\ ` with a trailing space, which in bash makes the backslash a literal character rather than a line continuation, potentially causing a shell syntax error. This may need to be fixed to ensure the command parses correctly across all shell environments.

---

## How the Rules Connect

Snakemake builds a **Directed Acyclic Graph (DAG)** of jobs to run. For this pipeline with 2 samples, the DAG is:

```
calc_RMS_Power(test1) ──┐
                         ├──► rule all ──► done.txt
calc_RMS_Power(test2) ──┘
```

The two `calc_RMS_Power` jobs have no dependency on each other, so with `--cores 2` they run in parallel. `rule all` cannot begin until both produce their output directories.

Snakemake determines this structure as follows:

1. The default target is `rule all`.
2. `rule all` needs `RMS_Power/test1.RMS_Power` and `RMS_Power/test2.RMS_Power` as inputs.
3. Neither exists on disk.
4. Snakemake scans all rules for ones whose `output` patterns match these paths.
5. `rule calc_RMS_Power` matches with `{sample}` = `"test1"` and `{sample}` = `"test2"`.
6. These rules have no `input:` block, so they have no further dependencies — they can run immediately.
7. Snakemake schedules both to run in parallel (up to the `--cores` limit).

---

## Execution Flow End-to-End

Here is the complete sequence of events from `snakemake --cores 2` to completion:

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
│   └── calc_RMS_Power jobs have no inputs → schedule both immediately
│
├── Run calc_RMS_Power(test1)  [parallel with test2]
│   ├── Activate snakeBat conda environment
│   ├── Execute: Rscript code/01_calcRMS_Power.R [8 args] &> logs/test1.log
│   │
│   │   Inside 01_calcRMS_Power.R:
│   │   ├── library() loads, source("code/BatFunctions.R")
│   │   ├── Parse 8 command-line args
│   │   ├── Validate dataDir
│   │   ├── Call rmsPower()
│   │   │   ├── List .WAV files recursively
│   │   │   ├── For each .WAV:
│   │   │   │   ├── Check skip (idempotency)
│   │   │   │   ├── readWave() → raw.wav
│   │   │   │   ├── bwfilter(30–70 kHz) → wav
│   │   │   │   ├── For each 1-second segment:
│   │   │   │   │   ├── Slice samples by index
│   │   │   │   │   ├── Normalize to [-1,1] (÷ 32768)
│   │   │   │   │   ├── rms() → RMS amplitude
│   │   │   │   │   ├── 20*log10(rms/1) → dBFS
│   │   │   │   │   └── + gainOffset (6.3 dB) → adjusted dBFS
│   │   │   │   └── write.csv(rmsenergy, outfile)
│   │   │   └── [returns to 01_calcRMS_Power.R]
│   │   ├── mclapply: reorganize CSVs into date subdirectories
│   │   │   ├── Extract date from filename (regex)
│   │   │   ├── Rename columns, omit NAs
│   │   │   ├── Compute AdjustedValue (shift to zero-minimum)
│   │   │   └── Write to RMS_Power/test1.RMS_Power/YYYYMMDD/
│   │   ├── Remove flat CSVs from RMS_Power/test1.RMS_Power/
│   │   └── mclapply: calcTotalRMSE() per date subdirectory
│   │       ├── Read all CSVs for this date
│   │       ├── Add date and Julian day columns
│   │       ├── rbind all into one dataframe
│   │       ├── Compute total_raw_rmse and total_adj_rmse
│   │       └── Write to Total_RMSE/test1.RMS_Power/YYYYMMDD_total_RMSE.csv
│   │
│   └── Directory RMS_Power/test1.RMS_Power/ now exists → job complete
│
├── Run calc_RMS_Power(test2)  [same flow as above]
│
└── Both outputs exist → run rule all
    └── touch done.txt
```

---

# Output Directory Structure

After a successful run with 2 samples spanning 1 date each:

```
SnakeBat/
├── done.txt                              ← sentinel file from rule all
├── logs/
│   ├── test1.log                         ← full R console output for test1
│   └── test2.log                         ← full R console output for test2
├── RMS_Power/
│   ├── test1.RMS_Power/
│   │   └── 20250529/
│   │       ├── PAB_BB_052925_AM68_000000_RMSPower_1Second.csv
│   │       ├── PAB_BB_052925_AM68_001000_RMSPower_1Second.csv
│   │       └── ...                       ← one file per original .WAV
│   └── test2.RMS_Power/
│       └── 20250529/
│           └── ...
└── Total_RMSE/
    ├── test1.RMS_Power/
    │   └── 20250529_total_RMSE.csv       ← all seconds for this date, with totals
    └── test2.RMS_Power/
        └── 20250529_total_RMSE.csv
```

**Per-file RMS CSV** (in `RMS_Power/`): One row per second of audio. Columns: `rmsEnergy` (dBFS + gain offset), `AdjustedValue` (shifted to zero minimum).

**Total RMSE CSV** (in `Total_RMSE/`): One row per second of audio across ALL files for that date. Additional columns: `date` (YYYY-MM-DD), `Julian` (day of year), `total_raw_rmse` (scalar repeated on every row), `total_adj_rmse` (scalar repeated on every row).
