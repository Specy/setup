# 0013 — Split by host bootstrap vs portable environment

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

A native Linux dual boot is planned. The obvious top-level split for a repo serving both
is `windows/` and `linux/`, but that would duplicate almost everything: shell config, git
config, mise, npm settings, docker, agent configuration and the deny-lists are identical
whether the Linux in question is a WSL distro or a native install.

The genuine difference is narrow — how the environment is *created* and how the host
around it is configured.

## Decision

```
hosts/          OS-specific bootstrap. The thin part.
  windows/      .wslconfig, winget manifest, Terminal profiles, zone creation
  linux/        Native Linux bootstrap
env/            Everything inside a Linux environment. Portable.
decisions/      Rationale. Append-only.
verify/         Assertions that reality matches this repo.
```

**Rule:** anything under `env/` must work on native Linux as well as inside WSL. WSL
specifics belong in `hosts/windows/`.

`env/bootstrap.sh --zone <name>` is the single entry point for configuring an
environment, and is the same command on both platforms.

## Consequences

- The dual boot reuses `env/` unchanged. That is the entire payoff and it only holds if
  the rule above is enforced when adding files.
- Some judgement is needed at the margin. Zone naming, for instance, is conceptual and
  lives in `env/`; creating a distro is a WSL operation and lives in `hosts/windows/`.
- `verify/` is shared and must skip WSL-specific assertions when running on native Linux.

## Rejected alternatives

**Top-level `windows/` and `linux/`.** Duplicates the majority of the content and
guarantees the two copies diverge.

**A dotfiles manager (chezmoi, yadm) with templating.** Solves a real version of this
problem, but adds a templating language and a tool to learn for a repo whose main value
is the runbooks and decision records rather than file distribution. Reconsider if `env/`
grows a lot of per-zone conditional content.

**Ansible or similar.** Disproportionate for four environments on one machine, and the
declarative model fights the interactive steps (`gh auth login`) that are unavoidable
here.

## What would change this

`env/` accumulating enough per-zone branching that a real templating tool would be
simpler than the conditionals. That is the signal to reconsider chezmoi.
