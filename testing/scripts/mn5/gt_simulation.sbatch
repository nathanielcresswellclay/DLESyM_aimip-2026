#!/bin/bash
# MareNostrum5 GPP (CPU-only) wrapper around the coupled gt simulation (job logic is in
# gt_simulation_common.sh; a GPU variant is gt_simulation_acc.sbatch).
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

export DEVICE_NUMBERS=-1
bash testing/scripts/mn5/gt_simulation_common.sh
