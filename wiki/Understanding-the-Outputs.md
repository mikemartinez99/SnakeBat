# Understanding the Outputs

What the pipeline writes, where it goes, and what every column means.

For the execution order that produces these files, see [Execution Flow and Outputs](Execution-Flow-and-Outputs). For the settings that shape them, see [Parameters](Parameters).

---

## Where everything lands

Every pipeline output is written under a single `results/` folder. Nothing is written loose in the project directory.

```
SnakeBat/
│
├── logs/                                    one log per rule, per site
│   ├── <site>.log                           RMS power
│   ├── <site>_combine.log
│   ├── <site>_plot.log
│   └── collate_summary.log
│
├── nohup.out                                Snakemake's own progress
│
└── results/
    │
    ├── RMS_Power/                           the raw detail
    │   └── <site>.RMS_Power/
    │       └── YYYYMMDD/
    │           └── <recording>_RMSPower_1Second.csv
    │
    ├── Total_RMSE/                          per night, per site
    │   └── <site>.RMS_Power/
    │       └── YYYYMMDD_total_RMSE.csv
    │
    ├── Summary/
    │   ├── <site>_combined_daily_totals.csv every second, one file per site
    │   └── all_samples_nightly_totals.csv   one row per site per night
    │
    ├── plots/
    │   └── <site>_nightly_rmse.png
    │
    └── full_pipeline_run_log.log            every rule log, in order
```

The root is set by `RESULTS = "results"` at the top of the `Snakefile`. Change that one string and everything moves.

---

## Which file do I actually want?

| If you want to… | Open |
|-----------------|------|
| Eyeball a season in Excel | `results/Summary/all_samples_nightly_totals.csv` |
| Do stats in R on one site | `results/Summary/<site>_combined_daily_totals.csv` |
| Show someone a figure | `results/plots/<site>_nightly_rmse.png` |
| Find out why a run misbehaved | `results/full_pipeline_run_log.log` |
| Go back to second-by-second detail | `results/RMS_Power/<site>.RMS_Power/YYYYMMDD/` |

Most people start and finish with `all_samples_nightly_totals.csv`.

---

## `results/Summary/all_samples_nightly_totals.csv`

**One row per site per night, across every site in `folders.csv`.** The small, readable file — a full field season across several sites is still only a few hundred rows, so it opens comfortably in Excel.

| Column | Type | Meaning |
|--------|------|---------|
| `sample` | text | Site name, from `folders.csv` |
| `date` | text | Recording date, `YYYY-MM-DD` |
| `Julian` | integer | Day of year, 1–365 (366 in a leap year) |
| `n_seconds` | integer | How many 1-second segments contributed to that night |
| `total_raw_rmse` | number | Sum of `rmsEnergy` across the night. Large and negative |
| `total_adj_rmse` | number | Sum of `AdjustedValue` across the night. Positive |
| `mean_rmsEnergy` | number | Average loudness across the night, in dBFS |
| `min_rmsEnergy` | number | The quietest second |
| `max_rmsEnergy` | number | The loudest second |

`n_seconds` is worth watching. A night with far fewer seconds than its neighbours means recordings were missing, empty or too short — check that site's log before reading anything into its totals.

---

## `results/Summary/<site>_combined_daily_totals.csv`

**Every second of every night for one site, stacked into one file**, with a single header row retained. This is the per-date files concatenated — the `awk` step that used to be a manual instruction in the README.

Same columns as the per-date files below. Expect roughly **3,600 rows per night**, so a 100-night season is around 360,000 rows: fine for R, past Excel's comfortable range.

---

## `results/Total_RMSE/<site>.RMS_Power/YYYYMMDD_total_RMSE.csv`

One file per night per site.

**The important thing to understand:** despite the name, this is **not** a one-row summary. Each row is *one second* of audio, and the two totals are nightly constants repeated down every row.

| Column | Type | Meaning |
|--------|------|---------|
| *(first, unnamed)* | text | Row name carried over from `rbind` — the source file path plus a row number |
| `X` | integer | Segment index within its original recording |
| `rmsEnergy` | number | Gain-adjusted RMS energy for that second, in dBFS |
| `AdjustedValue` | number | `rmsEnergy` shifted so the quietest second in its recording is 0 |
| `date` | text | `YYYY-MM-DD` |
| `Julian` | integer | Day of year |
| `total_raw_rmse` | number | Sum of `rmsEnergy` for the whole night — **identical in every row** |
| `total_adj_rmse` | number | Sum of `AdjustedValue` for the whole night — **identical in every row** |

