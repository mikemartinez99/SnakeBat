# Snakemake Workflow

[← Snakemake Configuration](Snakemake-Configuration) | [Next: Execution Flow and Outputs →](Execution-Flow-and-Outputs)

**File:** `Snakefile`

The `Snakefile` is a Python file extended with Snakemake's rule-based DSL. The top portion is pure Python (imports, config loading, sample discovery); each `rule` block is Snakemake syntax. Snakemake works by **backward chaining from a target**: it starts with the final output you want (`rule all`), figures out what rules are needed to produce it, and builds a DAG of jobs to run.

---

## Header — Imports and Config (Lines 1–12)

```python
import pandas as pd

configfile: "config.yaml"

sample_file = config["folders"]
samples_df  = pd.read_csv(sample_file).set_index("sample", drop=False)
sample_list = list(samples_df['sample'])
```

### `configfile` directive

```python
configfile: "config.yaml"
```

This is a Snakemake directive (not standard Python). It instructs Snakemake to parse `config.yaml` using PyYAML and expose the result as a global dictionary named `config`. After this line:

- `config["segmentDuration"]` → `"1"`
- `config["samplingRate"]` → `192000`
- `config["gainOffset"]` → `6.3`

### Loading the sample manifest

```python
samples_df = pd.read_csv(sample_file).set_index("sample", drop=False)
```

`pd.read_csv()` reads `folders.csv` into a pandas DataFrame. `.set_index("sample", drop=False)` makes `sample` the row index while keeping the column itself. This enables `.loc[sample_name, "folder"]` lookups by sample name later in the `params` block of `rule calc_RMS_Power`.

`drop=False` is important — without it, the `sample` column would be removed from the DataFrame after being set as the index, breaking the `list(samples_df['sample'])` extraction on the next line.

### Extracting the sample list

```python
sample_list = list(samples_df['sample'])
# → ["test1", "test2"]
```

This list is used by `expand()` in `rule all` to generate all expected output paths.

---

## The four rules

| Rule | Runs | Produces |
|------|------|----------|
| `calc_RMS_Power` | Once per sample | `results/RMS_Power/{sample}.RMS_Power/` (and `results/Total_RMSE/` as a side effect) |
| `combine_site_totals` | Once per sample | `results/Summary/{sample}_combined_daily_totals.csv` |
| `plot_site_totals` | Once per sample | `results/plots/{sample}_nightly_rmse.png` |
| `collate_summary` | Once, across all samples | `results/Summary/all_samples_nightly_totals.csv` |
| `rule all` | Once | `results/full_pipeline_run_log.log` |

Every output path is built from a single `RESULTS` variable at the top of the `Snakefile`:

```python
RESULTS = "results"
```

Change that one string and every rule follows.

Every rule also carries a `message:` directive, so a background run reports readable progress in `nohup.out`:

```
[1/4] Calculating RMS power for Test_2 (30000-70000 Hz, 1s segments) -> logs/Test_2.log
[2/4] Combining nightly files for Test_1 -> results/Summary/Test_1_combined_daily_totals.csv
[3/4] Plotting nightly RMS energy for Test_1 -> results/plots/Test_1_nightly_rmse.png
[4/4] Pipeline complete - assembling full run log at results/full_pipeline_run_log.log
```

---

## `rule all` — The Terminal Rule

```python
rule all:
    input:
        expand(RESULTS + "/RMS_Power/{sample}.RMS_Power", sample = sample_list),
        expand(RESULTS + "/Summary/{sample}_combined_daily_totals.csv", sample = sample_list),
        expand(RESULTS + "/plots/{sample}_nightly_rmse.png", sample = sample_list),
        RESULTS + "/Summary/all_samples_nightly_totals.csv"
    output:
        run_log = RESULTS + "/full_pipeline_run_log.log"
    params:
        logs = " ".join(ordered_logs())
    message:
        "[4/4] Pipeline complete - assembling full run log at {output.run_log}"
    shell: """
    ... concatenate every rule log, in order ...
    """
```

