# Parameters

Every setting the pipeline exposes, what it does, and how to choose it.

All of these live in `config.yaml` except the sample list, which lives in `folders.csv`. These two files are the only ones you edit to run the pipeline on your own data.

---

## Quick reference

| Parameter | Our default | What it controls |
|-----------|-------------|------------------|
| `folders` | `"folders.csv"` | Which file lists the sites to process |
| `segmentDuration` | `"1"` | Seconds of audio per measurement |
| `fileType` | `".WAV"` | Which files to look for |
| `samplingRate` | `192000` | Recorder sampling rate, in Hz |
| `gainOffset` | `6.3` | Fixed dB correction for recorder gain — **set to `0` for none** |
| `bwFilterFrom` | `"30000"` | Bottom of the frequency band to keep, in Hz |
| `bwFilterTo` | `"70000"` | Top of the frequency band to keep, in Hz |

> **Save the file after editing.** An unsaved `config.yaml` is the single most common cause of a run that completes with the wrong settings, because nothing errors — you simply get results computed from the old values.

---

## `folders`

```yaml
folders: "folders.csv"
```

The name of the CSV listing which sites to process. Leave this as `"folders.csv"` unless you keep several sample sheets side by side — for example one per field season — in which case point it at the one you want:

```yaml
folders: "folders_2026_season.csv"
```

