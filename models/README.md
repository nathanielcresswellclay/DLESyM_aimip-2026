# models/

One directory per model. Each holds `.hydra/config.yaml` (the config the coupled scripts compose) and
`tensorboard/checkpoints/*.ckpt`. Everything under `models/` except this file is Git LFS (see `.gitattributes`);
a checkout without `git lfs pull` contains small pointer files, not configs or weights.

| dir | role | class (`model._target_`) | step | notes |
|---|---|---|---|---|
| `dlwp` | trained atmosphere (DLWP) | `HEALPixRecUNet` | 6H | 9 prognostic vars (`z500 tau300-700 z1000 t2m0 tcwv0 t850 z250 ws10 olr`), SST coupled in via `ConstantCoupler` |
| `dlom` | trained ocean (DLOM) | `HEALPixUNet` | 48H | predicts `sst`; atmosphere coupled in as 48H trailing means (`z1000-48H ws10-48H olr-48H`) |
| `ocean-forcing-model` | **prescribed** ocean | `ocean_gt_model` | 48H | outputs SST from a forcing dataset (AIMIP daily SST, see `aimip/README.md`); used for the AIMIP runs |
| `ocean-forcing-model_2k`, `_4k` | prescribed ocean, +2K / +4K | `ocean_gt_model` | 48H | identical to the above except `model.gt_dataset` |
| `atmos-forcing-model` | **prescribed** atmosphere (testing) | `atmos_gt_model` | 6H | same 9 variables as `dlwp`; outputs observations from a gt dataset |
| `precip` | precipitation diagnosis | `HEALPixUNet` | 6H | maps 10 atmos/ocean vars -> `tp6`; run after a simulation by `aimip/precip_diagnosis/` |

The two `*_gt_model` classes live in `training/dlwp/model/models/diagnostic_models.py`.

## Ground-truth ("forcing") models

Purpose: replace a component with observations/prescribed fields to test the coupling, time alignment, output
format and downstream processing, or to force the other component.

- They subclass/mimic the real model so they can be instantiated from the same config, but **`forward` ignores its
  input and has no meaningful weights.** It returns `gt_dataset.targets` at times
  `init + (integration_counter * output_time_dim + i + 1) * step`, i = 0..output_time_dim-1, scaled with the data
  module's `target_scaling` (the coupled script un-scales it again, so output is in physical units).
- Models with `debugging_model = True` get `set_output(forecast_dates, forecast_integrations, data_module)` from
  `scripts/coupled_forecast*.py`; that is how they learn the init dates, step and variable list.
- `gt_dataset`: zarr with a `targets` variable, dims `(time, channel_out, face, height, width)` on the HPX64
  grid, containing every output variable and a timestamp at each `init + k*step`. Resolution is read from the data.
- The coupled scripts always load a checkpoint, so each forcing model needs one. It is arbitrary:
  regenerate with `python scripts/make_forcing_checkpoint.py models/<dir>` (needs `--gt-dataset` pointing at any
  existing zarr). `atmos-forcing-model`'s config holds a placeholder `gt_dataset`, so always override it.
- Override the gt dataset without editing shared configs: `scripts/coupled_forecast_hdf5.py` takes
  `--atmos-gt-dataset` / `--ocean-gt-dataset` (not the in-memory `coupled_forecast.py`).
- Initialization data is still required from the normal data modules (loaders read init-time inputs, and the
  ocean loader needs 48H of history), even though the gt model provides every later step.

## Coupling cadence

A coupled integration is 96H: atmosphere window = gap 6H + (2-1)*6H = 12H, ocean = 48H + 48H = 96H, lcm = 96H.
Per integration the atmosphere produces 16 steps (6H) and the ocean 2 steps (48H). Lead time must be a multiple
of 96H; `testing/scripts/coupled_forecast_gt_1983-2017.sh` rounds down to this, so a run ends up to 3 days
before the requested end date.

## Output format (`scripts/coupled_forecast_hdf5.py`)

Two NetCDF files, `<atmos|ocean>_...nc`. Dims: `time` (initialization dates), `step` (timedelta; `step[0] = 0` holds
the init data, then each model step), `face`(12), `height`/`width`(64). One data variable per output channel,
in physical units (float32). Atmos: 9 variables at 6H; ocean: `sst` at 48H.

## Dummy observation simulation (gt atmos + gt ocean, 1983-2017)

- Script: `testing/scripts/coupled_forecast_gt_1983-2017.sh` (workstation, `uv run --frozen`);
  MN5: `testing/scripts/mn5/gt_simulation{,_acc}.sbatch` (see `.claude/skills/mn5-*`).
- Data on MN5: `/gpfs/scratch/bsc32/bsc930186/agu_advances_2025/hpx64_1983-2017_3h_{9varCoupledAtmos-sst,1varCoupledOcean-z1000-ws10-olr}.zarr`
  serve as both init data and gt. They span **1983-07-02 to 2017-06-30T21:00** at 3H, so the earliest init is
  1983-07-04.
- Validated run: job 49118709 (`acc_debug`, 1 GPU), 1983-07-04 -> 2017-06-27, 1h18m, outputs in
  `/gpfs/scratch/bsc32/bsc930186/gt_sim/49118709/` (atmos 88 GB, ocean 1.4 GB); 48 sampled steps equal the gt
  stores (exact, or float32 round-off <= ~1e-7 relative).

## Gotchas

- `torch==1.13.0+cu117` (pinned in `uv.lock`) has no sm_90 kernels, so real GPU compute on MN5's H100 nodes
  stalls or fails. Gt models launch no kernels and are unaffected; trained models will need a newer torch.
- `ocean-forcing-model` is shared by the AIMIP forced-forecast scripts: do not repoint its `gt_dataset`
  for experiments, use `--ocean-gt-dataset`.
- Configs reference lab-machine paths (`/home/disk/...`, `/home/mercury2/...`); data dirs are normally passed on
  the command line (`--atmos-data-directory`, `--atmos-dataset-name`, ...).