Because the totals repeat, do not sum the `total_raw_rmse` column. Take its first value, or use `all_samples_nightly_totals.csv`, which has already done that for you.

Note also that R renames the columns when reading this file: the blank first column becomes `X.1` and the `X` column stays `X`. Reference columns by name rather than by position.

---

## `results/RMS_Power/<site>.RMS_Power/YYYYMMDD/*.csv`

One CSV per original `.WAV` recording, filed into a folder per date. This is the rawest output the pipeline keeps.

| Column | Type | Meaning |
|--------|------|---------|
| *(first, unnamed)* | integer | Segment number within this recording |
| `rmsEnergy` | number | Gain-adjusted RMS energy for that second, in dBFS |
| `AdjustedValue` | number | `rmsEnergy` shifted so this recording's quietest second is 0 |

### Why `rmsEnergy` is negative

RMS energy is expressed in **dBFS** — decibels relative to full scale, where 0 dB is the loudest signal the recorder could possibly capture. Everything real is quieter than that, so every value is negative. Values around −60 to −70 are typical background; a loud pass climbs toward zero.

`AdjustedValue` exists because negative numbers are awkward to plot and to sum. It shifts the whole recording up so its quietest second sits at exactly 0, which preserves every difference between seconds while making the numbers positive. It is the same data, moved.

---

## `results/plots/<site>_nightly_rmse.png`

One figure per site: nightly `total_adj_rmse` against Julian date, with a GAM trend line and confidence ribbon.

- One point per night, not per second.
- The trend line only appears when a site has **four or more nights**. Below that it is skipped and the log says so.
- Transparent background, 10 × 7 inches at 300 dpi — drops straight into slides or a poster.

Appearance is tuned by constants at the top of `code/03_plotSiteTotals.R`; see [Parameters](Parameters).

---

## `results/full_pipeline_run_log.log`

Written by `rule all` as the final step, and the file to read first after any run. It contains every rule's log, concatenated in the order the pipeline produced them, each under a labelled header:

```
==============================================================================
  logs/AM78_M_LGE.log
==============================================================================
```

The order is: RMS power for each site, then each site's combine, then the cross-site collation, then each site's plot.

Its presence is also what tells Snakemake the pipeline finished — it replaced the old `done.txt` marker. **If you need help with a run, send this one file.**

---

## Reading a per-site log

Each `calc_RMS_Power` log opens with the settings used, then prints one line per recording:

```
[10:25:52] 3/9 ( 33%)  20250529_201424   ok    331 segments in 6.9s
[10:25:45] 1/9 ( 11%)  20250529_201341   skip  empty recording - 0 samples (check battery / card)
```

The identifier in the middle is the recording's date and time, pulled out of the much longer AudioMoth filename.

It closes with a summary:

```
  Files found         9
  Processed           7
  Skipped (cached)    0
  Skipped (short)     0
  Skipped (empty)     2
  Failed to read      0
  Segments written    3,606
  Wall time           1m 15s
```

| Line | Meaning |
|------|---------|
| `Processed` | Files that produced measurements |
| `Skipped (cached)` | Already done on an earlier, interrupted run |
| `Skipped (short)` | Recording shorter than one `segmentDuration` |
| `Skipped (empty)` | **Zero samples.** A file header with no audio — usually a flat battery or a full SD card |
| `Failed to read` | Corrupted. Search the log for `FAIL` to see which |

`Skipped (empty)` is the one to act on. A couple across a season is unremarkable; a run of them points at a hardware problem at that deployment.

---

## Re-running

Snakemake only creates results that are missing, so if everything is present it reports `Nothing to be done`. To genuinely rerun, delete what you want rebuilt — everything under `results/` regenerates from your `.WAV` files.

Everything:

```bash
rm -rf results/
```

A single site:

```bash
rm -rf results/RMS_Power/<site>.RMS_Power results/Total_RMSE/<site>.RMS_Power
rm -f results/Summary/<site>_combined_daily_totals.csv results/plots/<site>_nightly_rmse.png
rm -f results/full_pipeline_run_log.log
```

Adding a new line to `folders.csv` needs no deletion at all — Snakemake runs only the new site and leaves the finished ones alone.

---

*See also: [Parameters](Parameters) · [Execution Flow and Outputs](Execution-Flow-and-Outputs) · [Installation and Setup](Installation-and-Setup)*
