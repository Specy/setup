# 0021 — A single read-only drvfs mount for Zed, not automount

- **Status:** Accepted
- **Date:** 2026-08-01

## Context

Opening a project in a zone from Zed failed:

```
failed ensuring server binary: Command 'wsl.exe "--distribution" "dev-personal"
"--cd" "~" "--exec" "wslpath" "-u" "C:/Users/<you>/AppData/Local/Zed/remote_servers/..."'
failed: wslpath: C:/Users/<you>/AppData/Local/Zed/remote_servers/...
```

Zed's WSL remoting asks the distro to translate a Windows path with `wslpath`, and
`wslpath` can only do that when the drive is mounted through drvfs. With
`automount = false` ([0002](0002-wsl-conf-hardening.md)) there is no `/mnt/c`, so `wslpath`
echoes its input back and Zed cannot locate its server binary.

Confirmed by running the same command in both kinds of zone:

| Zone | `wslpath -u "C:/Users/<you>/AppData/Local/Zed"` |
| --- | --- |
| `dev-personal` (automount off) | `wslpath: C:/Users/<you>/AppData/Local/Zed` |
| `Ubuntu-26.04` (automount on) | `/mnt/c/Users/<you>/AppData/Local/Zed` |

This is [0002](0002-wsl-conf-hardening.md) working as designed, meeting a tool that assumes
the Windows filesystem is reachable.

## Decision

Mount **only** `%LOCALAPPDATA%\Zed\remote_servers`, **read-only**, at exactly the path
`wslpath` produces. Applied by `hosts/windows/zones/enable-zed.ps1` and persisted in
`/etc/fstab`, so it survives a restart.

```
C:\Users\<user>\AppData\Local\Zed\remote_servers  /mnt/c/Users/<user>/AppData/Local/Zed/remote_servers  drvfs  ro,noatime  0 0
```

`wslpath` is satisfied because the translation it returns now resolves to a real
directory. Nothing else on `C:` becomes reachable — verified in every zone:

```
$ ls /mnt/c/Users/<you>/Desktop
ls: cannot access '/mnt/c/Users/<you>/Desktop': No such file or directory
```

`verify.sh` still passes 22 / 22 / 21, because its automount assertion matches a mount at
`/mnt/<letter>` and this one is several levels deeper.

## Why read-only

Every zone mounts the **same** Windows directory. A writable mount would let
`dev-external` — the zone that exists to run untrusted code — replace a server binary that
`dev-work` subsequently executes. That is a direct zone-to-zone code-execution path, and
the only one this setup would have had through the filesystem.

Read-only removes it. Zed downloads and places the server binary from the Windows side,
where it has native access, so the zone only ever needs to read and execute it.

If Zed turns out to need write access, `enable-zed.ps1 -Writable` flips it — but that
reintroduces exactly the path above, and should be a considered choice rather than a quick
fix.

## Rejected alternatives

**Re-enable `automount` in the dev zones.** The obvious fix and the worst one: it exposes
all of `C:` to every zone, which is the single control that makes the isolation real.
Trading it for editor support inverts the whole model.

**Mount all of `%LOCALAPPDATA%\Zed`.** Tested and working, but it exposes Zed's extensions
directory. Zed executes extensions on the **Windows** side, so a zone able to write there
would have a path to host code execution. `remote_servers` alone is the minimum that
satisfies `wslpath`.

**Use VS Code instead.** Genuinely works with no changes — its server is installed inside
the distro over a socket rather than fetched across `/mnt/c`
([0008](0008-agent-execution-boundary.md)). A reasonable answer, but it decides the
editor by what the sandbox tolerates rather than by preference.

**Zed over SSH instead of WSL remoting.** Would avoid drvfs entirely, at the cost of an
sshd listening in each zone — which, per [0015](0015-shared-network-namespace.md), every
other zone can reach. More moving parts and more exposure than one read-only mount.

## What would change this

Zed installing its server inside the distro the way VS Code does would make the mount
unnecessary; remove the fstab line if that lands. Any other tool needing a Windows path
should get its own narrow mount by the same reasoning — never a blanket `automount`.
