# 0014 — Sparse VHD not used; reclaim disk manually

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

`.wslconfig` originally set `sparseVhd=true`, on the reasoning that four distros with
duplicated image and package caches would otherwise grow without bound — WSL disks are
dynamically expanding but do not shrink when data is deleted, so a removed `node_modules`
never returns its space to Windows.

Creating `dev-work` produced this from WSL 2.7.11 before the install proceeded:

```
wsl: Sparse VHD support is currently disabled due to potential data corruption.
To force a distribution to use a sparse VHD, please run:
wsl.exe --manage <DistributionName> --set-sparse true --allow-unsafe
```

The setting is not merely ineffective — the feature has been disabled upstream, and the
only route to it is a flag explicitly named `--allow-unsafe`.

## Decision

Do not enable sparse VHD. The setting stays in `.wslconfig` commented out, with the
reason attached, so it is not silently re-added by someone who remembers it as a good
idea.

Reclaim space manually when a zone's disk has grown past what is comfortable:

```powershell
wsl --shutdown
diskpart
```

then, inside diskpart:

```
select vdisk file="C:\wsl\dev-work\ext4.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
```

Snapshot the zone first ([0012](0012-backup-and-snapshots.md)). This is an occasional
maintenance task, not something to schedule.

## Consequences

- Zone disks grow monotonically between compactions. Deleting a large `node_modules`
  frees space inside the zone but not on the Windows volume.
- The per-zone image duplication noted in [0004](0004-no-docker-desktop.md) is more
  expensive than that record assumed. Still the right trade — 382 GB free at the time of
  writing, and the isolation is the point — but the mitigation cited there is not
  available.

## Rejected alternatives

**`--set-sparse true --allow-unsafe`.** Microsoft disabled the feature over data
corruption. The data at stake is four zones of project work and environment state. Saving
disk on a machine with 382 GB free does not justify opting into a known corruption risk.

**`Optimize-VHD`.** Part of the Hyper-V PowerShell module, which is not available on
Windows 11 Home. `diskpart` is the equivalent that works here.

**Fixed-size VHDs.** Would make the ceiling explicit but wastes far more space up front.

## What would change this

WSL re-enabling sparse VHD by default in a later release, at which point the commented
line can simply be uncommented. Check the release notes rather than assuming — the flag
name is a strong signal that the risk was real.
