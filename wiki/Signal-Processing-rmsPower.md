# Signal Processing — `rmsPower()`

[← Repository Overview](Repository-Overview) | [Next: `calcTotalRMSE()` →](Signal-Processing-calcTotalRMSE)

**File:** `code/BatFunctions.R`, Lines 19–149

`rmsPower()` is the acoustic signal processing engine. It accepts a directory of `.WAV` files and, for each file, applies a Butterworth bandpass filter and then computes root mean square (RMS) energy in decibels for fixed-duration time segments. It never runs on its own — it is always `source()`'d by the driver script and called from `01_calcRMS_Power.R`.

---

## Function Signature

```r
rmsPower <- function(dataDir,         # path to folder containing .WAV files
                     segmentDuration,  # length of each time window in seconds
                     fileType,         # file extension to match (e.g. ".WAV")
                     samplingRate,     # audio sampling rate in Hz (e.g. 192000)
                     gainOffset,       # microphone calibration correction in dB
                     bwFilterFrom,     # lower frequency cutoff of bandpass filter in Hz
                     bwFilterTo,       # upper frequency cutoff of bandpass filter in Hz
                     outputDir)        # where to write output CSV files
```

Every argument is user-defined via `config.yaml`. Nothing is hardcoded, making the function reusable across different microphone setups, bat species frequency ranges, and recording hardware.

---

## Step 1 — Directory Validation (Lines 27–39)

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

Before touching any audio data, the function validates that `dataDir` exists and creates `outputDir` if it does not. Failing here with a clear message prevents cryptic errors from surfacing deep inside the loop, where R would crash with a file-not-found error rather than a meaningful one.

---

## Step 2 — File Discovery (Lines 47–51)

```r
dataFiles <- list.files(dataDir,
                        pattern = fileType,
                        full.names = TRUE,
                        recursive = TRUE)
```

`list.files()` with `recursive = TRUE` walks the entire directory tree under `dataDir` and returns every file whose name contains `fileType` (e.g., `".WAV"`). `full.names = TRUE` returns complete absolute paths rather than bare filenames, which is required because `tuneR::readWave()` needs a resolvable path. The recursive walk is important — AudioMoth recorders often organize output into date-named subdirectories, and a flat `list.files()` would miss those nested files.

---

## Step 3 — Progress Bar Initialization (Lines 53–55)

```r
numFiles <- length(dataFiles)
pb <- txtProgressBar(min = 0, max = numFiles, style = 3)
```

`txtProgressBar()` with `style = 3` renders a `[=====>   ] 45%` percentage bar in the terminal. Processing hundreds of 10-minute `.WAV` files at 192 kHz can take hours — without this feedback the user has no way to know whether the job is progressing or hung. The bar is updated at the end of every iteration via `setTxtProgressBar(pb, f)`.

---

## Step 4 — Outer Loop: Iterating Over Files (Lines 58–141)

```r
for (f in seq_along(dataFiles)) {
    i <- dataFiles[f]
```

`seq_along(dataFiles)` produces `c(1, 2, ..., numFiles)`. The loop variable `f` is the numeric index (needed for the progress bar update) and `i` is the actual file path (used for all file operations).

### Skip Check — Idempotency (Lines 66–72)

```r
short_name <- tools::file_path_sans_ext(basename(i))
out_file <- file.path(outputDir, paste0(short_name, "_RMSPower_1Second.csv"))
if (file.exists(out_file)) {
  message(paste("File already exists. Skipping:", out_file))
  setTxtProgressBar(pb, f)
  next
}
```

`tools::file_path_sans_ext(basename(i))` strips the directory path and `.WAV` extension, leaving just the filename stem (e.g., `PAB_20250529_000000`). The expected output filename is constructed predictably from this stem. If the output CSV already exists, the file is skipped — this makes the function **idempotent**: if a run is interrupted and restarted, it resumes from where it left off without reprocessing finished files. The progress bar is still updated before `next` to keep the displayed percentage accurate.

### Corrupt File Handling — `tryCatch` (Lines 75–85)

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

