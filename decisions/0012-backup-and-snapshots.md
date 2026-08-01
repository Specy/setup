# 0012 — Git for code, `wsl --export` for environments

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Moving code into ext4 inside a zone ([0007](0007-code-on-ext4.md)) puts it inside a VHDX
that no Windows backup tool, OneDrive sync or File History touches. Two distinct things
need protecting and they need different mechanisms:

- **Code** — recoverable from GitHub, except for uncommitted work and unpushed branches.
- **The environment** — installed packages, shell config, `gh` logins, docker state,
  agent configuration. Recoverable only by re-running provisioning, which is exactly what
  this repository is for.

A third risk is specific to WSL: `wsl --unregister` deletes a distro and everything in it
immediately, with no recycle bin. It is one typo away from any other `wsl` command.

## Decision

Three layers, each covering what the others do not:

**1. Git remotes for code.** Push often. Treat unpushed work as unbacked-up work.

**2. This repository for the environment definition.** A zone should be reconstructible
from a clean distro by running `env/bootstrap.sh --zone <name>`, in roughly ten minutes.
Anything configured by hand and not captured here is a gap in the repo, not a reason to
back up the VHDX more carefully.

**3. `wsl --export` for point-in-time snapshots.**

```powershell
wsl --terminate dev-work
wsl --export dev-work D:\wsl-backups\dev-work-2026-07-31.tar
```

`wsl --import` restores it, optionally under a different name.

Use it for: snapshotting before a risky change, and cloning a configured base distro into
several zones rather than provisioning each from scratch.

## Consequences

- Distros are disposable. That is the goal: it makes experimenting cheap and removes the
  fear that motivates hoarding local state.
- Snapshots are multi-gigabyte and machine-specific, so they are excluded by
  `.gitignore` and stored outside this repository.
- Terminate the distro before exporting, or the snapshot is crash-consistent rather than
  clean.
- An export contains credentials from that zone. Treat the `.tar` with the same care as
  the zone itself; do not put it in cloud storage unencrypted.

## Rejected alternatives

**Backing up the VHDX files directly.** They are locked while the distro runs and there
is no consistency guarantee. `wsl --export` is the supported path.

**Relying on snapshots instead of provisioning scripts.** A snapshot restores a machine
but explains nothing and drifts immediately. The scripts are the source of truth; the
snapshot is a convenience.

## What would change this

Provisioning a zone growing past roughly ten minutes would make snapshot-based cloning
the primary path rather than a convenience.
