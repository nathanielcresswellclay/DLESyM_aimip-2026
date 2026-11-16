#!/bin/bash

# Dummy coupled simulation for testing the coupling infrastructure.
# Both components are "ground truth" forcing models (atmos_gt_model and ocean_gt_model), so the
# output has the format of a normal DLESyM simulation but contains observations over 1983-2017.
# Useful for checking time alignment, coupling, output format and downstream processing.
#
# Set the paths marked TODO below. Memory/disk: the atmos output (6H, 9 vars, HPX64) is ~90GB for
# 35 years, and the hdf5 cache needs the same again in CACHE_DIR.

################ Environment Params ################
MODULE_DIR="/path/to/DLESyM_aimip-2026"    # TODO
DEVICE_NUMBERS="-1"                        # forcing models need no GPU

################ Model Params ################
ATMOS_MODEL="${MODULE_DIR}/models/atmos-forcing-model"
OCEAN_MODEL="${MODULE_DIR}/models/ocean-forcing-model"
# NOTE: the ground truth datasets themselves are set by `model.gt_dataset` in each model's
# .hydra/config.yaml. TODO: point both at your 1983-2017 gt zarr stores before running.
#   atmos: 6H-resolvable HPX64 zarr with `targets` for the 9 atmos output variables
#   ocean: daily HPX64 zarr with `targets` containing sst

# Initialization data (loaders need data at the init time and the preceding input times)
ATMOS_DATA_DIR="/path/to/atmos/init/data"  # TODO
ATMOS_DATASET_NAME="hpx64_1983-2017_3h_9varCoupledAtmos-sst"
OCEAN_DATA_DIR="/path/to/ocean/init/data"  # TODO
OCEAN_DATASET_NAME="hpx64_1983-2017_3h_1varCoupledOcean-z1000-ws10-olr"

################ Simulation Params ################
INIT="1983-01-02"                          # must have init data and gt data available
END="2017-12-31"
# lead time (hours) must be a multiple of the 96H coupling cycle (lcm of atmos 12H and ocean 96H)
DAYS=$(( ($(date -u -d ${END} +%s) - $(date -u -d ${INIT} +%s)) / 86400 ))
LEAD_TIME=$(( DAYS / 4 * 96 ))

OUTPUT_DIR="/path/to/output"               # TODO
CACHE_DIR="${OUTPUT_DIR}"
ATMOS_OUTPUT_FILENAME="atmos_gt_simulation_1983-2017"
OCEAN_OUTPUT_FILENAME="ocean_gt_simulation_1983-2017"

#############################################################
cd ${MODULE_DIR}
export PYTHONPATH=${MODULE_DIR}
export HDF5_USE_FILE_LOCKING=False
export HYDRA_FULL_ERROR=1
mkdir -p ${OUTPUT_DIR}

python scripts/coupled_forecast_hdf5.py \
    --atmos-model-path ${ATMOS_MODEL} \
    --ocean-model-path ${OCEAN_MODEL} \
    --non-strict \
    --lead-time ${LEAD_TIME} \
    --forecast-init-start ${INIT} \
    --forecast-init-end ${INIT} \
    --freq D \
    --time-chunk 1 \
    --step-chunk 1000 \
    --cache-dir ${CACHE_DIR} \
    --output-directory ${OUTPUT_DIR} \
    --atmos-output-filename ${ATMOS_OUTPUT_FILENAME} \
    --ocean-output-filename ${OCEAN_OUTPUT_FILENAME} \
    --atmos-data-directory ${ATMOS_DATA_DIR} \
    --ocean-data-directory ${OCEAN_DATA_DIR} \
    --atmos-dataset-name ${ATMOS_DATASET_NAME} \
    --ocean-dataset-name ${OCEAN_DATASET_NAME} \
    --gpu ${DEVICE_NUMBERS}
