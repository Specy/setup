# 0011 — mise for runtimes, uv for Python

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Language runtimes need to be installed per zone and pinned per project. The default
routes — distro packages, or the `curl | bash` installer each ecosystem ships — are
either too coarse or are themselves an unreviewed remote-code-execution step repeated for
every toolchain.

## Decision

**mise** manages runtime versions (Node, Python, Go, and others). A `mise.toml` in a
repository declares its versions and `cd`ing into the directory activates them. This
replaces nvm, pyenv and asdf with a single binary, and removes the per-toolchain
`curl | bash`.

**uv** manages Python packages, virtual environments and lockfiles.

Neither is load-bearing for security. Both are adopted for speed and for removing sharp
edges.

## Caveats worth knowing

**mise uses shims.** Tools that shell out to `node` by absolute path can occasionally be
confused by this. Rare, but the symptom is baffling if the cause is unknown.

**`mise.toml` is executable configuration.** It can define environment variables and
tasks, so a cloned repository carries config that mise will act on. mise prompts for
`mise trust` before honouring a directory. **Do not reflexively approve that prompt in
`dev-external`** — it is a supply-chain surface, and the prompt is the control.

**uv prefers wheels but will build source distributions** when no wheel exists, which
executes the package's build script. It reduces install-time code execution rather than
eliminating it. `--only-binary :all:` would eliminate it; see
[0010](0010-deferred-hardening.md) for why that is deferred.

**mise occasionally lags** a few days behind a brand-new runtime release.

## Rejected alternatives

**Distro packages only (`apt install nodejs`).** One version per zone, no per-project
pinning. Works until two projects disagree.

**nvm plus pyenv plus asdf.** Three tools, three shell hooks, three failure modes, and
each installed by piping a remote script to a shell.

**Nix or devbox.** Stronger reproducibility guarantees, which is explicitly a non-goal —
these are local development environments and reusability was not a requirement. The
learning curve is not repaid here.

## What would change this

A project requiring a runtime mise does not support, which would mean handling that one
by hand rather than changing the general approach.
