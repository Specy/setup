# Decisions

One record per real decision: what was chosen, what was rejected, and what would change
it. Append-only — superseding a record means writing a new one and marking the old one
`Superseded by NNNN`, never editing it to say something different.

Read these before changing configuration. Several settings look like oversights until you
know why they are there.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-zone-isolation-model.md) | Isolation granularity is the trust zone, not the project | Accepted |
| [0002](0002-wsl-conf-hardening.md) | Dev zones do not mount or execute Windows | Accepted |
| [0003](0003-networking-mode.md) | Networking mode: NAT | Accepted |
| [0004](0004-no-docker-desktop.md) | Docker runs inside each zone, not Docker Desktop | Accepted |
| [0005](0005-npm-ignore-scripts.md) | npm with lifecycle scripts disabled; pnpm deferred | Accepted |
| [0006](0006-credential-placement.md) | VPS key on the host, GitHub over HTTPS per zone | Accepted |
| [0007](0007-code-on-ext4.md) | Project code lives on ext4 inside the zone | Accepted |
| [0008](0008-agent-execution-boundary.md) | Agents must execute inside the zone | Accepted |
| [0009](0009-smart-app-control.md) | Smart App Control left in evaluation mode | Accepted |
| [0010](0010-deferred-hardening.md) | Deliberately deferred hardening | Accepted |
| [0011](0011-toolchain-management.md) | mise for runtimes, uv for Python | Accepted |
| [0012](0012-backup-and-snapshots.md) | Git for code, `wsl --export` for environments | Accepted |
| [0013](0013-repo-layout.md) | Split by host bootstrap vs portable environment | Accepted |
| [0014](0014-no-sparse-vhd.md) | Sparse VHD not used; reclaim disk manually | Accepted |
| [0015](0015-shared-network-namespace.md) | Zones share one network namespace; the boundary is filesystem, not network | Accepted |
| [0016](0016-systemd-user-manager.md) | Each zone needs a distinct uid | Accepted |
| [0017](0017-github-cli-source.md) | GitHub CLI from GitHub's apt repository, not Ubuntu's archive | Accepted |
| [0018](0018-docker-in-work-zone.md) | Docker CE in `dev-work`, from Docker's own repository | Accepted |
| [0019](0019-rust-via-rustup.md) | Rust via rustup, not mise | Accepted |
| [0020](0020-session-history-migration.md) | Agent history follows the project into its zone | Accepted |
| [0021](0021-zed-remote-servers-mount.md) | A single read-only drvfs mount for Zed, not automount | Accepted |

## Format

```markdown
# NNNN — Title in the imperative or as a statement

- **Status:** Accepted | Open | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
What forced a choice. Include the constraint that makes the obvious answer wrong.

## Decision
What was chosen, concretely enough to implement.

## Rejected alternatives
Each with the reason. This is the section that stops the decision being relitigated.

## What would change this
The trigger to revisit. Prevents both dogma and drift.
```

Records marked **Open** carry an explicit question and, where possible, the test that
would answer it. They are the backlog — not TODO comments buried in scripts.
