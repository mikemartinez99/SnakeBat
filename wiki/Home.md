# SnakeBat Pipeline — Documentation

**Authors:** Mike Martinez M.S. and Megan Graham  
**Original signal processing code:** Valerie Eddington

SnakeBat is a Snakemake workflow for calculating root mean square (RMS) acoustic energy from bat echolocation recordings. It takes raw `.WAV` files captured by AudioMoth recorders, applies a Butterworth bandpass filter to isolate echolocation frequencies, and outputs per-second RMS energy values in dBFS along with daily aggregate totals.

---

## What does this pipeline do?

1. **Filter** — isolates the bat echolocation frequency band (default 30–70 kHz) using a Butterworth bandpass filter
2. **Measure** — computes RMS energy in dBFS for every 1-second window of audio, corrected for microphone gain
3. **Organize** — groups output files by date automatically based on AudioMoth filename conventions
4. **Collate** — produces per-date summary files with total raw and zero-anchored adjusted RMS energy

---

## Wiki Pages

| Page | Contents |
|------|----------|
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
# 1. Clone the repo
git clone https://github.com/mikemartinez99/SnakeBat

# 2. Build the conda environment
conda env create -f env_config/snakeBat.yaml
conda activate snakeBat

# 3. Install R packages not in conda
R -e 'install.packages(c("tuneR", "seewave"))'

# 4. Edit config.yaml and folders.csv for your data

# 5. Run the pipeline
nohup snakemake -s Snakefile --cores 2 &
```

See [Snakemake Configuration](Snakemake-Configuration) for how to set up `config.yaml` and `folders.csv` before running.
