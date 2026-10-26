#!/bin/bash
#SBATCH -J example
#SBATCH --exclusive
#SBATCH --qos=gp_debug
#SBATCH --output=/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026/wavenumber5/logs/remap_historical_atmos_%j.out
#SBATCH --error=/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026/wavenumber5/logs/remap_historical_atmos_%j.out
#SBATCH --time=00:10:00
#SBATCH --nodes=1
# Remap is a single Python process with multiprocessing.Pool, not MPI.
# Use one Slurm task and give it the CPUs that --poolsize should use.
# MN5 GPP nodes have 112 cores; 32 is a reasonable start (raise toward 56/112 if CPU-bound).
# --exclusive still only grants ntasks * cpus-per-task in the job cgroup, so request what you use.
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32

# --- Email Notifications ---
##SBATCH --mail-type=end
##SBATCH --mail-user=nathaniel.cresswell@bsc.es

## EuroHPC allocation
#SBATCH --account=bsc32

echo "START TIME: $(date)"

# load modules
module load uv

################ Remapping Params #################

# Module parameters
export MODULE_DIR="/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026"
# Variable to remap 
export VAR="z250"
# Input and output files
export INPUT_FILE="/gpfs/scratch/bsc32/bsc930186/agu_advances_2025/forced_atmos_dlesym_1983-2017.nc"
export OUTPUT_FILE="/gpfs/scratch/bsc32/bsc930186/agu_advances_2025/forced_atmos_dlesym_1983-2017_ll_${VAR}.nc"
# Chunking arguments
# TIME_CHUNK=1 is right for single-init / memory-light jobs.
# STEP_CHUNK is the lead-time tile size; keep it >= POOLSIZE so workers stay busy.
export TIME_CHUNK=1
export STEP_CHUNK=512
# Match the worker pool to the CPUs requested above.
export POOLSIZE=${SLURM_CPUS_PER_TASK:-32}


#############################################################
############ Boiler plate to remap forecast #################
#############################################################

cd ${MODULE_DIR}
export PYTHONPATH=${MODULE_DIR}

LAUNCH_CMD="uv run --no-sync ./evaluation/remap_forecast.py \
    --infile ${INPUT_FILE} \
    --outfile ${OUTPUT_FILE} \
    --var ${VAR} \
    --time-chunk ${TIME_CHUNK} \
    --step-chunk ${STEP_CHUNK} \
    --chunk-ds \
    --poolsize ${POOLSIZE}"

# Set environment variables and run the command
export WORLD_RANK=${SLURM_PROCID}
export HDF5_USE_FILE_LOCKING=False
export HYDRA_FULL_ERROR=1
# Keep BLAS/OpenMP from spawning extra threads inside each remap worker.
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1 

SRUN_ARGS="\
    --wait=60 \
    --kill-on-bad-exit=1\
"

# Change into the repository root so that relative imports and hydra config paths work seamlessly
cd ${MODULE_DIR}

srun ${SRUN_ARGS} --jobid ${SLURM_JOB_ID} bash -c "$LAUNCH_CMD"

echo "END TIME: $(date)"
