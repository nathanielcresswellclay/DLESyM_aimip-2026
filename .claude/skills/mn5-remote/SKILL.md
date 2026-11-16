---
name: mn5-remote
description: Facts and ground rules for working on the MareNostrum5 (MN5) supercomputer over ssh. Load before ANY ssh/rsync/scp to MN5, or when the user mentions MN5, MareNostrum, BSC, mn5, alogin/glogin, or running things "on the cluster".
---

# MareNostrum5 remote access

## Which node for what (ssh aliases live in ~/.ssh/config, key auth, no password prompts)
| alias | host | use for |
|---|---|---|
| `mn5_gpp` | glogin1 | **Submit/monitor CPU jobs** (general-purpose partition, QoS `gp_*`). No internet. |
| `mn5` | alogin1 | Submit/monitor GPU jobs (accelerated partition, QoS `acc_*`), read-only inspection. No internet. |
| `mn5_4` | alogin4 | **The ONLY node with internet.** `git pull`, `git lfs`, `uv sync`/package downloads. Never run compute or interactive work here. |
| `mn5_trans4` | transfer4 | Bulk data movement / `ls`/`du` on storage. No GitHub access. |

Compute nodes have no internet either, so anything needing the network (git, pip/uv downloads) must be done beforehand on `mn5_4`.
`mn5_4`/`mn5_trans`/`nord4` other than the allow-listed git commands will prompt the user; `mn5_trans`, `nord4` and `rm` over ssh are denied. Never route around a deny (e.g. `ssh mn5 ssh alogin4`).

## Fixed facts
- user `bsc930186`, Slurm account `bsc32`; QoS: `gp_debug` (max 2h), `gp_bsces` (max 48h), `gp_interactive` (2h); GPU: `acc_debug`, `acc_bsces`, `acc_interactive`.
- Repo on MN5: `/gpfs/scratch/bsc32/bsc930186/DLESyM_aimip-2026` (same GitHub remote, uv `.venv` already built, Python 3.10, `module load uv` = 0.10.11).
- Data: `/gpfs/scratch/bsc32/bsc930186/agu_advances_2025/` (atmos init zarr `hpx64_1983-2017_3h_9varCoupledAtmos-sst.zarr`; ocean init is still a `.tar` there and in `data/isccp/` and must be extracted before use), `/gpfs/scratch/bsc32/bsc930186/data/`.
- Storage: scratch/projects are shared group quotas (check with `ssh mn5 bsc_quota`); home is small (80 GB). Large outputs go to scratch.
- Login nodes are shared: no heavy work, no long-running processes, no python runs beyond trivial checks. Real work goes through Slurm.

## Command-writing rules (so permission rules match and prompts stay rare)
- Permissions are prefix-matched on the literal command. Write `ssh mn5_gpp squeue -u bsc930186`, NOT `ssh mn5_gpp 'cd x && squeue'`. One simple remote command per call; avoid `&&`, `;`, pipes inside the ssh string (pipe locally instead: `ssh mn5 tail -n 80 FILE | grep ...`).
- Auto-allowed read-only: `squeue sacct sinfo scontrol show ls cat head tail grep du` on mn5/mn5_gpp, `ls du` on mn5_trans4, and `git -C <repo> status|fetch|log|branch|diff|lfs|pull --ff-only|checkout` on mn5_4.
- Always ask-first (the user is prompted): `sbatch`, `scancel`, `rsync`, `scp`. Do not try to bypass.
- Ssh stdout begins with module-load noise (`load bsc/1.0 ...`); ignore it or `| grep -v '^load '`.
- Use `ssh -o BatchMode=yes` when probing so a key/auth problem fails fast instead of hanging.

## Safety
- Never delete, overwrite or move remote files without the user's explicit OK, and look at the target first. No `rm` over ssh (denied).
- Don't print or copy private keys, tokens or the contents of `~/.ssh` / shell history.
- Report outcomes as they are: failed job, missing file, quota problem — with the actual output.
