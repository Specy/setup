# AGENTS.md

Instructions for an agent (or a person) implementing this setup on a machine.

Read this file completely before running anything. Then work through the phases in order.

## What you are building

Project code and coding agents execute inside isolated Linux zones — WSL2 distros, one per
trust level — while the Windows host stays a thin shell with no language toolchains. A
supply-chain compromise in one zone must not reach the credentials, source, or host of
another.

The default split is three dev zones plus the user's existing general-purpose distro:

| Zone | Holds | Credentials |
| --- | --- | --- |
| `daily` | the user's existing distro, kept for general Linux use | none |
| `work` | work projects | work GitHub token |
| `personal` | personal projects | personal GitHub token |
| `external` | third-party and untrusted code, agent sandbox | **none, deliberately** |

`external` existing at all is most of the value. Do not let the user collapse it away
without reading [decisions/0001](decisions/0001-zone-isolation-model.md).

## Before you touch anything

**Read [decisions/](decisions/).** There are twenty-one records. Several settings look
like mistakes until you know why they are there — `interop = false`, the absence of Docker
Desktop, and the per-zone uids are each load-bearing and each counter-intuitive. If you
are about to "fix" something that looks like an oversight, check `decisions/` first.

**Preconditions.** Verify these before starting, so failure happens at minute zero rather
than minute forty:

- Windows 11 with WSL2 (`wsl --version` reports 2.x)
- The user can respond to UAC prompts
- At least 40 GB free on the target drive
- `git` and `gh` on the host (`hosts/windows/apps.ps1` installs them)

## Phase 0 — configuration

```powershell
Copy-Item config.example.json config.json
```

Fill it in with the user. You need from them: their Windows username, git name and email,
the name and existing user of their current WSL distro (`wsl --list --verbose`, then
`wsl -d <name> -- whoami`), and which repositories belong in which zone.

`config.json` is gitignored. Nothing else in the repo may hardcode a username, a
repository, or machine sizing.

**Every uid must be unique across all distros including `daily`.** The loader rejects
duplicates, because the failure mode otherwise appears hours later as an unrelated systemd
error ([0016](decisions/0016-systemd-user-manager.md)).

## Phase 1 — host

```powershell
.\hosts\windows\apps.ps1
.\hosts\windows\write-wslconfig.ps1
wsl --shutdown
```

`write-wslconfig.ps1` sizes memory and CPU from the actual machine. Do not commit a
`.wslconfig`.

Then confirm with the user, from `hosts/windows/README.md` step 0: disk encryption on with
the recovery key stored **off-device**, and Memory Integrity on.

## Phase 2 — zones

```powershell
.\hosts\windows\zones\harden-daily.ps1
.\hosts\windows\zones\create-zone.ps1 -All
```

**STOP. This needs a human.** `passwd` requires an interactive terminal, so the accounts
are locked until the user runs, once per zone:

```powershell
wsl -d dev-work -u root passwd dev
```

Do not attempt to automate this, and do not set `NOPASSWD` to avoid it.

## Phase 3 — provision

```powershell
.\hosts\windows\provision-zone.ps1 -All -WithAgents
```

Pushes the repo into each zone, installs packages as root, configures the user
environment, installs the agent CLIs, and runs `verify.sh`.

**Expected result: 0 failed in every zone.** Anything else stops the run — read the failing
assertion, and consult the decision record it names.

## Phase 4 — credentials and repositories

**STOP. This needs a human.** Per zone with `"github": true`:

```powershell
wsl -d dev-work -- gh auth login
```

Tell the user to choose **HTTPS**, and to paste a token rather than use the browser flow —
with interop disabled the browser cannot be launched from inside the zone.

Strongly recommend **fine-grained tokens scoped to that zone's repositories only**. If the
zones share one GitHub account, this repository scoping is the *entire* separation between
them ([0006](decisions/0006-credential-placement.md)). Note the expiry date somewhere: the
failure a year later is a bare 401 with nothing pointing at the cause.

Then:

```powershell
.\hosts\windows\provision-zone.ps1 -All -WithRepos
```

## Phase 5 — editor and finishing

