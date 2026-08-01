# 0004 — Docker runs inside each zone, not Docker Desktop

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Docker is needed for projects in the `work` zone. On Windows the
default answer is Docker Desktop, which runs the engine in its own hidden `docker-desktop`
distro and exposes it to the others through WSL integration.

That architecture means every integrated zone talks to the **same engine**: the same
images, volumes, containers and socket. A container started from `external` can mount a
volume created by `work`. Docker Desktop also publishes a root-equivalent API on the
Windows side.

Either property on its own would undermine [0001](0001-zone-isolation-model.md). Together
they make the zone boundary largely cosmetic wherever Docker is enabled.

## Decision

Install `docker-ce` from the official apt repository directly inside each zone that needs
it. Initially that is `dev-work` only; add others when a project actually requires it.

systemd is enabled in every zone (`[boot] systemd = true`), so the daemon is managed
normally. The engine, CLI and `docker compose` are the same software Docker Desktop
ships; the socket is a Unix socket inside the zone's own filesystem.

## Consequences

- Image caches are per-zone and therefore duplicated across zones. The lack of sharing
  is the point. Note that the mitigation originally assumed here — `sparseVhd`
  reclaiming space automatically — turned out to be unavailable; see
  [0014](0014-no-sparse-vhd.md). Space is reclaimed manually instead.
- No GUI dashboard. `lazydocker` covers most of what the dashboard is actually used for.
- Membership in the `docker` group is root-equivalent **within that zone**. It does not
  cross zones, but it means "docker access" and "root in this zone" are the same thing.
- Removes any question about Docker Desktop's commercial licence terms.

## Rejected alternatives

**Docker Desktop with WSL integration enabled only for `work`.** Better than enabling it
everywhere, but it still publishes the engine API host-side and still ties the zone's
container state to a Windows-managed component outside the boundary.

**Rootless Docker.** Genuinely better on the `docker`-group point above, at the cost of
networking and bind-mount quirks that cost time on real projects. Deferred rather than
rejected — see [0010](0010-deferred-hardening.md). Worth revisiting first if `external`
ever needs containers.

**Podman.** Daemonless and rootless by default, which fits this model well. Rejected for
now only because the projects in `work` are written against Docker and Compose, and
compatibility gaps would surface at the worst time. Reconsider on a greenfield project.

## What would change this

- `external` needing containers, which would make rootless or Podman worth the migration.
- A workflow genuinely requiring shared images across zones, which should first be
  challenged as a sign the zones are drawn wrong.
