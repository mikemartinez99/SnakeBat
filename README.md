# SnakeBat Pipeline ![Version](https://img.shields.io/badge/version-2.0-blue)
<img src="img/SnakeBat_logo.png" alt="SnakeBat Logo" width="400" height="150" align="right" style="border: none;" />

Snakemake workflow for root mean square (RMS) acoustic energy processing of bat data.

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Snakemake](https://img.shields.io/badge/Snakemake-v7.32.4-red?logo=snakemake&logoColor=white)
![Python Version](https://img.shields.io/badge/python-3.10.18-blue)
![R Version](https://img.shields.io/badge/R-4.4.1-blue)
![Environment](https://img.shields.io/badge/environment-pixi-orange)

# Table of Contents
- [Introduction](#introduction)
- [Installation](#installation)
- [Implementation](#implementation)
- [Parameters](#parameters)
- [Understanding the Outputs](#understanding-the-outputs)
- [Debugging](#debugging)
- [Changelog](#changelog)
- [Contact](#contact)

## Introduction
This repository contains a Snakemake pipeline for calculating root mean square (RMS) power from bat acoustic energy recordings. RMS power is a widely used measure of signal intensity, allowing researchers to quantify the amplitude of bat echolocation calls over time. By automating RMS calcuations across large datasets, this workflow facilitates the analysis of bat activity, call structure, and energy distribution in acoustic monitoring studies in a highly reproducible manner.

**Features**
- Automated processing of .WAV files from multiple sessions (including continuous data, with automatic date partitioning)
- Automated segmenting of recordings based on user-defined durations with flexible bandpass filtering
- Generate RMS and adjusted RMS energy values
- Collate RMS metrics on a per-date basis for continuous data
- Combine each site's nightly files into a single flat CSV
- Produce a cross-site summary table, one row per site per night
- Plot nightly RMS energy against Julian date, one figure per site
- Assemble every rule's log into one ordered run log

**Requirements**

All software requirements are declared in [`pixi.toml`](https://github.com/mikemartinez99/SnakeBat/blob/main/pixi.toml). 

## Installation

The pipeline uses [pixi](https://pixi.sh) to manage its software. Pixi installs the exact versions of R, Python, Snakemake and every R package into a folder inside the project — it does not touch the rest of your system, and you do not need R or conda installed beforehand.

1. Install pixi. **Once per computer.**

```shell
curl -fsSL https://pixi.sh/install.sh | sh
```

On Windows, use PowerShell instead:

```shell
powershell -ExecutionPolicy ByPass -c "irm -useb https://pixi.sh/install.ps1 | iex"
```

Close your terminal and open a new one, then check it worked. If you get `command not found`, reopening the terminal is what fixes it — the installer changed your PATH.

```shell
pixi --version
```

2. Clone the github repository in a location of your choosing, and move into it.

```shell
git clone https://github.com/mikemartinez99/SnakeBat
cd SnakeBat
```

3. Install the software environment. **Once per repository clone.** This takes a few minutes and a few hundred megabytes the first time; it is near-instant thereafter.

```shell
pixi install
```

4. Install the two R packages that come from CRAN. **Once per clone.**

```shell
pixi run setup-r
```

`tuneR` and `seewave` are the packages that read `.WAV` files and apply the bandpass filter, and neither is published as a conda package on any channel — so they are fetched from CRAN and installed into the project environment. The command is safe to repeat; if they are already present it says so and exits.

5. Confirm the environment is complete.

```shell
pixi run check
```

A healthy environment prints:

```shell
R  ok: tuneR
R  ok: seewave
R  ok: lubridate
py ok: pandas 2.3.3
7.32.4
```


</details>

## Implementation
To implement this pipeline, 3 things are **required**

- `Snakefile`: Directs the flow of the pipeline

- `config.yaml`: Defines crucial variables related to the operation of the pipeline. Ensure you modify variables as needed (see example `config.yaml` in repo). Every setting is documented under [Parameters](#parameters), with a full reference in [wiki/Parameters.md](wiki/Parameters.md).

- `folders.csv`: Defines the list of folders you want to iterate over. This is a 2 column **comma separated** file. The headers for this file should be sample,folder. See example `folders.csv` in repo.

To implement this pipeline:

1. Edit `config.yaml` and `folders.csv` for your data, and **save them**. See [Parameters](#parameters) for what each setting does. An unsaved `config.yaml` is the most common cause of a run that completes with the wrong settings.

2. Run the pipeline in the background via `nohup` from within the SnakeBat folder. This generates a job number you can use to track it. A file called `nohup.out` will contain the Snakemake logging that would normally print to your terminal, and per-sample R logs are written to the `logs` folder, one file per sample. Once submitted, you can close your computer and the job will keep running.

``` shell
nohup pixi run pipeline &

# Example output showing the job number
[1] 79417
```

There is no environment to activate. `pixi run` uses the project environment automatically, and installs it first if it is missing.

To check the status of a background job:

```shell
jobs -l

# Example output
[1]  + 79417 running    nohup pixi run pipeline
```

To watch a sample's progress as it runs:

```shell
tail -f logs/AM78_M_LGE.log
```

To kill a background job, replacing `<PID>` with your job number:

```shell
kill -9 <PID>

# Example
kill -9 79417
```

To run live in the foreground:

```shell
pixi run pipeline
```

To use more cores than the default of 2 — worth doing on a large dataset, since samples process simultaneously:

```shell
nohup pixi run pipeline --cores 8 &
```

**Other available tasks**

| Command | What it does |
|---------|--------------|
| `pixi run pipeline` | Run the pipeline |
| `pixi run dry-run` | List what *would* run, without running it |
| `pixi run check` | Confirm every dependency is importable |
| `pixi run unlock` | Clear a stale Snakemake lock after an interrupted run |
| `pixi run setup-r` | Reinstall the CRAN R packages |
| `pixi task list` | Show every available task |

If you want an interactive shell inside the environment — to explore results in R, for instance — use `pixi shell`, and `exit` to leave.

## Parameters

Every setting lives in `config.yaml`, except the list of sites, which lives in `folders.csv`. These two files are the only ones you edit to run the pipeline on your own data.

| Parameter | Our default | What it controls |
|-----------|-------------|------------------|
| `folders` | `"folders.csv"` | Which file lists the sites to process |
| `segmentDuration` | `"1"` | Seconds of audio per measurement |
| `fileType` | `".WAV"` | Which files to look for. Case sensitive |
| `samplingRate` | `192000` | Recorder sampling rate in Hz. Must match the field setting |
| `gainOffset` | `6.3` | Fixed dB correction for recorder gain |
| `bwFilterFrom` | `"30000"` | Bottom of the frequency band to keep, in Hz |
| `bwFilterTo` | `"70000"` | Top of the frequency band to keep, in Hz |

> **If you do not need a gain adjustment, set `gainOffset: 0`.**
>
> ```yaml
> gainOffset: 0
> ```
>
> Zero adds nothing and leaves the raw dBFS values untouched. **Do not delete the line or leave it blank** — a blank value is read as `NA` in R, and `NA` added to a measurement makes the measurement `NA`, which then propagates silently into your nightly totals.

The filter band is the setting with real scientific consequence: it decides what counts as a bat. Widening it admits noise, narrowing it may exclude species. Change it deliberately — the values used are printed at the top of every run log, so a run is self-documenting.

**Full reference:** [Parameters](wiki/Parameters.md) — what each setting does, how to choose it, the constraints, and what breaks if it is wrong. Also covers `folders.csv` and the plot appearance constants.

## Understanding the Outputs

**Full reference:** [Understanding the Outputs](wiki/Understanding-the-Outputs.md) — every file the pipeline writes, what each column means, and how to read a run log.

Every pipeline output is written under a single `results/` folder. Nothing is written to the top level of the repository.

``` shell
.
└── SnakeBat/
    ├── results/
    │   ├── RMS_Power/
    │   │   └── Sample_1.RMS_Power/
    │   │       └── YYYYMMDD/          # one CSV per recording, per-second values
    │   ├── Total_RMSE/
    │   │   └── Sample_1.RMS_Power/
    │   │       └── YYYYMMDD_total_RMSE.csv
    │   ├── Summary/
    │   │   ├── Sample_1_combined_daily_totals.csv
    │   │   └── all_samples_nightly_totals.csv
    │   ├── plots/
    │   │   └── Sample_1_nightly_rmse.png
    │   └── full_pipeline_run_log.log  # every rule log, concatenated in order
    ├── logs/
    │   └── Sample_1.log
    └── nohup.out
```

The root is set by a single `RESULTS` variable at the top of the `Snakefile`. Change that one string to send results elsewhere.

**RMS_Power**

Contains subfolders corresponding to each sample listed in `folders.csv`. Each subfolder contains additional subfolders representing each individual date encompassed in the data, named in YYYYMMDD format. Files within these folders contain csv files of RMS energy and adjusted RMS energy per second (each csv file is a 10 minute segment as per the AudioMoth settings.)

**Total_RMSE**

Contains subfolders corresponding to each sample listed in `folders.csv`. Each subfolder contains one csv file per date. Note that each of these files holds one row **per second**, not one row per date — `total_raw_rmse` and `total_adj_rmse` are nightly constants repeated down every row.

Concatenating these by hand is no longer necessary. The `awk` one-liner that used to live here is now `rule combine_site_totals`, which runs automatically and writes `results/Summary/{sample}_combined_daily_totals.csv`.

**Summary**

Two kinds of file, both produced automatically:

| File | Shape | Use |
|------|-------|-----|
| `{sample}_combined_daily_totals.csv` | Every second, one file per site | Analysis in R. Large: ~3,600 rows per night |
| `all_samples_nightly_totals.csv` | One row per site per night | Opens comfortably in Excel |

The cross-site summary carries `sample`, `date`, `Julian`, `n_seconds`, `total_raw_rmse`, `total_adj_rmse`, and the mean, min and max of `rmsEnergy` for that night.

**plots**

One PNG per site, `{sample}_nightly_rmse.png`: nightly adjusted RMS energy against Julian date, with a GAM smooth once there are at least four nights of data. Transparent background, sized for slides and posters.

**logs folder**

Contains one log file per sample. Each log opens with the settings the run used, then prints one timestamped line per recording, then an end-of-run summary. A single line looks like:

```shell
[10:25:52] 3/9 ( 33%)  20250529_201424   ok    331 segments in 6.9s
```

The summary tells you what was and was not processed:

```shell
  Files found         9
  Processed           7
  Skipped (cached)    0
  Skipped (short)     0
  Skipped (empty)     2
  Failed to read      0
  Segments written    3,606
  Wall time           1m 15s
```

`Skipped (empty)` means the recorder wrote a file header with no audio behind it — usually a flat battery or a full SD card, and worth investigating if the count is more than a couple. `Failed to read` marks corrupted files; search the log for `FAIL` to see which. 

**nohup.out**
If running in the background with `nohup`, this log shows the progress of the pipeline and verbose Snakemake logging (i.e., number of jobs per rule, etc...)



**full_pipeline_run_log.log**

Written by `rule all` as the final step. Every rule's log, concatenated in the order the pipeline produced them — RMS power per sample, then the per-site combines, then the cross-site collation, then the plots — each under a labelled header. Its presence is also what tells Snakemake the pipeline finished, so it replaces the old `done.txt` marker.

Send this one file if you need help with a run; it contains everything.


## Debugging
**Checklist before you run**

- Is the environment complete? There is nothing to activate, but this confirms every dependency is importable:

```shell
pixi run check
```
- Are you in the SnakeBat working directory?
- Do all paths in  `folders.csv` point to valid folder paths that exist and contain non-empty files?
- Is `folders.csv` **comma separated?** with no additional whitespace before or after each line?
- Did you modify variables in `config.yaml` to your specifications? If yes, did you save the config.yaml?
- If rerunning, did you unlock the snakemake directory and all outputs that would prevent pipeline from re-running (i.e., outputs from `rule all`?) (more on this below...)

**Re-running an anlysis**
When you launch a Snakemake workflow, it creates a lock on the working directory to make sure that only one instance of Snakemake is writing files there. This prevents two jobs from accidentally overwriting results or corrupting intermediate files if they were run at the same time.
If a workflow crashes, gets killed, or is stopped abruptly, Snakemake may leave the lock file behind in a hidden folder called `.snakemake` (hidden folders can be viewed in your terminal using `ls -a`. Then, when you try to restart the workflow, Snakemake refuses to run because it thinks another process is still active. To unlock your Snakemake directory you have 2 options:

1. The clean way (run this in your terminal within the SnakeBat directory)

```shell
pixi run unlock
```

2. The quick and dirty way

```shell
rm -r .snakemake
```
Note that a Snakemake workflow will still not re-run even if unlocked if the expected outputs are already generated. Snakemake works off the principal of generating expected outputs. If all expected outputs are present, Snakemake will think there is nothing to be done. In this case, remove the results folder — everything in it is regenerated from your `.WAV` files.

``` shell
rm -rf results/
```

To rerun a single sample rather than everything, delete just that sample's outputs:

``` shell
rm -rf results/RMS_Power/<sample>.RMS_Power results/Total_RMSE/<sample>.RMS_Power
rm -f results/Summary/<sample>_combined_daily_totals.csv results/plots/<sample>_nightly_rmse.png
rm -f results/full_pipeline_run_log.log
```

## Changelog

*October 12th, 2025:* 

- Adjusted date column in Total_RMSE output to be in YYYY-MM-DD format

- Added `lubridate` package to conda to facilitate Julian date conversion

- Adjusted `code/BatFunctions.R` to specify duration as `seewave::duration` to avoid conflict with `lubridate::duration`

- Added calculation of Julian date

*November 25th, 2025:*

- Added gainOffset to config

- Adjusted `BatFunctions.R` to take gainOffset

- Adjusted `01_calcRMS_Power.R` to apply gain offset

*August 17th, 2026:*

- **All pipeline output now lives under `results/`**, preserving the previous folder structure one level down. The root is set by the `RESULTS` variable at the top of the `Snakefile`

- **`done.txt` replaced by `results/full_pipeline_run_log.log`** — `rule all` now concatenates every rule's log, in pipeline order, into one file

- Added `rule combine_site_totals`: the `awk` concatenation formerly documented in this README, promoted to a rule that runs per site automatically

- Added `rule collate_summary` (`code/02_collateSummary.R`): one row per site per night across all samples, small enough to open in Excel

- Added `rule plot_site_totals` (`code/03_plotSiteTotals.R`): nightly RMS energy vs Julian date, one PNG per site, with a GAM smooth once four or more nights exist. Added `r-mgcv` to the environment, which `geom_smooth(method = "gam")` requires

- Added `message:` directives to every rule, so background runs report progress in `nohup.out`

- Added `pixi.toml`; pixi is now the recommended way to install and run the pipeline. The conda route still works and is documented under Installation

- Added a `container:` directive to the `Snakefile` for running with `--use-singularity` on a cluster

- Reworked logging: one line per recording instead of three, wall-clock timestamps, an ETA heartbeat on long runs, and an end-of-run summary that counts processed / skipped / failed files separately

- Empty recordings (0 samples) are now reported distinctly from short ones, since they indicate a recorder problem rather than a short file

- Fixed a trailing space after a line-continuation backslash in the `Snakefile` that truncated the `RScript` call to six arguments

- Fixed an always-true argument count check in `01_calcRMS_Power.R` (`< 8 | > 7`, which is satisfied by every possible value)

## Contact
For questions regarding this pipeline feel free to submit an issue to the github repo or contact:

**Mike Martinez M.S.** - *Dartmouth Center for Quantitative Biology, Genomic Data Science Core*

mike.j.martinez99@gmail.com

