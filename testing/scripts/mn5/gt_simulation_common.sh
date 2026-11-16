#!/bin/bash
# Shared job body for the MN5 gt simulation sbatch wrappers (gt_simulation.sbatch = CPU/GPP,
# gt_simulation_acc.sbatch = GPU/ACC). Not submitted directly: the wrappers call it.
# Must run with the repo root as working directory (sbatch --chdir=<repo> or submit from the root).
# DEVICE_NUMBERS (-1 = CPU, 0 = first GPU) is set by the wrapper.

set -euo pipefail
echo "START $(date)  job=${SLURM_JOB_ID}  node=$(hostname)  device=${DEVICE_NUMBERS}"

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
export DEVICE_NUMBERS="${DEVICE_NUMBERS:--1}"
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}

echo "git: $(git rev-parse --short HEAD) on $(git branch --show-current)"

# GPU jobs: show the device. Note torch 1.13+cu117 (the pinned build) has no sm_90 kernels, so real GPU
# ops on the H100 nodes stall or fail; the gt forcing models launch no kernels, so they are unaffected.
# GPU_CHECK=1 runs real ops on the device (120s timeout) to test a node type / torch build;
# CHECK_ONLY=1 additionally stops before the simulation. Both are off by default.
if [[ "${DEVICE_NUMBERS}" != "-1" ]]; then
    nvidia-smi -L
fi
if [[ "${GPU_CHECK:-0}" == "1" || "${CHECK_ONLY:-0}" == "1" ]]; then
    timeout 120 uv run --no-sync --project "${MODULE_DIR}" python -u -c "
import torch
assert torch.cuda.is_available(), 'CUDA not available'
d = torch.device('cuda:${DEVICE_NUMBERS}')
print('torch', torch.__version__, '|', torch.cuda.get_device_name(d), '| compiled for', torch.cuda.get_arch_list())
x = torch.randn(64, 64, device=d); print('matmul', (x @ x).sum().item())
c = torch.nn.Conv2d(3, 4, 3).to(d)(torch.randn(2, 3, 16, 16, device=d)); print('conv2d', c.sum().item())
torch.cuda.synchronize(); print('GPU kernels OK on', d)
"
fi
if [[ "${CHECK_ONLY:-0}" == "1" ]]; then echo "CHECK_ONLY set: stopping before the simulation"; exit 0; fi

bash testing/scripts/coupled_forecast_gt_1983-2017.sh

echo "END $(date)"
