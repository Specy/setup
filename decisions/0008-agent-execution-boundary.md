# 0008 — Agents must execute inside the zone

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Claude Code, Codex and Gemini CLI are all in use. There is a natural assumption that the
choice is between a comfortable desktop GUI and a terminal. That is the wrong axis. The
question that matters is **where the commands actually execute**.

A desktop chat application — Claude Desktop, ChatGPT Desktop — is a Windows process. If
it reaches project files through an MCP filesystem server, that server is also a Windows
process running with the host user's permissions, outside every boundary in
[0001](0001-zone-isolation-model.md) and [0002](0002-wsl-conf-hardening.md). The zone
model is bypassed entirely, silently, while everything appears to work.

## Decision

Any agent that reads or writes project code, or runs commands against it, must execute
inside the zone that owns that code.

Acceptable:

- Agent CLI installed inside the distro.
- **VS Code with Remote-WSL and the agent extension installed in the WSL remote.** Full
  GUI, but the extension host, terminal and agent all run inside the zone. This is the
  recommended day-to-day setup.

Not acceptable:

- Desktop chat applications pointed at project directories over MCP.
- Any agent whose shell resolves to a Windows shell.

Desktop chat applications remain fine for conversation that does not touch project files.

## Supporting configuration

- Deny-lists at `~/.claude/settings.json`, deployed by `env/bootstrap.sh`, covering
  `~/.ssh/**`, `~/.config/gh/**`, `~/.aws/**`, `.env*` and key files. Defence in depth
  against prompt injection from repository content — a backstop, not the boundary.
- MCP servers are arbitrary code running with the agent's permissions. Configure them
  per project, never globally, and treat adding one as a dependency decision.

## The sandbox — `env/sandbox/sandbox.sh`

Installed to `~/.local/bin/sandbox` in every zone. Confines a command to a single project
directory:

```bash
sandbox                     # interactive shell, no network
sandbox npm test            # one command, no network
sandbox --net npm install   # network allowed
```

| Property | Behaviour |
| --- | --- |
| `$HOME` | empty tmpfs — other projects, history and agent config are invisible |
| Writes to `$HOME` | succeed, land in tmpfs, vanish on exit |
| Project directory | the only persistent writable path |
| Network | **off by default**, `--net` to allow |
| Toolchains | node, npm, cargo available read-only |
| `ignore-scripts` | still `true` inside |
| Outside `~/code` | refuses to run |

Verified against all of the above in `dev-external`.

### Two implementation details worth keeping

**Merged-usr.** `/bin`, `/sbin` and `/lib` are symlinks into `/usr` on Ubuntu. bwrap builds
an empty root, so binding `/usr` alone leaves no `/bin` and every command dies with
`execvp /bin/bash: No such file or directory`. The symlinks must be recreated with
`--symlink`.

**DNS under WSL.** `/etc/resolv.conf` is a symlink to `/mnt/wsl/resolv.conf`, which the
sandbox root does not contain. The symlink dangles, so name resolution fails while
connections to a bare IP still work — a confusing half-broken network. The resolved target
is bound when `--net` is given.

### What it is not

Not a boundary against a kernel exploit — bubblewrap uses user namespaces. It raises the
cost of a hostile `postinstall` or a prompt-injected agent considerably, and is a second
layer behind the zone, not a replacement for it.

Note also that `--net` grants the **shared** namespace, which per
[0015](0015-shared-network-namespace.md) reaches every other zone's services. Sandboxed
does not mean network-isolated from the rest of the machine.

Autonomous agent mode is acceptable **only** inside this sandbox, never as a blanket flag.

## Open

Whether the Claude Code **desktop app** on Windows can target a WSL distro as its
execution environment, or whether it shells out to Windows. If the former it is
acceptable under this record; if the latter it is not. Determine by inspection once a
zone exists — do not assume.

## What would change this

An agent tool offering a first-class remote execution target that is verifiably inside
the zone would be acceptable under the same rule. The rule is about execution location,
not about which product is used.
