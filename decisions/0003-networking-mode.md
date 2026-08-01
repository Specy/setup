# 0003 — Networking mode: NAT

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

`.wslconfig` offers `networkingMode = nat` (default) or `mirrored`. Mirrored folds WSL's
network namespace into the Windows one: `localhost` becomes shared in both directions.

**What mirrored gains:** LAN devices can reach a dev server running in WSL (phone testing
on a real device), better behaviour on VPNs and corporate DNS, IPv6. Windows reaching WSL
via localhost already works under NAT through `localhostForwarding`, so that is not a
gain.

**What mirrored costs:** anything bound to `127.0.0.1` on Windows becomes reachable from
inside every distro. The classic danger is the Docker Desktop engine API, which is
root-equivalent. That specific risk is removed by [0004](0004-no-docker-desktop.md),
which keeps the engine inside WSL behind a Unix socket.

`networkingMode` is global. It cannot be enabled for `personal` and left off for
`external`.

## The test that was open, and its result

The open question was whether WSL2 distros share a localhost with **each other**,
independent of Windows. Run on 2026-07-31 with `dev-work` and `dev-external`:

```
dev-work:      python3 -m http.server 8099 --bind 127.0.0.1
dev-external:  curl http://127.0.0.1:8099/canary.txt   ->  SECRET-FROM-DEV-WORK
```

The file served on loopback inside `dev-work` was read from `dev-external`. Further:

| Probe | Result |
| --- | --- |
| `hostname -I` in both zones | identical: `172.27.4.109` |
| Listener visible in the other zone's `ss -ltn` | yes |
| Rebinding the same port in the other zone | fails, address in use |
| `readlink /proc/self/ns/net` in both zones | identical: `net:[4026531833]` |

**All WSL2 distros share a single network namespace.** This is not a consequence of the
networking mode; it is true under NAT and would remain true under mirrored. It is
recorded as a constraint in [0015](0015-shared-network-namespace.md).

## Decision

Use `networkingMode = nat`.

Given that zone-to-zone loopback sharing exists either way, the choice reduces to a
single question: should Windows' own `127.0.0.1` also be exposed to every zone? Nothing
currently needs the mirrored-only capabilities, so the answer is no.

## What would change this

Needing LAN access to a dev server from a physical device, or a VPN that behaves badly
under NAT. Both are real reasons; neither applies today. Note that adopting mirrored
would widen [0015](0015-shared-network-namespace.md) to include the Windows host, so the
mitigations there become more important, not less.
