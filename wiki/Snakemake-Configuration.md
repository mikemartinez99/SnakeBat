# Snakemake Configuration

[← Driver Script](Driver-Script) | [Next: Snakemake Workflow →](Snakemake-Workflow)

This page covers the three configuration files that control the pipeline: `config.yaml` (parameters), `folders.csv` (samples), and `env_config/snakeBat.yaml` (software environment). These are the only files you need to edit to run the pipeline on your own data.

---

## `config.yaml`

**File:** `config.yaml`

```yaml
folders: "folders.csv"
segmentDuration: "1"
fileType: ".WAV"
samplingRate: 192000
gainOffset: 6.3
bwFilterFrom: "30000"
bwFilterTo: "70000"
```

This is the single user-facing control panel for the pipeline. Snakemake reads it at startup and makes every value available as a Python dictionary (`config["key"]`). Values are passed verbatim as command-line arguments to the R script.

### Parameters

| Key | Default | Type | Description |
|-----|---------|------|-------------|
| `folders` | `"folders.csv"` | string | Path to the sample manifest CSV. Keep as `"folders.csv"` unless you rename the file. |
| `segmentDuration` | `"1"` | string (numeric) | Duration of each RMS measurement window in seconds. `"1"` = one measurement per second. |
| `fileType` | `".WAV"` | string | File extension to search for. Case-sensitive on Linux. Use `".WAV"` for AudioMoth recordings. |
| `samplingRate` | `192000` | integer | Sample rate of the recordings in Hz. Must match your AudioMoth configuration. |
| `gainOffset` | `6.3` | float | Microphone gain calibration offset in dB. Added to every dBFS measurement to correct for hardware gain. See your microphone/recorder specification for the correct value. |
| `bwFilterFrom` | `"30000"` | string (integer) | Lower cutoff of the Butterworth bandpass filter in Hz. |
| `bwFilterTo` | `"70000"` | string (integer) | Upper cutoff of the Butterworth bandpass filter in Hz. |

### Notes on YAML formatting

- `segmentDuration`, `bwFilterFrom`, and `bwFilterTo` are **quoted strings** (`"1"`, `"30000"`) while `samplingRate` and `gainOffset` are bare numbers. YAML allows both; Snakemake passes all values to the shell as strings, so the distinction only matters if you use them in Python inside the `Snakefile` (you do not, here).
- Do not add trailing spaces or use tabs for indentation — YAML is whitespace-sensitive.
- After editing, save the file before running Snakemake.

### Adjusting for your bat species

The default filter range (30–70 kHz) targets eastern North American bat species. Adjust `bwFilterFrom` and `bwFilterTo` for your study region:

| Species group | Approximate call range | Suggested filter |
|---------------|----------------------|-----------------|
| Big brown bat | 25–50 kHz | `bwFilterFrom: "20000"`, `bwFilterTo: "55000"` |
| Little brown bat | 40–80 kHz | `bwFilterFrom: "35000"`, `bwFilterTo: "85000"` |
| Generic North American | 30–70 kHz | Default |

---

## `folders.csv`

**File:** `folders.csv`

```
sample,folder
test1,/path/to/data/session_1
test2,/path/to/data/session_2
```

This two-column comma-separated file defines the units of work. Each row is one "sample" — typically one recording device, one deployment site, or one night's session.

### Columns

| Column | Required | Description |
|--------|----------|-------------|
| `sample` | Yes | Short identifier for this sample. Used to name output directories and log files. No spaces — use underscores or hyphens. |
| `folder` | Yes | **Absolute path** to the directory containing `.WAV` files for this sample. Must exist before running. |

### Rules

- The file must be **comma-separated** with no extra whitespace before or after values on each line.
- Headers must be exactly `sample,folder` (lowercase, no spaces).
- Paths in the `folder` column must be absolute (starting from `/`). Relative paths will fail because Snakemake runs from the project root, not from wherever you are in the terminal.
- Double slashes in paths (e.g., `//SnakeBat/`) are harmless — most operating systems treat `//` identically to `/`.
- `.WAV` files can be nested in subdirectories inside `folder` — the pipeline uses `list.files(..., recursive = TRUE)` to find them.

### Adding new samples

Simply add a new row:

```
sample,folder
site_A,/data/recordings/site_A
site_B,/data/recordings/site_B
site_C,/data/recordings/site_C   ← add this
```

Snakemake will automatically detect the new sample and schedule one additional job for it. Previously completed samples will not be rerun (Snakemake checks whether their output directories already exist).

---

## `env_config/snakeBat.yaml`

**File:** `env_config/snakeBat.yaml`

```yaml
name: snakeBat
channels:
  - conda-forge
  - bioconda
  - defaults

dependencies:
  # Python
  - python=3.10
  - snakemake
  - pandas
  - numpy<2

  # R
  - r-base
  - r-dplyr
  - r-ggplot2
  - r-data.table
  - r-foreach
  - r-doparallel
  - r-lubridate
```

This conda environment file pins the complete software environment for the pipeline. Snakemake's `conda:` directive in `rule calc_RMS_Power` tells Snakemake to activate (or create) this environment before executing the rule's shell command.

### Why this matters

Environment isolation guarantees that the pipeline always runs with the exact packages listed here, regardless of what is installed in the user's base conda environment. This makes results reproducible across different machines and over time.

### Key dependencies

| Package | Layer | Role |
|---------|-------|------|
| `python=3.10` | Python | Pinned to avoid breaking API changes in 3.11+ for some bioconda packages |
| `snakemake` | Python | The workflow engine itself |
| `pandas` | Python | Used in the `Snakefile` to read `folders.csv` |
| `numpy<2` | Python | Version cap; NumPy 2.x introduced breaking changes incompatible with some bioconda packages |
| `r-base` | R | R language runtime |
| `r-lubridate` | R | `yday()` for Julian date calculation |
| `r-doparallel`, `r-foreach` | R | Listed but not directly used in the current scripts; available for future parallel constructs |

### Packages NOT in conda (must be installed manually)

`tuneR` and `seewave` are the two most critical R packages for the pipeline but are not available as standard conda packages. Install them once after activating the environment:

```bash
conda activate snakeBat
R -e 'install.packages(c("tuneR", "seewave"))'
```

This only needs to be done once per environment. If you rebuild the environment, you will need to reinstall them.

---

*Next: [Snakemake Workflow](Snakemake-Workflow)*
