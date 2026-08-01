# env — the portable environment

Everything here configures the inside of a Linux environment and **must work on native
Linux as well as inside WSL** ([0013](../decisions/0013-repo-layout.md)). Anything
WSL-specific belongs in [`../hosts/windows/`](../hosts/windows/).

That rule is the whole payoff of the repo layout: when the dual boot happens, this
directory is reused unchanged.

## Entry points

System packages first, as root:

```bash
wsl -d dev-work -u root -- /home/dev/setup/env/packages.sh --zone work
```

Then user-level configuration, as the zone's own user:

```bash
./env/bootstrap.sh --zone work
```

Valid zones: `daily`, `work`, `personal`, `external`.

The split is deliberate. `packages.sh` needs root; `bootstrap.sh` configures the user's
own environment and must never need it, so it never prompts for a password.

Both are idempotent — safe to re-run against a partly or fully configured environment,
reporting only what they change.

## Layout

| Path | Contents | Runs as |
| --- | --- | --- |
| `packages.sh` | System packages, apt repositories, rustup | **root** |
| `bootstrap.sh` | User config: shell, git, npm, mise, sandbox, agent deny-list | zone user |
| `agents.sh` | Agent CLIs — separate because it is slow ([0008](../decisions/0008-agent-execution-boundary.md)) | zone user |
| `git/` | Shared git config, included from `~/.gitconfig` | — |
| `node/` | `.npmrc` with lifecycle scripts disabled ([0005](../decisions/0005-npm-ignore-scripts.md)) | — |
| `mise/` | Runtime baseline: node 24, uv ([0011](../decisions/0011-toolchain-management.md)) | — |
| `sandbox/` | `sandbox` command — per-project confinement ([0008](../decisions/0008-agent-execution-boundary.md)) | — |
| `agents/` | Claude deny-list deployed to `~/.claude/settings.json` | — |

Not scripted: Docker, which is installed in `work` only and whose exact commands are
recorded in [0018](../decisions/0018-docker-in-work-zone.md). Promote it to `env/docker.sh`
if a second zone ever needs containers.

The shell prompt needs no special handling — each zone's hostname *is* its zone name
(`dev@dev-work:~/code$`), and the Windows Terminal colour scheme carries the visual signal
([terminal/README.md](../hosts/windows/terminal/README.md)).

Pending items are implemented as the corresponding phase of the runbook is executed,
rather than written speculatively in advance.

## Shell configuration, and why it is split across two files

`bootstrap.sh` writes a **managed block** — delimited by `# >>> managed by setup repo >>>`
markers — into two files. Anything outside the markers is yours and is never touched.

| File | Contains | Why there |
| --- | --- | --- |
| `~/.profile` | mise **shims** on `PATH`, `SETUP_ZONE` | Read by login shells regardless of interactivity |
| `~/.bashrc` | `mise activate bash` | Interactive only; adds per-directory version switching on `cd` |

The split is not stylistic. Ubuntu's stock `~/.bashrc` opens with

```sh
case $- in *i*) ;; *) return;; esac
```

so **anything appended to `.bashrc` is skipped entirely by non-interactive shells.** With
activation only there, `node` resolves when a human is typing and vanishes for scripts and
anything an agent runs non-interactively. The shims are real executables on disk and need
no shell hook, which is why they go in `.profile`.

### Running one-off commands from Windows

```powershell
wsl -d dev-work -- bash -lc 'npm test'
```

The `-l` matters. `wsl -d dev-work -- npm test` reads no shell configuration at all — not
`.profile`, not `.bashrc` — so the toolchain is not on `PATH` and the command fails with
`command not found`. This is WSL behaviour, not a gap in the setup.

## The zone marker

`bootstrap.sh` writes `~/.zone` containing the zone name. It is read by the shell prompt,
by `verify/verify.sh`, and by anything else that needs to know where it is running. It is
the one piece of state that makes an environment self-describing.

## Identity is not configured here

Zone identity — GitHub account, git `user.email` — is set interactively with
`gh auth login` and `git config`, and is deliberately not in this repo. See
[SECRETS.md](../SECRETS.md) and
[0006](../decisions/0006-credential-placement.md). `bootstrap.sh` reports when identity is
unset but does not attempt to guess it.