`rule all` is a Snakemake convention: the **first rule in the file is the default target**. When you run `snakemake` without specifying a rule name, Snakemake works backwards from this rule's `input` to build the DAG.

### `expand()`

```python
expand(RESULTS + "/RMS_Power/{sample}.RMS_Power", sample = sample_list)
```

`expand()` is a Snakemake function that generates all combinations of a path template with a list of values. For `sample_list = ["test1", "test2"]` it produces:

```python
["results/RMS_Power/test1.RMS_Power", "results/RMS_Power/test2.RMS_Power"]
```

Snakemake registers these as **required inputs** to `rule all`. Since neither exists on disk when you first run the pipeline, Snakemake searches its rules for ones that can produce them — finding `rule calc_RMS_Power`.

### Terminal output

Earlier versions wrote an empty `done.txt` sentinel here. `rule all` now produces something useful instead: `results/full_pipeline_run_log.log`, containing every rule's log concatenated in the order the pipeline produced them, each under a labelled header.

It still serves the same structural purpose — giving `rule all` a concrete output Snakemake can track, so it knows whether the rule has already run — but it is also the single file worth reading after a run, and the single file worth sending if you need help.

The order comes from a helper at the top of the `Snakefile`:

```python
def ordered_logs():
    logs = []
    logs += [f"logs/{s}.log" for s in sample_list]          # 1. calc_RMS_Power
    logs += [f"logs/{s}_combine.log" for s in sample_list]  # 2. combine_site_totals
    logs += ["logs/collate_summary.log"]                    # 3. collate_summary
    logs += [f"logs/{s}_plot.log" for s in sample_list]     # 4. plot_site_totals
    return logs
```

**Add new rules to this list as you add them to the workflow**, or their logs will be missing from the combined file.

To rerun the entire pipeline, delete `results/`.

---

## `rule calc_RMS_Power` — The Processing Rule (Lines 28–60)

```python
rule calc_RMS_Power:
    output:
        rms_power = directory("RMS_Power/{sample}.RMS_Power")
    params:
        sample       = lambda wildcards: wildcards.sample,
        folder       = lambda wildcards: samples_df.loc[wildcards.sample, "folder"],
        rms_code     = "code/01_calcRMS_Power.R",
        segDur       = config["segmentDuration"],
        fileType     = config["fileType"],
        samplingRate = config["samplingRate"],
        gainOffset   = config["gainOffset"],
        bwFilterFrom = config["bwFilterFrom"],
        bwFilterTo   = config["bwFilterTo"]
    conda:
        "env_config/snakeBat.yaml",
    log:
        "logs/{sample}.log"
    shell: """
        RScript {params.rms_code} \
            {params.folder} \
            {params.segDur} \
            {params.fileType} \
            {params.samplingRate} \
            {params.gainOffset} \
            {params.bwFilterFrom} \
            {params.bwFilterTo} \
            {output.rms_power} \
            &> {log}
    """
```

---

### `output` block

```python
output:
    rms_power = directory("RMS_Power/{sample}.RMS_Power")
```

**`{sample}` is a wildcard.** Snakemake fills it in based on which sample it is building. When it needs `RMS_Power/test1.RMS_Power`, it matches `{sample}` = `"test1"` and runs this rule with that substitution.

**`directory()`** tells Snakemake the output is a directory, not a single file. Without this wrapper, Snakemake would check for the existence of a *file* named `RMS_Power/test1.RMS_Power` and never find it. With `directory()`, it checks for the directory's existence instead.

The pattern `RMS_Power/{sample}.RMS_Power` matches the `expand()` template in `rule all` — this is the structural link that lets Snakemake connect the two rules.

---

### `params` block

