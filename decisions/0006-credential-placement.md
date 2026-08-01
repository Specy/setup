# 0006 — VPS key on the host, GitHub over HTTPS per zone

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

The original plan was to keep SSH private keys on Windows and forward the agent socket
into each zone, so a compromised zone could *use* a key while active but never exfiltrate
it. The standard mechanism for that is `npiperelay.exe` bridged to a Unix socket with
`socat` — which requires executing a Windows binary from Linux, i.e. interop.

[0002](0002-wsl-conf-hardening.md) disables interop precisely because it is the
zone-to-zone pivot. Re-enabling it to gain theft-resistance on a key would trade a strong
boundary for a weaker one.

The actual requirement turned out to be narrow: SSH is only used to hand-connect to a VPS.
No zone needs to make SSH connections at all.

## Decision

**VPS SSH key lives on the Windows host only.** Connect from Windows Terminal using the
built-in OpenSSH client. No zone holds the key, so no zone can reach the VPS — including
`work`.

**GitHub access inside zones uses HTTPS tokens via `gh auth login`**, not SSH keys.

| Zone | GitHub auth | git identity |
| --- | --- | --- |
| `dev-work` | own token | `Your Name <you@example.com>` |
| `dev-personal` | own token | `Your Name <you@example.com>` |
| `dev-external` | **none** — anonymous HTTPS clones | same, for local commits |
| `Ubuntu-26.04` | none | none |

No SSH keys in any dev zone.

### Correction, 2026-07-31

This record originally assumed `work` and `personal` were separate GitHub accounts, and
claimed the split meant "a compromise in one zone yields credentials for that zone only".
**They are the same account**, so that claim was wrong and is withdrawn.

What the arrangement still buys:

- Each zone holds a **separate token** for that one account. Tokens are independently
  revocable, so burning `work`'s does not disturb `personal`.
- `external` holds nothing at all, which is the case that matters most.
- The VPS remains unreachable from every zone.

What it does not buy: a token stolen from `work` grants the same repository access as one
stolen from `personal`, because it is one account with one set of permissions. Zone
isolation still separates **source, filesystems and processes** — it no longer separates
*what GitHub access is possible* between those two zones.

If that separation is wanted later, the route is fine-grained PATs scoped to specific
repositories per zone, rather than the broad OAuth token `gh auth login` issues. That is
a per-zone `gh auth login --with-token` and a scoping decision, not a restructure.

### Resolution, same day

That route was taken immediately. Two fine-grained PATs were issued against the one
account, each with a different **repository selection** — the work repositories for
`dev-work`, personal repos for `dev-personal` — both with a one-year expiry.

Separation is therefore restored, and by a stronger mechanism than the original
assumption of two accounts: the boundary is now per-repository rather than per-account.

Measured rather than assumed:

```
dev-work:      gh api repos/<you>/setup  ->  404 Not Found
dev-personal:  gh api repos/<you>/setup  ->  <you>/setup
```

A compromise in one zone cannot reach the other zone's repositories. `verify.sh` asserts
that `work` and `personal` are authenticated and that `external` is not; the repository
scoping itself is enforced by GitHub and is not something the machine can check.

The exact permission set is recorded in [SECRETS.md](../SECRETS.md), including the
non-obvious one: **Workflows: write** is required to push any commit touching
`.github/workflows/`, and its absence rejects an otherwise-ordinary push.

One practical consequence: `setup` sits in the personal selection, so `dev-work` cannot
pull this repository. It stays that way. Widening the work token to reach an
infrastructure repo would weaken the separation for a reason unrelated to any project.

Instead, zones other than `personal` are provisioned by pushing from the host with
`hosts/windows/provision-zone.ps1`. That is the better arrangement regardless of tokens:
`external` never receives a checkout of a repository it has no business holding, and the
provisioning source of truth stays on the host rather than being duplicated into three
zones that can drift.

## Consequences

- Compartmentalisation comes from the distro boundary rather than from agent forwarding.
  A compromise in `external` yields no credentials at all; a compromise in `work` yields
  a revocable, scopeable GitHub token and nothing that reaches the VPS.
- Tokens are revocable from a web UI in seconds. A stolen private key is a worse day.
- If a zone ever needs to push over SSH, that is a deliberate change, not a default.

## Rejected alternatives

**Agent forwarding via npiperelay.** Requires interop. See above.

**A separate SSH key per zone.** This was the previous plan and is strictly more setup
for no benefit given no zone needs SSH.

**One shared key across zones.** Defeats the model entirely.

## What would change this

- Buying a hardware key. FIDO2 `ed25519-sk` keys cannot be copied off the device and
  require a physical touch, which is better than both options here. Note it needs
  `usbipd-win` for USB passthrough into WSL, so it is real setup rather than a drop-in.
- A zone genuinely needing to reach a remote host, which should first be questioned as a
  sign that work is happening in the wrong place.