`tuneR::readWave()` parses the binary RIFF/WAV format. Corrupted files — for example, incomplete recordings from a battery-dying AudioMoth — cause `readWave()` to throw a hard error. Without `tryCatch`, this would crash the entire loop and lose all progress for that sample. The `tryCatch` block intercepts any error, issues a `warning()` (which goes to the log but does not abort), returns `NULL`, and allows the `is.null()` check to trigger `next`, continuing to the next file. This makes the pipeline robust to real-world field recording imperfections.

---

## Step 5 — Butterworth Bandpass Filter (Lines 93–99)

```r
wav <- bwfilter(raw.wav,
                f = samplingRate,
                from = bwFilterFrom,
                to = bwFilterTo,
                bandpass = TRUE,
                output = "Wave")
```

`seewave::bwfilter()` implements a Butterworth infinite impulse response (IIR) filter. A Butterworth filter is **maximally flat in the passband** — it does not introduce ripple in the frequencies it retains, unlike Chebyshev or elliptic designs.

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `f` | 192,000 Hz | Sample rate; used to normalize frequency cutoffs |
| `from` | 30,000 Hz | Lower passband edge — energy below 30 kHz is attenuated |
| `to` | 70,000 Hz | Upper passband edge — energy above 70 kHz is attenuated |
| `bandpass` | `TRUE` | Retain frequencies *between* cutoffs (`FALSE` = band-stop/notch) |
| `output` | `"Wave"` | Return a `tuneR::Wave` object preserving sample-rate metadata |

**Why 30–70 kHz?** North American bat echolocation calls typically fall in this range: big brown bats call around 25–50 kHz; little brown bats around 40–80 kHz. Filtering to this band *before* computing RMS ensures you measure only echolocation energy, not wind noise, insect sounds, or electrical interference (which live outside this range).

---

## Step 6 — Segment Count Calculation (Lines 101–102)

```r
num_segments <- floor(seewave::duration(wav) / segmentDuration)
```

`seewave::duration(wav)` returns the total recording length in seconds (e.g., 600 s for a 10-minute AudioMoth file). Dividing by `segmentDuration` (1 s) and taking `floor()` gives the number of complete, non-overlapping windows. `floor()` is critical — a 599.8-second file produces 599 complete segments, not 600 partial ones.

The `seewave::` namespace prefix is **required** to avoid a silent name collision with `lubridate::duration()`, which is also loaded and creates time-period objects rather than returning a scalar number of seconds.

---

## Step 7 — Preallocated Results Vector (Line 106)

```r
rmsenergy <- numeric(num_segments)
```

`numeric(num_segments)` allocates a zero-filled vector of exactly the needed length *before* the inner loop begins. The naive alternative — starting with `rmsenergy <- c()` and growing it inside the loop — causes R to copy the entire vector into a new memory allocation on every iteration (O(n²) memory operations). For a 10-minute file at 1-second resolution that is 600 copies. Preallocation eliminates this overhead entirely.

---

## Step 8 — Inner Loop: RMS Per Segment (Lines 109–133)

```r
for (j in 1:num_segments) {
  start_time <- (j - 1) * segmentDuration
  end_time   <- j * segmentDuration
  segment    <- wav[round(start_time * samplingRate):round(end_time * samplingRate)]
  MLV        <- (segment@left) / 32768
  rms_energy <- rms(MLV)
  rel_rmsenergy       <- 20 * log(rms_energy / 1, base = 10)
  rel_rmsenergy_gainAdj <- rel_rmsenergy + gainOffset
  rmsenergy[j] <- rel_rmsenergy_gainAdj
}
```

### Time Window Boundaries

```r
start_time <- (j - 1) * segmentDuration   # segment 3 → 2.0 s
end_time   <- j * segmentDuration          # segment 3 → 3.0 s
```

For `segmentDuration = 1`, this produces non-overlapping 1-second windows: [0, 1), [1, 2), [2, 3), ...

### Converting Time to Sample Indices

```r
segment <- wav[round(start_time * samplingRate):round(end_time * samplingRate)]
```

