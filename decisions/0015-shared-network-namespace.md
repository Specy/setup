# 0015 — Zones share one network namespace; the boundary is filesystem, not network

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Measured on 2026-07-31 while resolving [0003](0003-networking-mode.md). Every WSL2 distro
on this machine runs in the **same network namespace**:

- `readlink /proc/self/ns/net` returns `net:[4026531833]` in every zone
- every zone reports the same IP from `hostname -I`
- a listener bound to `127.0.0.1` in `dev-work` was fetched from `dev-external`
- that listener appears in `dev-external`'s own `ss -ltn` output
- the port cannot be re-bound in another zone

This is a property of WSL2's architecture, not of any setting in this repo, and it holds
under both networking modes.

## What this means

The zone boundary from [0001](0001-zone-isolation-model.md) is real for **filesystems,
users, credentials and processes**. It does **not** exist for the network.

Concretely: a Postgres container in `dev-work` published on `localhost:5432` is reachable
from `dev-external` — the least trusted zone — with no authentication beyond the
database's own. Any service anyone binds to loopback anywhere is effectively bound for
all four zones at once.

There is also a mundane consequence that will be met sooner: **ports collide across
zones.** Two zones cannot both run a dev server on `:3000`.

## Decision

Accept the constraint and design around it. Specifically:

1. **Prefer Unix sockets to TCP** for anything that does not need a network. Docker's
   own socket is a filesystem object inside the zone and is therefore correctly
   isolated — one more reason [0004](0004-no-docker-desktop.md) is right.
2. **Assume every service you run is reachable from `external`.** Not "if you publish a
   port" — always. Anything holding data that matters needs its own authentication,
   because the zone boundary will not supply it. A database with a real password is fine;
   a database trusting `127.0.0.1` is not.
3. **Allocate port ranges per zone** to avoid collisions: `work` 3000–3999,
   `personal` 4000–4999, `external` 5000–5999. This is about ports colliding, not
   security — it buys no isolation.

### Correction, 2026-07-31 — "do not publish ports" does not work

This record originally advised not publishing container ports, on the reasoning that an
unpublished container is only reachable inside its Compose network. **That is wrong**, and
was measured after Docker was installed in `dev-work`:

```
dev-work:      docker run -d --rm nginx:alpine        (no -p flag at all)
               container IP 172.17.0.2
dev-external:  curl http://172.17.0.2/            ->  HTTP 200
```

`dev-external` also sees `docker0` directly at `172.17.0.1/16`.

The docker bridge is created in the **shared** network namespace, so every zone can route
to every container in every other zone regardless of port publishing. Publishing a port
adds a loopback listener; not publishing one changes nothing about cross-zone
reachability. The advice has been removed rather than softened, because following it
would have produced a false sense of protection.

User-defined and `internal` Compose networks do not help either — their bridges live in
the same shared namespace.

## Rejected alternatives

**Per-distro network namespaces.** Not offered by WSL. This is the fix that would
actually resolve it and it is not available.

**Firewall rules inside each zone.** They share the namespace, so they share the
netfilter tables — a rule added in one zone is not a rule "for" that zone. This does not
work the way it first appears to.

**Owner-matched iptables rules.** One variant might actually work, and is recorded here
so it is not rediscovered from scratch. Cross-zone traffic is locally generated, so it
traverses `OUTPUT`, where iptables' `owner` match applies — and since
[0016](0016-systemd-user-manager.md) each zone now has a distinct uid:

```
iptables -I OUTPUT -d 172.17.0.0/16 -m owner --uid-owner 1003 -j REJECT
```

would stop `external` reaching the docker bridge. Not adopted: the rules live in shared
netfilter tables that any zone's root can flush, they need maintaining as networks change,
and they would give a stronger impression of isolation than they actually deliver.
Authentication on the service is the honest control.

**Binding services to a zone-specific address.** There is one interface with one address.
Nothing to bind distinctly.

**Moving to full VMs per zone.** Would solve it, at the cost rejected in
[0001](0001-zone-isolation-model.md). Reconsider only if something genuinely requires
network isolation between zones.

## What would change this

WSL gaining per-distro network namespaces. Worth re-testing with
`readlink /proc/self/ns/net` after major WSL updates — the test is one command and the
answer changes the model.
