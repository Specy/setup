# 0009 — Smart App Control left in evaluation mode

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Smart App Control blocks unsigned and low-reputation binaries on Windows. It has an
unusual property: it can **only** be enabled shortly after a clean install. Once it turns
off — manually or by its own evaluation logic — re-enabling requires reinstalling
Windows.

At the time of writing it sits in evaluation mode (`VerifiedAndReputablePolicyState = 2`),
so the option is live. Because the entire toolchain is going into WSL by
[0001](0001-zone-isolation-model.md), the host would plausibly stay signed-binaries-only
and enforcement might actually hold.

Against that: there is no certainty that a Windows-side toolchain will never be needed,
and discovering the constraint at the wrong moment — mid-task, with a reinstall as the
only remedy — is a bad failure mode.

## Decision

Leave Smart App Control in evaluation mode. Do not enforce it.

Treat "if it can run in WSL, it runs in WSL" as a strong default rather than a rule
enforced by the OS. The isolation model does not depend on Smart App Control; it is
additive hardening that was available for free and was declined for flexibility.

## Consequences

Evaluation mode will most likely resolve itself to off over time as software is
installed. That is expected and costs nothing, precisely because nothing depends on it.

The host retains Memory Integrity (on) and BitLocker (on), which are the two host
protections that actually matter here.

## What would change this

A future clean install where the WSL-only discipline has proven to hold in practice would
be the moment to enforce it. That decision has to be made in the first days of that
install or not at all.
