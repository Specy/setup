# 0002 — Dev zones do not mount or execute Windows

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

By default WSL mounts the entire Windows filesystem at `/mnt/c` **with the permissions of
the Windows user**, and appends the Windows `PATH` to the Linux `PATH`. Both are on by
default and both are enormously convenient.

Together they mean a process inside WSL — including any `postinstall` script or agent —
can read `C:\Users\<you>\`, write to it, and execute arbitrary Windows binaries. With
those defaults left in place, per-zone distros are decoration: everything can reach
everything through the host.

There is a second, less obvious consequence. Interop lets a distro execute
`C:\Windows\System32\wsl.exe`, and `wsl.exe -d <other-distro> <command>` runs as the
default user in that distro **without a password**. Any distro with interop enabled can
therefore read every other distro's filesystem. Interop is not just a Windows-facing
hole, it is a zone-to-zone hole.

## Decision

`/etc/wsl.conf` is per-distro (unlike `.wslconfig`, which is global), so each zone is
configured independently:

| Distro | `automount` | `interop` | `appendWindowsPath` |
| --- | --- | --- | --- |
| `dev-work` | false | false | false |
| `dev-personal` | false | false | false |
| `dev-external` | false | false | false |
| `Ubuntu-26.04` | **true** | **false** | false |

The daily driver keeps `/mnt/c` because its whole purpose is being a usable Linux box
next to Windows, but loses interop so it cannot become the pivot into the hardened zones.

`appendWindowsPath = false` also delivers a second goal for free: coding agents can no
longer resolve `npm.cmd`, `git.exe` or `python.exe` from Windows. There is no Windows
tooling on `PATH` to accidentally use, so agents use Linux tools by construction rather
than by instruction.

## Consequences

Lost in the hardened zones: `explorer.exe .`, `clip.exe`, launching a Windows browser
from the shell, and any access to `C:\`.

Not lost: `code .` still works, because the VS Code remote CLI is a shell script talking
to the VS Code server over a socket rather than an interop call. Windows Explorer can
still reach into a distro via `\\wsl.localhost\<distro>\`, which is Windows reading WSL —
the safe direction.

## Rejected alternatives

**`automount = false` but `interop = true`.** Tempting, since with no `/mnt/c` there is
no path to a `.exe`. But interop executes any PE binary regardless of where it sits, so a
`.exe` copied or downloaded into the Linux filesystem still runs. This closes the obvious
door and leaves the real one open.

**Restricting `/mnt/c` with mount options instead of disabling it.** More moving parts,
more ways to get it subtly wrong, and it still leaves interop.

**Leaving the daily driver fully open.** Rejected because of the `wsl.exe` pivot above.
The cost of `interop = false` there is small; the cost of leaving it is that the weakest
zone can read the strongest.

## What would change this

A concrete workflow that genuinely needs interop in a hardened zone. The most likely
candidate is SSH agent forwarding from Windows, which is why credentials were arranged to
not need it — see [0006](0006-credential-placement.md).
