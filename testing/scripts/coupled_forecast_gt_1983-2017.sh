#!/bin/bash

# Dummy coupled simulation for testing the coupling infrastructure.
# Both components are "ground truth" forcing models (atmos_gt_model and ocean_gt_model), so the
# output has the format of a normal DLESyM simulation but contains observations over 1983-2017.
# Useful for checking time alignment, coupling, output format and downstream processing.
#
# Every setting below can be overridden from the environment (this is how the MN5 sbatch wrapper
# drives it). Otherwise set the paths marked TODO. Memory/disk: the atmos output (6H, 9 vars, HPX64) is ~90GB for
# 35 years, and the hdf5 cache needs the same again in CACHE_DIR.

################ Environment Params ################
# Repo root, resolved from this script's location (override by exporting MODULE_DIR)
MODULE_DIR="${MODULE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEVICE_NUMBERS="${DEVICE_NUMBERS:--1}"                        # forcing models need no GPU
# The simulation runs in the uv environment defined by pyproject.toml / uv.lock at the repo root.
# --frozen: use uv.lock exactly as is (never re-resolve or upgrade). Create the env first with `uv sync`.
# UV_FLAGS can be overridden, e.g. UV_FLAGS="--no-sync" on offline compute nodes (MN5).
UV_RUN="uv run ${UV_FLAGS:---frozen} --project ${MODULE_DIR}"

################ Model Params ################
ATMOS_MODEL="${ATMOS_MODEL:-${MODULE_DIR}/models/atmos-forcing-model}"
OCEAN_MODEL="${OCEAN_MODEL:-${MODULE_DIR}/models/ocean-forcing-model}"
# Ground truth datasets (zarr with a `targets` variable). If unset, `model.gt_dataset` from each
# model's .hydra/config.yaml is used.
#   atmos: HPX64 zarr (time step dividing 6H) with `targets` for the 9 atmos output variables
#   ocean: HPX64 zarr (time step dividing 48H) with `targets` containing sst
ATMOS_GT_DATASET="${ATMOS_GT_DATASET:-}"
OCEAN_GT_DATASET="${OCEAN_GT_DATASET:-}"
GT_ARGS=()
[[ -n "${ATMOS_GT_DATASET}" ]] && GT_ARGS+=(--atmos-gt-dataset "${ATMOS_GT_DATASET}")
[[ -n "${OCEAN_GT_DATASET}" ]] && GT_ARGS+=(--ocean-gt-dataset "${OCEAN_GT_DATASET}")

# Initialization data (loaders need data at the init time and the preceding input times)
ATMOS_DATA_DIR="${ATMOS_DATA_DIR:-/path/to/atmos/init/data}"  # TODO
ATMOS_DATASET_NAME="${ATMOS_DATASET_NAME:-hpx64_1983-2017_3h_9varCoupledAtmos-sst}"
OCEAN_DATA_DIR="${OCEAN_DATA_DIR:-/path/to/ocean/init/data}"  # TODO
OCEAN_DATASET_NAME="${OCEAN_DATASET_NAME:-hpx64_1983-2017_3h_1varCoupledOcean-z1000-ws10-olr}"

################ Simulation Params ################
INIT="${INIT:-1983-07-04}"   # data starts 1983-07-02; ocean loader needs 48H of history. Init+gt data must exist
END="${END:-2017-06-30}"   # data ends 2017-06-30T21:00
# lead time (hours) must be a multiple of the 96H coupling cycle (lcm of atmos 12H and ocean 96H)
DAYS=$(( ($(date -u -d ${END} +%s) - $(date -u -d ${INIT} +%s)) / 86400 ))
LEAD_TIME=$(( DAYS / 4 * 96 ))

OUTPUT_DIR="${OUTPUT_DIR:-/path/to/output}"  # TODO
CACHE_DIR="${OUTPUT_DIR}"
ATMOS_OUTPUT_FILENAME="atmos_gt_simulation_1983-2017"
OCEAN_OUTPUT_FILENAME="ocean_gt_simulation_1983-2017"

#############################################################
cd ${MODULE_DIR}
export PYTHONPATH=${MODULE_DIR}
export HDF5_USE_FILE_LOCKING=False
export HYDRA_FULL_ERROR=1
command -v uv >/dev/null || { echo "uv not found on PATH (https://docs.astral.sh/uv/)"; exit 1; }
mkdir -p ${OUTPUT_DIR}

${UV_RUN} python scripts/coupled_forecast_hdf5.py \
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
    "${GT_ARGS[@]}" \
    --gpu ${DEVICE_NUMBERS}
