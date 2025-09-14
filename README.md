# SnakeBat Pipeline Documentation
Snakemake workflow for bat RMS processing.

<img src="img/SnakeBat_logo.png" alt="Description" width = 700 height = 450 style="border: none;" />

# Table of Contents
- [Introduction]
- [Installation]
- [Implementation]
- [Debugging]

## Introduction

## Installation

1. Clone the github repository in a location of your choosing.

```shell
git clone https://github/com/mikemartinez99/SnakeBat
```

2. Install required R packages not available via `conda`. This only needs to be done once.


```shell
# Activate conda environment
conda activate snakeBat
```

```shell
# Start an interactive R session
R
install.packages("tuneR")
install.packaghes(seewave)
quit()
```

## Implementation
To implement this pipeline, 3 things are **required**

1. `Snakefile`: Directs the flow of the pipeline

2. `config.yaml`: Defines crucial variables related to the operation of the pipeline. Ensure you modify variables as needed in valid json format (see example `config.yaml` in repo.)

3. `folders.csv`: Defines the list of folders you want to iterate over. This is a 2 column **comma separated** file. The headers for this file should be sample,folder. See example `folders.csv` in repo.

To implement the pipeline in the background via `nohup` with 4 cores, run the following command. This will generate a process ID (PID) for which you can track the status of your job. A file called `nohup.out` will contain Snakemake logging information that would normally be printed out to your terminal. Individual folder logs containing R code information will be stored in the `logs` folder, with one file per folder. Once you submit a nohup job, you can close your computer and the job will safely run in the background.

``` shell
nohup snakemake -s Snakefile --cores 4 &

# Example output showing PID
[1] 79417
```

**Note** You can increase the efficiency by increasing the number of cores. To check the number of cores on your machine run the following line. DO NOT exceed the number of performance cores your machine has!

```shell
system_profiler SPHardwareDataType | grep "Total Number of Cores
```

If running in the background, you can check the job status with the following command:

```shell
jobs -l

# Example output
[1]  + 79417 running    nohup snakemake -s Snakefile --cores 4
```

To kill a background job, run the following command, replacing `<PID> with your process ID
```shell
kill -9 <PID>

# Example
kill -9 79417
```

To run live with 4 cores, run the following
```shell
snakemake -s Snakefile --cores 4
```

## Debugging
**Checklist before you run**

- Did you activate the conda environment? 

```shell
conda activate snakeBat
```

- Did you modify `folders.csv` to point to valid folder paths?
- Did you ensure `folders.csv` is **comma separated?**
- Did you check for additional whitespace in `folders.csv`? There should be **NO** added whitespace.
- Did you modify variables in `config.yaml` to your specifications?
- If rerunning, did you unlock the snakemake directory and all outputs that would prevent pipeline from re-running (i.e., outputs from `rule all`?)

```shell
rm -r .snakemake
```

