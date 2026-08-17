# Installation and Setup

This page takes you from a machine with nothing installed to a finished pipeline run. No prior command-line experience is assumed — you can copy and paste every block below in order.

The pipeline uses [pixi](https://pixi.sh) to manage its software. Pixi reads [`pixi.toml`](Snakemake-Configuration) and installs the exact versions of R, Python, Snakemake and every R package the pipeline needs into a folder inside the project. It does not touch the rest of your computer, and it does not require you to install R or conda separately.

---

## 1. Install pixi

You only ever do this once per computer.

**macOS and Linux**

```bash
curl -fsSL https://pixi.sh/install.sh | sh
```

**Windows** (PowerShell)

```powershell
powershell -ExecutionPolicy ByPass -c "irm -useb https://pixi.sh/install.ps1 | iex"
```

Close your terminal and open a new one, then confirm it worked:

```bash
pixi --version
```

You should see something like `pixi 0.60.0`. If instead you get `command not found`, the installer added pixi to your PATH but your terminal has not picked it up yet — closing and reopening the terminal is what fixes it.

---

## 2. Get the pipeline

```bash
git clone https://github.com/mikemartinez99/SnakeBat
```

```bash
cd SnakeBat
```

Every command from here on is run from inside this `SnakeBat` folder. If a command fails with "no such file", the usual cause is being in the wrong directory — `pwd` prints where you are.

---

## 3. Install the software environment (once per computer)

```bash
pixi install
```

This downloads R, Python, Snakemake and the R packages, and writes them into a hidden `.pixi/` folder inside the project. Expect it to take several minutes and a few hundred megabytes the first time. It is only slow once; afterwards it is near-instant.

Then install the two R packages that come from CRAN rather than conda: (again, once per computer)

```bash
pixi run setup-r
```

`tuneR` and `seewave` — the packages that read `.WAV` files and do the filtering — are not published as conda packages, so this step fetches them from CRAN and installs them into the project environment. It is safe to run more than once; if they are already present it just says so and exits.

Confirm everything is in place:

```bash
pixi run check
```

A healthy environment prints:

```
R  ok: tuneR
R  ok: seewave
R  ok: lubridate
py ok: pandas 2.3.3
7.32.4
```

---

## 4. Point the pipeline at your data

Two files to edit before your first run. Both are plain text — any editor will do, including TextEdit or Notepad.

**`folders.csv`** — which recordings to process. One line per site or deployment: a short name you choose, then the full path to the folder of `.WAV` files.

```
sample,folder
AM68_ML_LGE,/Users/you/BatData/PAB_BB_052925_AM68_ML_LGE
AM78_M_LGE,/Users/you/BatData/PAB_BB_052925_AM78_M_LGE
```

The name on the left becomes the name of your results folder. Three things break this file, all of them silent:

- It must be **comma**-separated. Excel's default tab or semicolon export will not be read.
- No stray spaces before or after a path.
- Every path must exist, and any external drive must be mounted before you start.

**`config.yaml`** — the measurement settings. See [Snakemake Configuration](Snakemake-Configuration) for what each one means. The defaults suit our AudioMoth setup; the one with real scientific consequence is the filter band, since it decides what counts as a bat.

Save both files. An unsaved `config.yaml` is the single most common cause of "it ran, but with the wrong settings".

---

## 5. Run the pipeline

For a short test, run it in the foreground so you can watch:

```bash
pixi run pipeline
```

For a real dataset, run it in the background so it survives closing your laptop:

```bash
nohup pixi run pipeline &
```

The `&` sends the job to the background and prints a job number. `nohup` keeps it alive when the terminal closes. Snakemake's own output goes to `nohup.out`; the detailed per-recording logs go to `logs/`.

Check on a background job:

```bash
jobs -l
```

Watch the progress of one site as it runs:

```bash
tail -f logs/AM78_M_LGE.log
```

Stop a background job, using the number `jobs -l` printed:

```bash
kill -9 79417
```

To use more cores — sensible on a big dataset, since sites process simultaneously:

```bash
nohup pixi run pipeline --cores 8 &
```

---

## 6. Check it worked

A finished run leaves everything under `results/`:

```
SnakeBat/
|-- results/
|   |-- RMS_Power/                  per-second values, per site, then per date
|   |-- Total_RMSE/                 nightly files, one CSV per date per site
|   |-- Summary/
|   |   |-- <site>_combined_daily_totals.csv   every second, one file per site
|   |   |-- all_samples_nightly_totals.csv     one row per site per night
|   |-- plots/
|   |   |-- <site>_nightly_rmse.png            nightly RMS vs Julian date
|   |-- full_pipeline_run_log.log   every rule log, in order
|-- logs/                           one log per rule, per site
|-- nohup.out                       overall Snakemake progress
```

`results/full_pipeline_run_log.log` is written last and is what tells Snakemake the pipeline finished. Start there — it contains every other log.

For a quick look at your data, open `results/Summary/all_samples_nightly_totals.csv`: one row per site per night, small enough for Excel.

Everything is a plain CSV — open it in Excel or read it straight into R. See [Execution Flow and Outputs](Execution-Flow-and-Outputs) for what each column means.

The end of a per-site log tells you whether anything was skipped:

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

`Skipped (empty)` means the recorder wrote a file header with no audio behind it — usually a dead battery or a full SD card, worth checking if the count is more than a couple.

---

## Everyday commands

| Command | What it does |
|---------|--------------|
| `pixi run pipeline` | Run the pipeline in the foreground |
| `nohup pixi run pipeline &` | Run it in the background, survives closing the terminal |
| `pixi run dry-run` | List what *would* run, without running it |
| `pixi run check` | Confirm every dependency is importable |
| `pixi run unlock` | Clear a stale directory lock after an interrupted run |
| `pixi run setup-r` | Reinstall the CRAN R packages |
| `pixi task list` | Show every available task |

You never need to "activate" anything. `pixi run` uses the project environment automatically. If you do want an interactive shell inside it — to poke at results in R, say — use `pixi shell`, and `exit` to leave.

---

## When it will not run

Work down this list before asking for help; it covers nearly everything.

1. Are you inside the `SnakeBat` folder? (`pwd`)
2. Did `pixi install` and `pixi run setup-r` both complete without errors? (`pixi run check`)
3. Do all the paths in `folders.csv` exist, and is the external drive mounted?
4. Is `folders.csv` comma-separated, with no stray spaces?
5. Did you save `config.yaml` after editing it?

**"Directory cannot be locked"** — a previous run was interrupted. Snakemake leaves a lock behind so two jobs can never write to the same place. Clear it:

```bash
pixi run unlock
```

**"Nothing to be done"** — Snakemake only creates results that are missing, so it thinks the work is already complete. To genuinely rerun, delete the results folder; everything in it is regenerated from your `.WAV` files.

```bash
rm -rf results/
```

**Still stuck** — send us `results/full_pipeline_run_log.log`. It contains every rule's log in order, so it is usually all we need.

---

## A note on the older conda instructions

Earlier versions of this documentation used `conda env create -f env_config/snakeBat.yaml` followed by a manual `install.packages()` step in R. That still works, and `env_config/snakeBat.yaml` remains in the repository for anyone who needs it — including Snakemake's own `conda:` directive.

Pixi is now the recommended route because it installs R, Python, Snakemake and the CRAN packages in one step, and because `pixi.lock` records the exact resolved version of every package. That lock file is what makes a run on your laptop and a run on a colleague's machine produce the same numbers. Commit it alongside the code.

---

*Next: [Snakemake Configuration](Snakemake-Configuration) — what each setting in `config.yaml` controls*
