# 0007 — Project code lives on ext4 inside the zone

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Code currently sits at `C:\Users\<you>\Desktop\projects\`. Working on Windows-hosted
files from WSL means going through `/mnt/c`, which is a protocol translation layer
between two filesystems with very different semantics. Anything performing many small
file operations — `node_modules` installs, `git status` on a large repository,
TypeScript builds, test watchers — pays a per-operation cost. It is the single largest
performance difference in WSL and it is not subtle.

Separately, [0002](0002-wsl-conf-hardening.md) disables `automount` in the hardened
zones, so `/mnt/c` does not exist there. The question is settled by security before
performance even enters.

## Decision

All project code lives at `~/code/` inside its zone, on the zone's own ext4 filesystem.

| Was | Becomes |
| --- | --- |
| `Desktop\projects\work\` | `dev-work:~/code/` |
| `Desktop\projects\<group>\` | `dev-work:~/code/` |
| `Desktop\projects\personal\` | `dev-personal:~/code/` |
| `Desktop\projects\external\` | `dev-external:~/code/` |

Everything is re-cloned fresh from GitHub rather than copied, so no Windows-side state,
line endings or `node_modules` come along.

This repository is the exception: it stays on the Windows host at
`Desktop\projects\setup`, because it must be reachable on a fresh machine before any WSL
distro exists.

## Access paths

- **VS Code** — Remote-WSL. Open the folder inside the distro; the server runs in the
  zone and it feels local.
- **Windows Explorer** — `\\wsl.localhost\dev-work\home\dev\code`. Works for drag and
  drop. This is Windows reading WSL, the safe direction.
- **Terminal** — a Windows Terminal profile per zone, landing in `~/code`.

## Consequences

Code is now inside a VHDX that no Windows backup tool, OneDrive sync or File History
touches. Git remotes cover committed work; the environment itself is covered by
`wsl --export` snapshots — see [0012](0012-backup-and-snapshots.md).

## What would change this

Nothing foreseeable. Working from `/mnt/` would mean giving up both the performance and
the isolation.
