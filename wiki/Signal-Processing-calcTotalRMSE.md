# Signal Processing — `calcTotalRMSE()`

[← `rmsPower()`](Signal-Processing-rmsPower) | [Next: Driver Script →](Driver-Script)

**File:** `code/BatFunctions.R`, Lines 153–218

`calcTotalRMSE()` takes a directory of adjusted RMS CSV files (all from the same date) and collapses them into a single per-date summary dataframe. It adds date and Julian day annotations and computes total raw and adjusted RMS energy across all files for that date.

This function is called from the Phase 3 section of `01_calcRMS_Power.R`, once per date subdirectory, in parallel.

---

## Function Signature

```r
calcTotalRMSE <- function(dataDirs, date)
```

| Argument | Type | Example | Description |
|----------|------|---------|-------------|
| `dataDirs` | string | `"RMS_Power/test1.RMS_Power/20250529/"` | Path to a directory of adjusted CSVs for one date |
| `date` | string | `"20250529"` | Date in YYYYMMDD format; used to create date and Julian columns |

---

## File Loop and Validation (Lines 165–208)

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

Each CSV file in the date directory is loaded and validated before being added to the collection.

**Empty file handling:** `if (nrow(x) == 0)` skips any file with zero rows using `next()` rather than aborting. An AudioMoth recording might produce a file where all amplitude values are NA (e.g., if the segment was pure silence below the noise floor and was entirely removed during the `na.omit()` step in the driver script). Skipping silently allows the rest of the date's files to still be processed.

**Column validation:** Both `rmsEnergy` and `AdjustedValue` must be present. Missing columns indicate a structural problem — either a bug upstream or a misprocessed file. These trigger `stop()`, which aborts the function with a clear error message rather than silently producing a wrong result.

---

## Date Parsing and Julian Date (Lines 194–201)

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

The `date` argument arrives as a compact string like `"20250529"` (YYYYMMDD). This block:

1. Splits it into individual characters: `c("2","0","2","5","0","5","2","9")`
2. Reassembles them as `"2025-05-29"` — ISO 8601 format (YYYY-MM-DD)
3. Assigns the formatted date string as a new `date` column on every row of `x`
4. Computes the **Julian day-of-year** via `lubridate::yday()` (1–365 or 1–366 in leap years)

The Julian day is critical for time-series analysis of seasonal bat activity. Comparing bat activity across multiple years is much simpler using Julian day (which runs 1–365 regardless of year) than using calendar dates (which would require aligning different year/month combinations). Both columns are added to `x` before it is appended to `dataList`.

---

## Building the List and Row-Binding (Lines 207–210)

```r
dataList[[j]] <- x
...
fullResults <- do.call(rbind, dataList)
```

Each validated, annotated dataframe `x` is stored in `dataList` keyed by its filename `j`. After the loop, `do.call(rbind, dataList)` row-binds all dataframes into one long result. This idiom is equivalent to:

```r
rbind(dataList[[1]], dataList[[2]], dataList[[3]], ...)
```

but works regardless of how many files are in the list. The result `fullResults` has one row per second of audio across all files in that date's directory.

---

## Computing Daily Totals (Lines 212–215)

```r
fullResults$total_raw_rmse <- sum(fullResults$rmsEnergy)
fullResults$total_adj_rmse <- sum(fullResults$AdjustedValue)
return(fullResults)
```

Two total columns are computed:

| Column | Formula | Meaning |
|--------|---------|---------|
| `total_raw_rmse` | `sum(rmsEnergy)` | Sum of all gain-adjusted dBFS values for this date |
| `total_adj_rmse` | `sum(AdjustedValue)` | Sum of all zero-anchored adjusted values for this date |

Because a scalar is assigned to an entire column, **every row in `fullResults` carries the same value** for these two columns. They represent the date-level totals, replicated across all per-second rows. To extract the total cleanly in downstream analysis, use `unique(fullResults$total_raw_rmse)` — or simply read it from any single row.

**Why sum `AdjustedValue` rather than `rmsEnergy`?** Raw dBFS values are negative (typically –90 to –20). Summing negative numbers produces a total that partially cancels itself — a quiet second at –80 dBFS partially undoes a loud second at –30 dBFS. The `AdjustedValue` column shifts all values so the minimum maps to 0 and all values are non-negative, which makes the sum monotonically grow with activity level and is more interpretable as a daily activity index.

---

## Return Value Schema

`calcTotalRMSE()` returns a dataframe with the following columns:

| Column | Type | Description |
|--------|------|-------------|
| `rmsEnergy` | numeric | Gain-adjusted RMS energy in dBFS (negative values) |
| `AdjustedValue` | numeric | `rmsEnergy` shifted so the minimum = 0 (non-negative) |
| `date` | character | Recording date as `"YYYY-MM-DD"` |
| `Julian` | integer | Day of year (1–365/366) |
| `total_raw_rmse` | numeric | Sum of all `rmsEnergy` values for this date (scalar, replicated) |
| `total_adj_rmse` | numeric | Sum of all `AdjustedValue` values for this date (scalar, replicated) |

This dataframe is written directly to `Total_RMSE/{sample}/{date}_total_RMSE.csv` by the driver script.

---

*Next: [Driver Script — `01_calcRMS_Power.R`](Driver-Script)*
