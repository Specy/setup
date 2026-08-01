# 0001 — Isolation granularity is the trust zone, not the project

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

The goal is that a supply-chain compromise — a malicious npm `postinstall`, a poisoned
transitive dependency, a hostile repository handed to an agent — cannot reach anything
beyond the thing it compromised. The question is what "beyond" means: per project, per
category of project, or per machine.

Projects were already informally grouped as personal, work and external. Those groups
turn out to correspond to *credential scope*, which is what an attacker is actually
after. Nobody wants your `node_modules`; they want the token sitting next to it.

## Decision

One WSL2 distro per trust zone. Four total:

| Zone | Distro | Contents |
| --- | --- | --- |
| `daily` | `Ubuntu-26.04` | General Linux use, tinkering, learning |
| `work` | `dev-work` | work projects, docker |
| `personal` | `dev-personal` | `personal/` projects |
| `external` | `dev-external` | Third-party and untrusted code, agent sandbox |

Each distro has its own ext4 filesystem, its own users, and its own credentials. Nothing
is shared between them by default.

Per-project isolation is a *second, optional* layer applied inside a zone — bubblewrap
sandboxing for running untrusted build steps — and is only worth its friction in
`external`.

## Rejected alternatives

**A distro per project.** Each WSL distro is a multi-gigabyte VHDX with its own apt tree
and its own set of updates. A dozen of them would be unmaintainable, would drift apart,
and the disk cost is real. The security gain over zone isolation is small because
projects within a zone already share the credentials that matter.

**One distro for everything.** This is the status quo of a normal dev machine and
provides no boundary at all: every project can read every token.

**Full VMs per zone.** Stronger isolation, considerably more overhead in RAM, disk and
day-to-day friction. Disproportionate to the threat — see limits below.

**Containers (devcontainers) as the primary boundary.** Good for reproducibility, which
is explicitly a non-goal here. Container escape and the shared daemon make it a weaker
boundary than a separate distro, for more configuration work.

## Limits of this model

All WSL2 distros run inside a single utility VM and share one kernel. So:

- **WSL to Windows** is a genuine Hyper-V boundary. Strong.
- **Zone to zone** is namespace-based, comparable to container isolation. Good, but not
  VM-grade.
- **Zone to zone on the network: no boundary at all.** Measured after this record was
  written — every distro shares one network namespace, so any service on loopback in one
  zone is reachable from all of them. See
  [0015](0015-shared-network-namespace.md), which this record should be read alongside.

This addresses the realistic threat — dependency code stealing credentials, source and
browser data, or pivoting between projects — because those all travel through the
filesystem, which *is* separated. It does not address a kernel exploit, and it does not
separate the network. If something ever genuinely requires absolute separation, that
needs a real VM, not another distro.

## What would change this

- A project that must be isolated from everything else in its own zone, at which point
  it earns its own distro or a real VM.
- WSL gaining supported per-distro VM isolation, which would upgrade the zone-to-zone
  boundary for free.
