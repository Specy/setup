# 0017 — GitHub CLI from GitHub's apt repository, not Ubuntu's archive

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

The zones are bare Ubuntu 26.04 images with no tooling. `gh` is needed in `work` and
`personal` to authenticate to GitHub over HTTPS
([0006](0006-credential-placement.md)).

Ubuntu's archive carries `gh` **2.46.0-4**. The current release is **2.97.0** — roughly
two years of drift. For most packages that would be unremarkable; for `gh` it is not:

- it stores and refreshes OAuth tokens
- it talks to a live API whose behaviour and deprecations move
- it is itself part of the credential path this setup depends on

Running a two-year-old version of the tool that holds your tokens is a cost, not a
neutral choice.

## Decision

Add GitHub's official signed apt repository in the zones that need `gh`, and install from
there. Implemented in `env/packages.sh`:

- keyring pinned at `/etc/apt/keyrings/githubcli-archive-keyring.gpg`
- source line uses `signed-by=` so the key authorises **only** this repository
- idempotent: re-running configures nothing and reports no changes

`external` and `daily` do not get `gh` at all — they hold no GitHub credentials, so the
tool has nothing to do there. Result: `gh 2.97.0`, matching the host.

## Why this does not contradict 0011

[0011](0011-toolchain-management.md) rules out `curl | bash`, and this is a different
thing. A signed apt repository is verifiable, pinned to a specific key, updated through
the normal package manager, and removable by deleting two files. `curl | bash` executes
unreviewed code fetched at run time with no signature check and no record of what it did.

The objection to `curl | bash` is the absence of verification, not the presence of a
third-party source.

## Rejected alternatives

**Ubuntu's `gh` 2.46.0.** One fewer trust root, but two years stale on a
credential-handling tool. If GitHub's repo ever became unavailable this is the fallback,
and it would work.

**Installing `gh` via mise.** mise can do it, but that routes a security-relevant binary
through a version manager rather than the system package manager, and it would not be
covered by unattended `apt` security updates.

**Downloading the release binary directly.** Manual verification, manual updates, and no
integration with anything. Strictly worse than a signed repo.

## Consequences

- One additional trust root, `cli.github.com`, in `work` and `personal` only.
- `gh` now updates with normal `apt upgrade`.
- If GitHub rotates the signing key, `apt update` fails loudly in those zones. That is the
  correct failure mode; the fix is re-running `env/packages.sh`, which re-fetches the
  keyring.

## What would change this

Ubuntu shipping a current `gh`, which would make the extra trust root unnecessary.
