# Changelog

## 2026-08-01 — first public release

Built on one machine over a few days, then generalised: everything machine-specific moved
into a gitignored `config.json`, and history was squashed for the public release.

The detailed build log is gone with that squash. It was a record of one machine, and the
part worth keeping — *why* each choice was made, and what was rejected — was always in
[decisions/](decisions/) rather than here. Twenty-one records, each with the trigger that
should prompt a revisit.

### Findings that cost real time

Recorded because they are all counter-intuitive, and each was found by measuring rather
than reasoning.

**All WSL2 distros share one network namespace.** Identical `net:[...]` inode, identical
IP, and a loopback listener in one zone answers a `curl` from another. The zone boundary
covers filesystems, users, credentials and processes — **not** the network
([0015](decisions/0015-shared-network-namespace.md)).

**Docker containers are reachable across zones even unpublished.** The bridge lives in
that shared namespace, so a container with no `-p` flag answered from the untrusted zone at
its bridge IP. This invalidated advice an earlier version of 0015 gave — "don't publish
ports" protects nothing, and the correction is left visible
([0018](decisions/0018-docker-in-work-zone.md)).

**Every distro needs a distinct uid.** systemd's `user@<uid>.service` collides across
distros because they share a kernel: only the first to claim a uid gets a working user
manager, the rest fail with `EBUSY` and stay degraded for that boot. The first hypothesis —
a locked password — correlated once and was wrong
([0016](decisions/0016-systemd-user-manager.md)).

**`interop` is a zone-to-zone hole, not just a Windows-facing one.** A distro that can
execute `wsl.exe` reads every other distro's filesystem with no password, which is why even
the credential-free general-purpose distro has it disabled
([0002](decisions/0002-wsl-conf-hardening.md)).

**`npm rebuild` reports success while fixing nothing.** Under `ignore-scripts`, a package
whose postinstall fetches a native binary installs cleanly and then refuses to run;
`npm rebuild -g` prints `rebuilt dependencies successfully` and changes nothing. The install
script has to be invoked directly ([0005](decisions/0005-npm-ignore-scripts.md)).

**Sparse VHD is disabled upstream** over data corruption, reachable only via
`--allow-unsafe`. Disk is reclaimed manually instead
([0014](decisions/0014-no-sparse-vhd.md)).

### Smaller traps, all documented in place

- Windows PowerShell 5.1 reads `.ps1` as ANSI without a BOM, so a single em dash in a
  comment is a parser error rather than a legible failure.
- Ubuntu's stock `.bashrc` returns early for non-interactive shells, so a toolchain
  activated only there works when a human types and vanishes for every script and agent.
- `/bin` is a symlink into `/usr` on merged-usr systems, so a bubblewrap sandbox binding
  only `/usr` has no executable at all — and that made an isolation test *falsely pass*.
- `git config --global --get` does not follow `include.path`, so settings in an included
  file are invisible to it.
- Under WSL `/etc/resolv.conf` symlinks outside the sandbox root, so DNS fails while a bare
  IP still works.
- `/tmp` is a tmpfs and the WSL VM idles out after 60s, so staging files there between two
  commands can find them gone.
