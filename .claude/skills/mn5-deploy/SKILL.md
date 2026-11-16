---
name: mn5-deploy
description: The edit-on-workstation, push-to-GitHub, pull-on-MN5, submit loop for the DLESyM repo, including git/gh usage and getting results or logs back. Use when the user wants to run code changes on MN5, "push and run", sync the repo, or iterate on a remote job.
---

# Workstation -> GitHub -> MN5 loop

Workstation repo: `/home/ncresswe/Desktop/DLESyM_aimip-2026`. MN5 repo: `/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026`. GitHub: `nathanielcresswellclay/DLESyM_aimip-2026` (`gh` is authenticated; `origin` over https).
The working copy on MN5 is **read-only for us**: all edits happen on the workstation. Only `git pull --ff-only` on MN5.

## Loop
1. **Edit & test locally.** Use `uv run --frozen ...` (see `testing/scripts/coupled_forecast_gt_1983-2017.sh`). Smoke-test on `example_data` before involving MN5.
2. **Commit & push — only when the user asks** (or has said "push and run" for this task). Branch: never commit to `main`; use the current feature branch. Commit message ends with the Co-Authored-By line from the session reminder. Check `git status` first: don't commit `.claude/settings.local.json`, data, outputs, or unrelated user edits; stage files by name. Push: `git push -u origin <branch>`. Model checkpoints under `models/**` are Git LFS, so pushes of new ones need `git-lfs` (installed locally).
3. **Pull on MN5 via the internet node** (auto-allowed):
   ```
   ssh mn5_4 git -C /gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026 fetch origin
   ssh mn5_4 git -C /gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026 checkout <branch>
   ssh mn5_4 git -C /gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026 pull --ff-only
   ssh mn5_4 git -C /gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026 log --oneline -3
   ```
   Confirm the remote HEAD hash equals the local `git rev-parse --short HEAD` before submitting. If `pull --ff-only` fails or `status` shows tracked modifications on MN5, STOP and tell the user — do not reset/force/stash on their cluster checkout. Untracked files there (e.g. analysis pngs) are the user's; leave them.
4. **Environment changes.** If `pyproject.toml`/`uv.lock` changed, the MN5 `.venv` must be re-synced on `mn5_4` (the only node with internet): `ssh mn5_4 ...uv sync --frozen --project <repo>` (not pre-approved: the user is prompted; explain why). Compute nodes always use `uv run --no-sync`.
5. **Submit and watch** with the **mn5-jobs** skill; then read logs, fix locally, go to step 1.
6. **Bring results back only if needed.** Prefer analysing in place on MN5 (outputs are ~100 GB). For small files: `rsync -avP mn5_trans4:<remote path> <local dir>` (asks the user first). Never pull the full simulation output without confirming disk space (`df -h /home`; the workstation has ~330 GB free).

## GitHub (gh)
- `gh pr create` / `gh pr view` / `gh run list` for PRs and CI when asked. PR bodies end with the attribution line from the session reminder. Do not merge or force-push without explicit instruction.
- Never put the user's email/name into external requests beyond what git/gh already do.

## What lives where
- Batch scripts: `testing/scripts/mn5/*.sbatch` (tracked, submitted from the MN5 checkout).
- Per-run settings are passed with `sbatch --export=ALL,VAR=...`, not by editing files on MN5.
- Machine-specific data paths (gt zarr, init data) for MN5 should be set via env overrides or the model configs committed on the branch — record the chosen paths in the commit message.
