#!/bin/bash
# MareNostrum5 ACC (accelerated partition, 1 GPU) wrapper around the coupled gt simulation.
# Same job as gt_simulation.sbatch, but on a GPU node with the models on device 0. The gt forcing
# models don't need a GPU; this exercises the node type and device path that trained models will use.
#
# Submit from alogin (`ssh mn5`, alogin1). Compute nodes have NO internet: the uv environment
# (.venv) must already be synced (done on alogin4, the only node with internet).
# The job's working directory must be the REPO ROOT, so pass --chdir=<repo root> (or run from it):
#   sbatch --chdir=<repo> --export=ALL,END=1984-07-03 testing/scripts/mn5/gt_simulation_acc.sbatch   # 1-year test
# Overridable variables are listed at the top of coupled_forecast_gt_1983-2017.sh and in
# gt_simulation_common.sh.

#SBATCH --job-name=gt_sim_acc
#SBATCH --account=bsc32
#SBATCH --qos=acc_debug         # acc_debug (max 2h, 1 submitted job) | acc_bsces (max 48h)
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=20      # 1/4 of an ACC node (4 GPUs, 80 cores)
#SBATCH --output=logs/gt_simulation/%j.out
#SBATCH --error=logs/gt_simulation/%j.out

export DEVICE_NUMBERS=0
bash testing/scripts/mn5/gt_simulation_common.sh
