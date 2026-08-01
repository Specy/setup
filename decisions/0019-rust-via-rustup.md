# 0019 — Rust via rustup, not mise

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Some migrated projects are Rust, in the `personal` and `external` zones. No Rust toolchain
was installed.

[0011](0011-toolchain-management.md) adopted mise as the runtime version manager, so mise
is the default answer. mise does support Rust — `mise latest rust` returns 1.97.1 — and
Ubuntu 26.04 also ships a `rustup` package.

## Decision

**rustup, from Ubuntu's archive**, in `personal` and `external` only. `rustup default
stable` is set per user by `env/bootstrap.sh`.

This is a deliberate exception to 0011.

## Why not mise

Rust is not just a runtime version, and the parts mise does not manage are the parts these
projects need:

- **Targets.** `rustup target add wasm32-unknown-unknown` is required for anything
  compiling to WebAssembly. mise's Rust support has no equivalent.
- **Components.** `clippy`, `rustfmt`, `rust-analyzer` are installed and versioned by
  rustup alongside the toolchain.
- **Channels.** stable/beta/nightly switching, and per-project pinning via
  `rust-toolchain.toml`, which cargo honours automatically and mise does not read.

mise's own documentation points at rustup for Rust. Using mise here would mean discovering
its limits at the first `wasm32` build rather than now.

This does not weaken 0011. That record adopted mise for Node and Python-shaped runtimes,
where version selection is the whole problem. Rust's toolchain manager already solves a
larger problem well, and Ubuntu ships it as a signed package — so unlike mise itself
([0011](0011-toolchain-management.md)) and `gh` ([0017](0017-github-cli-source.md)), no
extra trust root is involved.

## Scope

Installed only in zones with `"rust": true` in `config.json`, and `verify.sh` asserts it
**both ways** — present where enabled, absent where not, so a zone quietly acquiring a
toolchain it should not have fails the check.

The toolchain is roughly a gigabyte and disk is not reclaimed automatically
([0014](0014-no-sparse-vhd.md)), so installing it in a zone that has no use for it is a
real cost. Add a zone to the list when it gains a Rust project.

## Rejected alternatives

**mise `rust = "stable"`.** One tool instead of two, but no targets, no components, and no
`rust-toolchain.toml` support. Reconsider only if Rust becomes incidental — a single
dependency to compile rather than a language being worked in.

**The `rustup.rs` install script.** The canonical route, and a piped shell script, which
[0011](0011-toolchain-management.md) rules out. Ubuntu's package provides the same binary
through the archive.

**apt `rustc` and `cargo` directly.** One fixed toolchain, no channel switching, no
targets. Worse than either option above.

## What would change this

mise gaining real target and component management, or Rust disappearing from these zones.
