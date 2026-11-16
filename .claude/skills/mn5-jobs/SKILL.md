---
name: mn5-jobs
description: Submit, monitor, read logs of, and cancel Slurm jobs on MareNostrum5 (sbatch, squeue, sacct, job logs, failures). Use when the user asks to run something on MN5, check a job, or look at remote output/logs. Load mn5-remote first.
---

# Slurm jobs on MN5

Repo root on MN5: `R=/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026`. CPU jobs are submitted from `mn5_gpp`, GPU jobs from `mn5`.
Batch scripts live in the repo (`testing/scripts/mn5/*.sbatch`) and reach MN5 via the **mn5-deploy** skill — never edit files on MN5 by hand, and make sure the code on MN5 is the commit you intend before submitting.

## Submit (asks the user for approval each time)
```
ssh mn5_gpp sbatch --chdir=/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026 testing/scripts/mn5/gt_simulation.sbatch
```
- GPU variant: `ssh mn5 sbatch --chdir=<repo> testing/scripts/mn5/gt_simulation_acc.sbatch` (submit from `mn5`/alogin1; QoS `acc_debug`, max 2h and only ONE submitted job per user at a time; 1 GPU + 20 cores; device 0). It fails fast if CUDA is unavailable rather than falling back to CPU. Both wrappers share `gt_simulation_common.sh`.
- Override via flags *before* the script path: `--qos=gp_bsces --time=48:00:00 --export=ALL,INIT=...,END=...,OUTPUT_DIR=...`. Flags override the `#SBATCH` lines.
- `--chdir` is required since the ssh command can't `cd`; the job's logs go to `<repo>/logs/gt_simulation/<jobid>.out` (dir is tracked via `.gitkeep`).
- First submission of any new/changed script: use the default `gp_debug` 2h QoS (short queue, high priority) as a smoke test before a long run. Say what you are about to submit (script, QoS, time, overrides, commit hash on MN5) before running it.
- Output is `Submitted batch job <ID>`: record the ID and tell the user.

## Monitor
- Queue: `ssh mn5_gpp squeue -u bsc930186 -o %i,%P,%T,%M,%l,%R` (add `-j <ID>`). Pending reason is in `%R`. Keep the `-o` format free of spaces/quotes: ssh re-splits the remote command, so a quoted format string breaks (`Unrecognized option`).
- Finished/failed: `ssh mn5_gpp sacct -j <ID> --format=JobID,JobName,State,ExitCode,Elapsed,MaxRSS,NodeList -X`.
- Details: `ssh mn5_gpp scontrol show job <ID>`.
- Don't poll in a tight loop. Check at sensible intervals (use the harness's wait/loop facilities if available); a pending debug job usually starts in minutes, a 48h `gp_bsces` job may queue for hours.

## Logs
- Tail: `ssh mn5 tail -n 80 /gpfs/.../logs/gt_simulation/<ID>.out`
- Errors: `ssh mn5 grep -n -i -E "error|traceback|killed|oom" <file>` (grep -E patterns with `|` need the quoting above; keep it in one ssh arg list).
- The simulation prints a tqdm bar with the current init/step; carriage returns make `tail` lines long — filter with `| tr '\r' '\n' | tail -n 5` locally.
- Outputs: `ssh mn5 ls -lh <OUTPUT_DIR>`; size check `ssh mn5 du -sh <dir>`.

## Diagnose failures (common ones here)
- `State=TIMEOUT`: raise `--time`/QoS, or split the run; the hdf5 cache restarts from scratch each run.
- `OUT_OF_MEMORY` / `Killed`: add `--mem=...` or fewer chunks (`--step-chunk`).
- `ModuleNotFoundError`/uv trying to download: compute nodes are offline; the `.venv` is out of sync with `uv.lock`. Fix on `mn5_4` (user-approved `uv sync --frozen` there), then resubmit.
- `FileNotFoundError` on gt zarr / init data: gt paths are in `models/*-forcing-model/.hydra/config.yaml` (`model.gt_dataset`); init data via `ATMOS_DATA_DIR`/`OCEAN_DATA_DIR`. Check the path exists with `ssh mn5 ls`.
- Quota: `ssh mn5 bsc_quota` (shared group scratch quota is nearly full — check before a ~200 GB write).

## Cancel
`ssh mn5_gpp scancel <ID>` asks for approval; only cancel jobs this session submitted unless the user names the job.
