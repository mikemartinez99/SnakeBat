# SnakeBat Pipeline
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
- [Understanding the Outputs](#understanding-the-outputs)
- [Debugging](#debugging)
- [Changelog](#changelog)
- [Contact](#contact)

## Introduction
This repository contains a simple one-rule Snakemake pipeline for calculating root mean square (RMS) power from bat acoustic energy recordings. RMS power is a widely used measure of signal intensity, allowing researchers to quantify the amplitude of bat echolocation calls over time. By automating RMS calcuations across large datasets, this workflow facilitates the analysis of bat activity, call structure, and energy distribution in acoustic monitoring studies in a highly reproducible manner.

**Features**
- Automated processing of .WAV files from multiple sessions (including continuous data, with automatic date partitioning)
- Automated segmenting of recordings based on user-defined durations with flexible bandpass filtering
- Generate RMS and adjusted RMS energy values
- Collate RMS metrics on a per-date basis for continuous data

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

- `config.yaml`: Defines crucial variables related to the operation of the pipeline. Ensure you modify variables as needed in valid json format (see example `config.yaml` in repo.)

- `folders.csv`: Defines the list of folders you want to iterate over. This is a 2 column **comma separated** file. The headers for this file should be sample,folder. See example `folders.csv` in repo.

To implement this pipeline:

1. Edit `config.yaml` and `folders.csv` for your data, and **save them**. An unsaved `config.yaml` is the most common cause of a run that completes with the wrong settings.

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

## Understanding the Outputs

The SnakeBat pipeline generates two main output folders: `RMS_Power/` and 'Total_RMSE`

``` shell
.
└── SnakeBat/
    ├── RMS_Power/
    │   └── Sample_1/
    │       └── YYYYMMDD/
    ├── Total_RMSE/
    │   └── Sample_1/
    │       └── YYYYMMDD/
    ├── Logs/
    │   └── Sample_1.log
    └── nohup.out
```

**RMS_Power**

Contains subfolders corresponding to each sample listed in `folders.csv`. Each subfolder contains additional subfolders representing each individual date encompassed in the data, named in YYYYMMDD format. Files within these folders contain csv files of RMS energy and adjusted RMS energy per second (each csv file is a 10 minute segment as per the AudioMoth settings.)

**Total_RMSE**

Contains subfolders corresponding to each sample listed in `folders.csv`. Each subfolder contains one csv file per date representing the daily RMS energy total. These files can be concatenated for easier viewing / data manipulation by navigating to the output folder of interest and running the following command. This command concatenates all files, keeping the header of the first file, and dropping the header from all other files. You can change the output file name to whatever you'd like. 

```shell
# Total summary concatenation (get one massive file of daily total RMS energy
awk 'FNR==1 && NR!=1 { next } { print }' *.csv > combined_daily_totals.csv
```

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



**done.txt**
`done.txt` is a "dummy" file created by the `rule_all` of this workflow. This file has no meaning or importance other than to signify the end of the pipeline!


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
Note that a Snakemake workflow will still not re-run even if unlocked if the expected outputs are already generated. Snakemake works off the principal of generating expected outputs. If all expected outputs are present, Snakemake will think there is nothing to be done. In this case, move the output folders and the `done.txt` file

``` shell
rm done.txt
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