```python
params:
    sample       = lambda wildcards: wildcards.sample,
    folder       = lambda wildcards: samples_df.loc[wildcards.sample, "folder"],
    rms_code     = "code/01_calcRMS_Power.R",
    segDur       = config["segmentDuration"],
    fileType     = config["fileType"],
    samplingRate = config["samplingRate"],
    gainOffset   = config["gainOffset"],
    bwFilterFrom = config["bwFilterFrom"],
    bwFilterTo   = config["bwFilterTo"]
```

The `params` block holds values needed in the `shell` command that are not direct file inputs or outputs. Static values (config entries, fixed paths) are assigned directly. Dynamic values that depend on the current wildcard use **lambda functions**.

#### Lambda functions

```python
sample = lambda wildcards: wildcards.sample
```

A Python anonymous function that receives the current `wildcards` object and returns `wildcards.sample` (e.g., `"test1"`). This is how you access the wildcard value inside `params` — you cannot reference `{wildcards.sample}` directly outside of a lambda in this block.

```python
folder = lambda wildcards: samples_df.loc[wildcards.sample, "folder"]
```

Uses the current sample name to look up the **absolute path to raw data** from the pandas DataFrame loaded in the header. For `sample = "test1"`, this returns the full path to that sample's `.WAV` files. This value becomes the `dataDir` argument to the R script.

---

### `conda` block

```python
conda:
    "env_config/snakeBat.yaml"
```

Before executing the `shell` command, Snakemake activates (or creates, if absent) the conda environment described in `snakeBat.yaml`. This guarantees the rule runs with the correct R, Python, and package versions regardless of what is installed in the user's base environment.

---

### `log` block

```python
log:
    "logs/{sample}.log"
```

The `{sample}` wildcard resolves to `logs/test1.log`, `logs/test2.log`, etc. Log files are **special in Snakemake**: unlike output files (which Snakemake deletes on failure to prevent incomplete artifacts from looking like successes), log files are **always kept** even when a rule fails. This ensures you can inspect the R console output to diagnose what went wrong.

---

### `shell` block

```python
shell: """
    RScript {params.rms_code} \
        {params.folder} \
        {params.segDur} \
        {params.fileType} \
        {params.samplingRate} \
        {params.gainOffset} \
        {params.bwFilterFrom} \
        {params.bwFilterTo} \
        {output.rms_power} \
        &> {log}
"""
```

Snakemake resolves all `{...}` placeholders to their actual values and passes the resulting string to `bash -c "..."`. For `sample = "test1"`, the expanded command is:

```bash
RScript code/01_calcRMS_Power.R \
    /path/to/PAB_BB_052925_AM68_ML_LGE \
    1 \
    .WAV \
    192000 \
    6.3 \
    30000 \
    70000 \
    RMS_Power/test1.RMS_Power \
    &> logs/test1.log
```

`&>` redirects both `stdout` and `stderr` to the log file. R's `message()` writes to `stderr`, so all progress messages from both the driver script and `BatFunctions.R` appear in the log.

The trailing `\` on each line is a bash line-continuation character allowing a long single command to span multiple lines for readability.

> **Known bug:** Line 54 of the Snakefile (the `gainOffset` line) has a trailing space after `\ `, which makes bash treat the backslash as a literal character rather than a line continuation. This can cause a shell syntax error depending on the shell environment. The line should read `{params.gainOffset} \` with no trailing space.

---

## How Wildcards Connect Rules

The relationship between `rule all` and `rule calc_RMS_Power` works through matching wildcard patterns:

```
rule all input:   "RMS_Power/{sample}.RMS_Power"   ← expand() fills {sample}
                              ↕ matches
rule calc output: "RMS_Power/{sample}.RMS_Power"   ← {sample} is the wildcard
```

When Snakemake sees that `rule all` needs `RMS_Power/test1.RMS_Power`, it scans for rules whose `output` pattern matches. It finds `rule calc_RMS_Power`, binds `{sample}` = `"test1"`, and schedules that job. The same happens for `"test2"`.

---

*Next: [Execution Flow and Outputs](Execution-Flow-and-Outputs)*