```powershell
.\hosts\windows\terminal\apply.ps1
.\hosts\windows\zones\enable-zed.ps1
```

Terminal gets a colour per zone. This is not decoration — colour is what stops a work token
being pasted into `external`. `enable-zed.ps1` is only needed if the user uses Zed
([0021](decisions/0021-zed-remote-servers-mount.md)); VS Code needs nothing.

Docker, if a zone enables it, is not scripted — the commands are in
[0018](decisions/0018-docker-in-work-zone.md).

## Steps you must never automate

| Step | Why |
| --- | --- |
| `passwd` per zone | Needs a terminal. `NOPASSWD` gives any script root in the zone |
| `gh auth login` | Interactive, and the user must choose token scopes |
| Agent sign-in | Interactive |
| UAC prompts | Cannot be automated; the user must be present |
| Disk encryption recovery key | The user must store it off-device themselves |

If you cannot complete one of these, **stop and say so**. Do not work around it.

## Customising without forking the template

`main` is the template and stays generic. Anything specific to one person goes in exactly
two places, so that improvements move between branches without dragging personal details
along:

| | `main` | a personal branch |
| --- | --- | --- |
| `config.json` | gitignored | force-added and tracked (`git add -f`) |
| `overrides/` | a README only | whatever that person needs |

**Never personalise a base script.** If a user wants an extra package, an extra setup step,
their editor config, or an extra assertion, it goes in `overrides/` — see
[overrides/README.md](overrides/README.md) for the hooks. Editing `env/` or `hosts/`
directly means every future template update collides with that edit.

If a change is genuinely general — it would help anyone using this — put it in the template
with a decision record instead, and it can be backported to `main` cleanly because it
touches no personal files.

## Invariants

Breaking one requires a new decision record explaining why.

1. **No secrets in this repo.** `config.json` is gitignored and holds no tokens either —
   only names. See [SECRETS.md](SECRETS.md).
2. **Dev zones never mount the Windows filesystem.** `automount = false` and
   `interop = false`. This is the one control that makes the isolation real.
3. **The daily distro never executes Windows binaries.** It keeps `/mnt/c` but loses
   interop, because a distro that can run `wsl.exe` reads every other distro without a
   password.
4. **Everything is idempotent.** Re-running any script against a configured machine is
   safe and reports no changes.
5. **Every meaningful config has an assertion in `verify/`.** Documentation rots silently;
   assertions fail loudly.
6. **Project code lives on the native filesystem** at `~/code`, never under `/mnt`.
7. **Agents execute inside the zone.** An agent driven from a Windows process — a desktop
   chat app reaching files over MCP — runs on the host with host permissions and defeats
   the entire model.
8. **Zones with `"github": false` hold no credentials.** `verify.sh` fails if one becomes
   authenticated.

## What this does NOT protect against

State these plainly to the user rather than letting them assume otherwise.

- **The network.** All WSL2 distros share one network namespace. Every loopback service and
  **every container, published or not**, is reachable from every other zone including
  `external`. Every service needs its own authentication
  ([0015](decisions/0015-shared-network-namespace.md)).
- **Kernel exploits.** Zone-to-zone isolation is namespace-based, comparable to containers.
  WSL-to-Windows is a real Hyper-V boundary; zone-to-zone is not.
- **A compromised Windows host.** The host reaches every zone via `wsl.exe` with no
  authentication, by design.

## Conventions when editing this repo

- Shell scripts: LF endings, `set -euo pipefail`, `--zone <name>` where zone-specific.
- **PowerShell scripts are ASCII only.** Windows PowerShell 5.1 reads `.ps1` as ANSI without
  a BOM, so an em dash becomes a parser error rather than a legible failure.
- Decision records are append-only. Superseding one means writing a new record and marking
  the old `Superseded by NNNN`, never editing it to say something different.
- `env/` must work on native Linux too, not just WSL. WSL specifics belong in
  `hosts/windows/`.

## Verifying

```bash
~/setup/verify/verify.sh --zone work
```

Run after any change. `verify.sh` asserts the model **both ways** — it fails if a zone is
missing something it should have, and equally if it has something it should not. Those are
not oversights to relax.
