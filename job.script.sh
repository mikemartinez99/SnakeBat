#!/bin/bash
#SBATCH --job-name="Snakebat"
#SBATCH --no-requeue
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=60:00:00
#SBATCH --mail-user=Megan.Graham@unh.edu
#SBATCH --mail-type=FAIL
#SBATCH --output=%x_%j.log
##========================================================#
set -euo pipefail

##----- Working directory
wd=$PWD
cd "$wd" || exit 1
mkdir -p slurm_logs logs results

##----- Quiet third-party noise
export PIXI_CACHE_DIR="/tmp/pixi-cache-$USER"
export PYTHONWARNINGS="ignore::FutureWarning,ignore::UserWarning"

##----- Path to pixi (.bashrc is not sourced in a non-interactive shell)
export PIXI_HOME="$HOME/.pixi"
PIXI="$PIXI_HOME/bin/pixi"
if [[ ! -x "$PIXI" ]]; then
    echo "ERROR: pixi not found at $PIXI" >&2
    exit 1
fi

##----- Validate the environment, silently unless it breaks
if ! CHECK_OUT=$("$PIXI" run --frozen -q check 2>&1); then
    echo "ERROR: pixi environment validation failed" >&2
    printf '%s\n' "$CHECK_OUT" >&2
    exit 1
fi

##----- Snakemake identity from inside the environment
SMVER=$("$PIXI" run --frozen -q bash -c 'snakemake --version' 2>/dev/null | tail -n1)
SMBIN=$("$PIXI" run --frozen -q bash -c 'command -v snakemake' 2>/dev/null | tail -n1)

##----- Optional dry run: sbatch job.script.sh --dry-run
SM_EXTRA=()
MODE="EXECUTE"
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    SM_EXTRA=(--dry-run --printshellcmds)
    MODE="DRY RUN"
fi

##----- Make slurm logs output folder
mkdir -p slurm_logs

#----- LOGGER
cat <<EOF
#───────────────────────── Initialization ──────────────────────────#
Running SnakeBat Pipeline v2.1 with Snakemake $SMVER
Mode:        $MODE
Job:         $SLURM_JOB_NAME
Job ID:      $SLURM_JOB_ID
Node:        $(hostname)
Start time:  $(date)
Work dir:    $wd
Snakemake:   $SMBIN
#───────────────────────────────────────────────────────────────────#
SNAKEMAKE LOG:
EOF

##----- Run the pipeline
"$PIXI" run --frozen -q snakemake \
    -s Snakefile \
    --profile cluster_profile \
    "${SM_EXTRA[@]}"