See [folders.csv](#folderscsv) below for the file's format.

---

## `segmentDuration`

```yaml
segmentDuration: "1"
```

How many seconds of audio go into each RMS measurement. `1` gives one loudness value per second of recording, which is what all the downstream summaries and plots assume.

A 10-minute recording produces 600 measurements at `1`, 60 at `10`, and 6000 at `0.1`.

**When to change it.** Longer segments smooth over short events and produce smaller files; shorter segments resolve individual passes better but multiply the output size and the runtime. If you change it, say so when reporting results — a "total nightly RMS" computed from 10-second segments is not comparable to one computed from 1-second segments.

Any audio left over at the end of a file, shorter than one full segment, is discarded rather than measured on a partial window.

---

## `fileType`

```yaml
fileType: ".WAV"
```

Which files to look for inside each folder listed in `folders.csv`. Anything not matching is ignored, so stray notes, spreadsheets and `.DS_Store` files are harmless.

This is matched as a pattern, and **it is case sensitive**. AudioMoth writes uppercase `.WAV`. If your recorder writes lowercase `.wav`, change this or the pipeline will report `ERROR: No files found matching pattern`.

Sub-folders are searched too, so a folder containing one directory per night works without flattening it first.

---

## `samplingRate`

```yaml
samplingRate: 192000
```

Your recorder's sampling rate in Hz. **This must match what the recorder was actually set to in the field.**

It is not read from the file — it is supplied by you and used both to run the band-pass filter and to cut the audio into segments. If it is wrong, the filter band is wrong and every number the pipeline produces is wrong, silently. Nothing will error.

192,000 Hz is the standard AudioMoth setting for bat work. The sampling rate must be at least twice the highest frequency you want to keep, so 192,000 Hz supports a `bwFilterTo` up to 96,000 Hz.

---

## `gainOffset`

```yaml
gainOffset: 6.3
```

A fixed correction in decibels, added to every measurement after the conversion to dBFS. It compensates for the gain setting on the recorder, so deployments recorded at different gains can be compared on the same scale.

> ### If you do not need a gain adjustment, set this to `0`.
>
> ```yaml
> gainOffset: 0
> ```
>
> Zero means "add nothing" and leaves the raw dBFS values untouched. **Do not delete the line or leave it blank** — the pipeline reads it as a number and expects one to be there. A blank value becomes `NA` in R, and `NA` added to a measurement makes the measurement `NA`, which then propagates silently into your nightly totals.

The correction is a straight addition, so `6.3` shifts every value up by 6.3 dB and changes nothing about the shape of the data. Only use a non-zero value when you have a calibration figure for the recorder; if you are comparing sites recorded on identical settings, `0` is the honest choice.

---

## `bwFilterFrom` and `bwFilterTo`

```yaml
bwFilterFrom: "30000"
bwFilterTo: "70000"
```

The bottom and top of the frequency band to keep, in Hz. Everything outside this band is removed by a Butterworth band-pass filter before any measurement happens — so wind, insects, road noise and handling sounds are excluded, and what remains is the echolocation range.

**This is the setting with real scientific consequence.** The band decides what counts as a bat. Widening it admits noise and inflates your totals; narrowing it may exclude species whose calls sit outside the window. Our 30–70 kHz default suits the target species in this study.

Change it deliberately, and record that you did — the values used are printed at the top of every run log and are also visible in the `[1/4]` progress message, so a run is self-documenting.

Constraints worth knowing:

- `bwFilterTo` must be below half the `samplingRate`. At 192,000 Hz that ceiling is 96,000 Hz.
- `bwFilterFrom` must be below `bwFilterTo`.
- These are Hz, not kHz. 30 kHz is `30000`.

---

## A note on quoting

Some values are quoted in `config.yaml` and some are not:

```yaml
segmentDuration: "1"      # quoted
samplingRate: 192000      # unquoted
gainOffset: 6.3           # unquoted
bwFilterFrom: "30000"     # quoted
```

This is inconsistent but harmless. Every value is passed to R as a command line argument, which is a string either way, and the R code converts each one with `as.numeric()`. Follow the existing style when editing and you will not run into trouble.

---

## `folders.csv`

A two-column, **comma-separated** file listing which sites to process. One line per site or deployment.

```
sample,folder
AM68_ML_LGE,/Users/you/BatData/PAB_BB_052925_AM68_ML_LGE
AM78_M_LGE,/Users/you/BatData/PAB_BB_052925_AM78_M_LGE
```

| Column | Meaning |
|--------|---------|
| `sample` | A short name you choose. It becomes the name of the results folder and the label on the plot, so keep it filename-safe: no spaces, no slashes |
| `folder` | Full path to the folder of recordings for that site |

Three things break this file, all of them silently:

1. **It must be comma-separated.** Excel's default tab or semicolon export will not be read.
2. **No stray spaces** before or after a path.
3. **Every path must exist**, and any external drive must be mounted before you start.

Adding a line and re-running processes only the new site. Snakemake sees the existing sites' outputs already exist and leaves them alone.

---

## Where the results go

Not a `config.yaml` setting, but worth knowing: every output lands under `results/`, set by a single variable at the top of the `Snakefile`:

```python
RESULTS = "results"
```

Change that one string and the whole output tree moves with it. See [Understanding the Outputs](Understanding-the-Outputs).

---

## Plot appearance

The figures produced by `rule plot_site_totals` are tuned by constants at the top of `code/03_plotSiteTotals.R` rather than by `config.yaml`, since they are presentation choices rather than analysis parameters:

| Constant | Default | Controls |
|----------|---------|----------|
| `BASE_SIZE` | `20` | Base font size. Raise for posters, lower for slides |
| `PLOT_WIDTH` / `PLOT_HEIGHT` | `10` / `7` | Output size in inches |
| `PLOT_DPI` | `300` | Resolution. 300 is print quality |
| `POINT_FILL` | `"#E8A33D"` | Fill colour of the nightly points |
| `SMOOTH_COL` | `"#029475"` | Colour of the GAM trend line and its ribbon |
| `Y_LABEL` | `"RMS Amplitude (V)"` | The y-axis label |

The GAM smooth is fitted only when a site has **four or more nights** of data; below that it is skipped and the run log says so, because the fit is not meaningful — and would error outright — on a handful of points.

---

*Next: [Understanding the Outputs](Understanding-the-Outputs) — what the pipeline writes and what each column means*
