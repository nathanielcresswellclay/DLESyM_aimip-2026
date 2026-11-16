#!/bin/bash
# MareNostrum5 (GPP, CPU-only) wrapper around testing/scripts/coupled_forecast_gt_1983-2017.sh
#
# The gt "forcing" models need no GPU, so this runs on the general-purpose partition (submit from
# glogin = `ssh mn5_gpp`). Compute nodes have NO internet: the uv environment (.venv) must already
# be synced (done on alogin4, the only node with internet) and is used with `uv run --no-sync`.
#
# The job's working directory must be the REPO ROOT (log dir and relative paths depend on it). Either
# run sbatch from the repo root, or pass --chdir=<repo root> (what Claude does over ssh):
#   sbatch testing/scripts/mn5/gt_simulation.sbatch                 # 2h debug QoS, default settings
#   sbatch --qos=gp_bsces --time=48:00:00 \
#          --export=ALL,INIT=1983-01-02,END=2017-12-31,OUTPUT_DIR=/gpfs/scratch/bsc32/bsc930186/gt_sim \
#          testing/scripts/mn5/gt_simulation.sbatch
# Other overridable variables are listed at the top of coupled_forecast_gt_1983-2017.sh.

#SBATCH --job-name=gt_sim
#SBATCH --account=bsc32
#SBATCH --qos=gp_debug          # gp_debug (max 2h) | gp_bsces (max 48h)
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --output=logs/gt_simulation/%j.out
#SBATCH --error=logs/gt_simulation/%j.out

set -euo pipefail
echo "START $(date)  job=${SLURM_JOB_ID}  node=$(hostname)"

# Slurm runs a spooled copy of this file, so the repo root is the job's working dir, not the script dir.
export MODULE_DIR="${MODULE_DIR:-$PWD}"
cd "${MODULE_DIR}"

module load uv
export UV_FLAGS="--no-sync"        # offline: never touch the network or modify .venv
export UV_OFFLINE=1
export DEVICE_NUMBERS=-1
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

echo "git: $(git rev-parse --short HEAD) on $(git branch --show-current)"

bash testing/scripts/coupled_forecast_gt_1983-2017.sh

echo "END $(date)"
