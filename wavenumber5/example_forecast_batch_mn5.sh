#!/bin/bash
#SBATCH -J example
#SBATCH --exclusive
#SBATCH --qos=acc_debug # options: acc_ehpc, acc_debug, acc_bsces, acc_bsccs
#SBATCH --output=logs/example/%j.out
#SBATCH --error=logs/example/%j.out
#SBATCH --time=00:10:00
#SBATCH --nodes=1
#SBATCH --gres=gpu:4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=80

# --- Email Notifications ---
##SBATCH --mail-type=end
##SBATCH --mail-user=nathaniel.cresswell@bsc.es

## EuroHPC allocation
#SBATCH --account=bsc32

echo "START TIME: $(date)"

# load modules
module load uv

export PYTHONWARNINGS="ignore::FutureWarning"
export HYDRA_FULL_ERROR=1
export LOGLEVEL=WARN

################ Environment Params ################
export MODULE_DIR=/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026
export INFERENCE_SCRIPT=${MODULE_DIR}/coupled_forecast_hdf5.py

################ Forecast Params ################

# Training parameters
export OUTPUT_DIR="/path/to/desired/output/directory"
export ATMOS_MODEL="/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026/models/dlwp"
export OCEAN_MODEL="/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026/models/dlom"
export ATMOS_OUTPUT_FILENAME="atmos_test"
export OCEAN_OUTPUT_FILENAME="ocean_test"
export DATA_DIR="/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026/example_data"
export LEAD_TIME="336"
export INIT_START="2017-01-01"
export INIT_END="2017-01-02"
export FREQ="biweekly"

#############################################################
############ Boiler plate to execute forecast ###############
#############################################################

cd ${MODULE_DIR}
export PYTHONPATH=${MODULE_DIR}

LAUNCH_CMD="uv run --no-sync ./scripts/coupled_forecast.py \
    --atmos-model-path ${ATMOS_MODEL} \
    --ocean-model-path ${OCEAN_MODEL} \
    --non-strict \
    --lead-time ${LEAD_TIME} \
    --forecast-init-start ${INIT_START} \
    --forecast-init-end ${INIT_END} \
    --freq ${FREQ} \
    --output-directory ${OUTPUT_DIR} \
    --atmos-output-filename ${ATMOS_OUTPUT_FILENAME} \
    --ocean-output-filename ${OCEAN_OUTPUT_FILENAME} \
    --data-directory ${DATA_DIR} \
    --gpu 0"

# Set environment variables and run the command
export WORLD_RANK=${SLURM_PROCID}
export HDF5_USE_FILE_LOCKING=False
export HYDRA_FULL_ERROR=1 

SRUN_ARGS="\
    --wait=60 \
    --kill-on-bad-exit=1\
"

# Change into the repository root so that relative imports and hydra config paths work seamlessly
cd ${MODULE_DIR}

srun ${SRUN_ARGS} --jobid ${SLURM_JOB_ID} bash -c "$LAUNCH_CMD"

echo "END TIME: $(date)"
