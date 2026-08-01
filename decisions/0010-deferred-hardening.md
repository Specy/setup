# 0010 — Deliberately deferred hardening

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Several measures were considered and consciously not adopted. Recording them prevents two
failure modes: rediscovering them as though they were new ideas, and adopting them later
without remembering why they were skipped.

Each entry states the trigger that should cause a revisit.

## Deferred

### Encrypted `.env` via sops + age

Encrypts secrets at rest, decrypting into the process environment only at run time. The
zone boundary already limits how far a leaked key travels, and this is meaningful setup
and daily friction for a solo developer.

**Revisit when:** holding production credentials whose leak would cost real money, or
sharing a repository with collaborators who need different secrets.

Until then: `.env` in `.gitignore`, plaintext, confined to its zone.

### Hardware security key

FIDO2 keys resist phishing in a way no other second factor does — relevant because the
npm supply-chain compromises began with maintainer phishing rather than a technical
exploit. Also enables `ed25519-sk` SSH keys whose private half cannot be copied off the
device.

**Revisit when:** the key is purchased. Note WSL needs `usbipd-win` for USB passthrough,
so in-WSL use is real setup rather than a drop-in.

### pnpm with `minimumReleaseAge`

The cooldown control that blocks fast-moving npm worms during their effective window.
See [0005](0005-npm-ignore-scripts.md) for why the migration is deferred.

**Revisit when:** migrating any project to pnpm. Do it per project, not in a sweep.

### Rootless Docker or Podman

Removes the "docker group is root in this zone" property from
[0004](0004-no-docker-desktop.md).

**Revisit when:** `external` needs containers, or on a greenfield project where Compose
compatibility is not already assumed.

### Per-project bubblewrap sandboxing outside `external`

A second isolation layer inside a zone. Worth its friction where code is untrusted;
mostly noise where it is not.

**Revisit when:** a `work` or `personal` project starts pulling dependencies that warrant
the same suspicion as `external` code.

### uv `--only-binary :all:`

Forces wheel-only Python installs, refusing to build source distributions and thereby
refusing to execute their build scripts. Fails loudly on sdist-only packages.

**Revisit when:** a Python project's dependency set is stable enough that the failures
would be rare and informative rather than constant.

## What would change this

Each entry carries its own trigger. When one fires, write a new record adopting the
measure and mark the entry here as superseded.
