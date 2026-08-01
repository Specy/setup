# Native Linux host bootstrap

Placeholder for the planned dual boot. Nothing here yet.

## What this will need to cover

Only what is genuinely host-specific. Everything about configuring a working environment
already lives in [`../../env/`](../../env/) and is reused unchanged — that reuse is the
entire reason the repo is split this way
([0013](../../decisions/0013-repo-layout.md)).

- Distribution choice and installation
- Disk layout and full-disk encryption (the equivalent of BitLocker on the Windows side)
- Bootloader and dual-boot coexistence with the Windows install
- Desktop environment and host applications, mirroring `hosts/windows/apps.ps1`
- Mapping the zone model onto native Linux

## The open design question

The zone isolation in [0001](../../decisions/0001-zone-isolation-model.md) is implemented
with WSL distros, which do not exist here. The same boundary on native Linux needs a
different mechanism — separate Unix users per zone, systemd-nspawn containers, or full
VMs — each with a different strength and a different amount of friction.

That decision should be made when the dual boot is actually being set up, with a new
decision record. It should not be guessed at now: the right answer depends on how the
zone model has held up in daily use by then, which is information not yet available.

## What is already portable

- `env/bootstrap.sh --zone <name>` is intended to run unchanged
- `verify/verify.sh` skips WSL-specific assertions when not running under WSL
- Every decision record except [0002](../../decisions/0002-wsl-conf-hardening.md),
  [0003](../../decisions/0003-networking-mode.md) and
  [0009](../../decisions/0009-smart-app-control.md) applies to both platforms
