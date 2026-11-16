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
#   sbatch --export=ALL,END=1984-07-03 testing/scripts/mn5/gt_simulation.sbatch   # 1-year timing run
#   sbatch --qos=gp_bsces --time=48:00:00 \
#          --export=ALL,INIT=1983-07-04,END=2017-06-30,OUTPUT_DIR=/gpfs/scratch/bsc32/bsc930186/gt_sim \
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
# MN5 defaults: the observation stores are used as both initialization data and ground truth.
# Override any of these with --export=ALL,VAR=...
DATA_DIR=/gpfs/scratch/bsc32/bsc930186/agu_advances_2025
OCEAN_STORE=hpx64_1983-2017_3h_1varCoupledOcean-z1000-ws10-olr
ATMOS_STORE=hpx64_1983-2017_3h_9varCoupledAtmos-sst
export ATMOS_DATA_DIR="${ATMOS_DATA_DIR:-$DATA_DIR}"
export OCEAN_DATA_DIR="${OCEAN_DATA_DIR:-$DATA_DIR}"
export ATMOS_DATASET_NAME="${ATMOS_DATASET_NAME:-$ATMOS_STORE}"
export OCEAN_DATASET_NAME="${OCEAN_DATASET_NAME:-$OCEAN_STORE}"
export ATMOS_GT_DATASET="${ATMOS_GT_DATASET:-$DATA_DIR/$ATMOS_STORE.zarr}"
export OCEAN_GT_DATASET="${OCEAN_GT_DATASET:-$DATA_DIR/$OCEAN_STORE.zarr}"
export OUTPUT_DIR="${OUTPUT_DIR:-/gpfs/scratch/bsc32/bsc930186/gt_sim/${SLURM_JOB_ID}}"

export UV_FLAGS="--no-sync"        # offline: never touch the network or modify .venv
export UV_OFFLINE=1
export DEVICE_NUMBERS=-1
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

echo "git: $(git rev-parse --short HEAD) on $(git branch --show-current)"

bash testing/scripts/coupled_forecast_gt_1983-2017.sh

echo "END $(date)"