A `.WAV` file is a discrete sequence of amplitude samples. `start_time × samplingRate` converts a time in seconds to the sample index where that time falls. At 192,000 Hz, second 1 starts at sample 192,000. `round()` handles floating-point imprecision (e.g., 191999.9999 → 192000). Subsetting `wav[start:end]` uses `tuneR`'s `Wave` subsetting operator and returns a new `Wave` object covering only that window.

### Normalizing from 16-bit PCM to [–1, 1]

```r
MLV <- (segment@left) / 32768
```

`segment@left` accesses the left audio channel via R's S4 slot accessor `@`. AudioMoth records in 16-bit PCM, where each sample is an integer in [–32,768, +32,767]. Dividing by 32,768 (= 2^15) rescales to [–1, 1], where ±1 represents the hardware's maximum deflection. This normalization is required because the RMS formula and the dBFS scale both assume a reference amplitude of 1.

### Root Mean Square

```r
rms_energy <- rms(MLV)
```

`seewave::rms()` computes:

```
RMS = sqrt( (1/N) × Σ xᵢ² )
```

RMS is the standard acoustic power metric because it is always positive, weights large deflections more than small ones (due to squaring), and is directly related to the energy carried by the wave. For a pure sine wave, RMS = peak / √2. For complex bat echolocation calls, it gives a meaningful single-number summary of signal intensity in that window.

### Converting to dBFS

```r
rel_rmsenergy <- 20 * log(rms_energy / 1, base = 10)
```

This is the standard dBFS (decibels relative to full scale) formula:

```
dBFS = 20 × log₁₀(measured / reference)
```

The reference is 1 (the maximum possible RMS on the [–1, 1] scale). Since `rms_energy` is always less than 1 for any real recording, `log₁₀(value < 1)` is always negative — so all dBFS values are negative. 0 dBFS means maximum possible amplitude; –60 dBFS means 60 dB quieter than maximum.

The factor of **20** (not 10) is used because we are working with *amplitude*, not power directly. Amplitude is the square root of power, so: `10 × log₁₀(amplitude²) = 20 × log₁₀(amplitude)`.

### Applying the Gain Offset

```r
rel_rmsenergy_gainAdj <- rel_rmsenergy + gainOffset   # gainOffset = 6.3 dB
```

The `gainOffset` corrects for the known difference between what the microphone records and the true acoustic pressure in the environment. Every microphone/amplifier chain has a gain that shifts the measured dB value away from the physical acoustic pressure. If the recording system has a 6.3 dB gain, a signal measured at –40 dBFS corresponds to a true level of –40 + 6.3 = –33.7 dBFS. The exact value comes from the hardware specification and is set in `config.yaml`.

### Storing the Result

```r
rmsenergy[j] <- rel_rmsenergy_gainAdj
```

The gain-adjusted dBFS value for this segment is stored at position `j` in the preallocated vector.

---

## Step 9 — Write Output and Update Progress (Lines 135–140)

```r
write.csv(rmsenergy, out_file)
message(paste0("Output saved to ", outputDir))
setTxtProgressBar(pb, f)
```

The completed `rmsenergy` vector — one dBFS value per 1-second segment — is written to `outputDir/{stem}_RMSPower_1Second.csv`. `write.csv()` adds an auto-generated row-number column with no header (read back as `"X"`), which is cleaned up in the post-processing phase of the driver script. After writing, the progress bar advances to position `f`.

---

## Output Schema

Each CSV produced by `rmsPower()` has this structure before post-processing:

| Column | Type | Description |
|--------|------|-------------|
| *(row index)* | integer | Auto-generated by `write.csv()`, read back as `"X"` |
| `x` | numeric | Gain-adjusted RMS energy in dBFS for this 1-second segment |

After post-processing in the driver script, the column is renamed `rmsEnergy` and an `AdjustedValue` column is added. See [Driver Script](Driver-Script) for details.

---

*Next: [Signal Processing — `calcTotalRMSE()`](Signal-Processing-calcTotalRMSE)*
