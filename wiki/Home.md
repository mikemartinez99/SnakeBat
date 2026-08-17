# SnakeBat Pipeline — Documentation

**Authors:** Mike Martinez M.S. and Megan Graham  
**Original signal processing code:** Valerie Eddington

SnakeBat is a Snakemake workflow for calculating root mean square (RMS) acoustic energy from bat echolocation recordings. It takes raw `.WAV` files captured by AudioMoth recorders, applies a Butterworth bandpass filter to isolate echolocation frequencies, and outputs per-second RMS energy values in dBFS along with daily aggregate totals.

---

## What does this pipeline do?

1. **Filter** — isolates the bat echolocation frequency band (default 30–70 kHz) using a Butterworth bandpass filter
2. **Measure** — computes RMS energy in dBFS for every 1-second window of audio, corrected for microphone gain
3. **Organize** — groups output files by date automatically based on AudioMoth filename conventions
4. **Collate** — produces per-date files with total raw and zero-anchored adjusted RMS energy
5. **Combine** — flattens each site's per-date files into one CSV, and builds a cross-site table of one row per site per night
6. **Plot** — draws nightly RMS energy against Julian date, one figure per site
7. **Report** — concatenates every rule's log into a single ordered run log

All output is written under `results/`.

---

## Wiki Pages

| Page | Contents |
|------|----------|
| [Installation and Setup](Installation-and-Setup) | Install pixi, set up the environment, run the pipeline, troubleshooting |
| [Repository Overview](Repository-Overview) | File tree, role of each file, data flow summary |
| [Signal Processing — `rmsPower()`](Signal-Processing-rmsPower) | Bandpass filter, segment slicing, dBFS math, gain offset |
| [Signal Processing — `calcTotalRMSE()`](Signal-Processing-calcTotalRMSE) | Date collation, Julian day, totaling across files |
| [Driver Script — `01_calcRMS_Power.R`](Driver-Script) | Argument parsing, Phase 1–3 orchestration, parallel post-processing |
| [Snakemake Configuration](Snakemake-Configuration) | `config.yaml`, `folders.csv`, conda environment |
| [Snakemake Workflow](Snakemake-Workflow) | Snakefile structure, `rule all`, `rule calc_RMS_Power`, wildcards |
| [Execution Flow and Outputs](Execution-Flow-and-Outputs) | DAG, end-to-end trace, output directory layout |

---

## Quick Start

```bash
# 1. Install pixi (once per computer), then reopen your terminal
curl -fsSL https://pixi.sh/install.sh | sh

# 2. Clone the repo
git clone https://github.com/mikemartinez99/SnakeBat
cd SnakeBat

# 3. Install the software environment (once per clone)
pixi install
pixi run setup-r
pixi run check

# 4. Edit config.yaml and folders.csv for your data

# 5. Run the pipeline in the background
nohup pixi run pipeline &
```

See [Installation and Setup](Installation-and-Setup) for the same steps explained in full, and [Snakemake Configuration](Snakemake-Configuration) for how to set up `config.yaml` and `folders.csv` before running.
