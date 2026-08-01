# Windows host runbook

Ordered. Later steps assume earlier ones. Nothing here is destructive to existing data
except where marked.

Read [../../decisions/](../../decisions/) before deviating.

## 0. Host baseline

| Check | Expected | How |
| --- | --- | --- |
| BitLocker | On, recovery key stored **off-device** | Settings → Privacy & security → Device encryption |
| Memory Integrity | On | Windows Security → Device security → Core isolation |
| Smart App Control | Left in evaluation — do not enforce ([0009](../../decisions/0009-smart-app-control.md)) | Windows Security → App & browser control |
| Language toolchains | **None on the host** ([0001](../../decisions/0001-zone-isolation-model.md)) | `where node` should fail |

## 1. Configuration

```powershell
Copy-Item ..\..\config.example.json ..\..\config.json
```

Fill it in: your Windows username, git identity, your existing distro and the user inside
it (`wsl -d <name> -- whoami`), and which repositories belong in which zone. `config.json`
is gitignored and every script reads it.

Every uid must be unique across all distros including the daily one. The loader rejects
duplicates — see [0016](../../decisions/0016-systemd-user-manager.md) for the failure this
prevents.

## 2. Host applications

```powershell
.\apps.ps1
```

Idempotent. Add new host applications there, not by hand — the file is the record of what
belongs on this machine.

## 3. WSL global config

```powershell
.\write-wslconfig.ps1
wsl --shutdown
```

Generated from this machine's actual RAM and CPU count rather than committed, since a fixed
figure that suits one machine starves another. `config.json` can pin the numbers instead.

All distros share this one memory budget: they run in a single utility VM.

## 4. Harden the existing daily driver

```powershell
.\zones\harden-daily.ps1
```

Your existing distro stays as the general-purpose Linux box but loses interop, so it cannot
become the pivot into the hardened zones
([0002](../../decisions/0002-wsl-conf-hardening.md)).

Afterwards `/mnt/c` still exists and `cmd.exe /c ver` fails. Both outcomes are intended.

## 5. Create the dev zones

```powershell
.\zones\create-zone.ps1 -All
```

Idempotent, and `-Zone <name>` does one at a time. For each zone the script installs the
distro under the configured install root, creates the user with that zone's uid, renders
`zones/wsl.conf.template` and deploys it, removes the empty `/mnt/c` stub left by the first
launch, terminates to apply, and prints a verification block covering user, uid, hostname,
user manager, automount, interop and `PATH`.

The user must be created before `wsl.conf` is applied, because `[user] default` refers to
an account that has to already exist. The script handles that ordering.

### Set the account passwords

`create-zone.ps1` deliberately does not set passwords — `passwd` needs an interactive
terminal. Until you do this the account is locked and `sudo` will not work. Run once per
zone, in a real terminal:

```powershell
wsl -d dev-work -u root passwd dev
```

Sudo requires a password by design. `NOPASSWD` would mean any script that runs in the
zone gets root in the zone; the zone boundary makes that less severe than on a normal
machine, but it is not free. If the friction proves intolerable, record the change as a
decision rather than editing it in quietly.

**After this point the dev zones can no longer see `C:\`.** Get files in via
`\\wsl.localhost\dev-work\home\dev\` from Explorer, which is Windows reading WSL — the
safe direction.

## 6. Configure each zone

```powershell
.\provision-zone.ps1 -All -WithAgents
```

It pushes this repo into the zone, runs `env/packages.sh` as root, runs
`env/bootstrap.sh` as the zone user, optionally installs the agent CLIs, and finishes with
`verify/verify.sh`. Idempotent — a fully provisioned zone reports "nothing to change"
throughout.

`-WithAgents` is opt-in because claude alone pulls a ~275 MB native binary. **`verify.sh`
asserts the agent CLIs**, so a zone provisioned without it will not report green until
`env/agents.sh` has run once. Useful switches: `-SkipPackages` for user-level config only,
`-SkipVerify` to suppress the closing check.

**Why push rather than clone.** The zones cannot see `C:\`, and they cannot all read this
repo from GitHub if it lives in only one zone's token scope, and
`dev-external` holds no credentials at all by design
([0006](../../decisions/0006-credential-placement.md)). Widening the work token to include
an infrastructure repo would weaken the separation for a non-project reason. Pushing is
also better on its own terms — `external` never receives a checkout of anything it does
not need.

`dev-personal` *can* clone this repo normally, and may prefer to:

```bash
gh repo clone <you>/setup ~/setup
```

See [../../env/README.md](../../env/README.md) for what the scripts do.

## 7. Credentials and repositories

**Needs you present.** Per zone with `"github": true`:

```powershell
wsl -d dev-work -- gh auth login
```

Choose **HTTPS**, and paste a token rather than using the browser flow — with interop
disabled the zone cannot launch a browser.

Use **fine-grained tokens scoped to that zone's repositories only**. If your zones share
one GitHub account, that repository scoping is the entire separation between them
([0006](../../decisions/0006-credential-placement.md)). Note the expiry somewhere: a year
later the failure is a bare 401 with nothing pointing at the cause.

Then clone what `config.json` lists:

```powershell
.\provision-zone.ps1 -All -WithRepos
```

Zones with `"github": false` can only take repositories marked `"anonymous": true`, and
`clone-repos.sh` refuses the rest rather than prompting for credentials that zone is not
supposed to have.

## 8. Terminal profiles

```powershell
.\terminal\apply.ps1
```

One profile per zone with a distinct colour scheme, then restart Terminal. This is not
decoration — the colour is what stops a work token being pasted into `external` at one in
the morning. See [terminal/README.md](terminal/README.md).

## 9. Editors

### Zed

```powershell
.\zones\enable-zed.ps1
```

Zed's WSL remoting calls `wslpath` to translate a Windows path, which needs a drvfs mount.
With `automount = false` it fails with `failed ensuring server binary`. This mounts **only**
Zed's `remote_servers` directory, read-only, at the path `wslpath` produces — nothing else
on `C:` becomes reachable. See [0021](../../decisions/0021-zed-remote-servers-mount.md).

### VS Code

Nothing to install on the WSL side. But `code .` from inside a zone works **only after VS
Code has connected to that zone from Windows at least once** — the `code` command is
`~/.vscode-server/bin/*/bin/remote-cli/code`, which exists only once a connection has
installed the server. A fresh zone has no `code` command at all.

So the entry point is always Windows-side: open VS Code, run **WSL: Connect to WSL using
Distro**, pick the zone. After that first connection `code .` works normally inside it.

The pre-interop habit of typing `code .` in a fresh WSL shell no longer works, because that
relied on a wrapper script under `/mnt/c` execing the Windows binary.

## 10. Docker, where a zone enables it

Not scripted. The exact commands are in
[0018](../../decisions/0018-docker-in-work-zone.md). Read
[0015](../../decisions/0015-shared-network-namespace.md) first: every container in a zone
is reachable from every other zone, published or not, so each container service needs its
own authentication.

## 11. Migrate projects

Re-clone from GitHub into `~/code/` in the owning zone. Do not copy from
`Desktop\projects\` — a fresh clone avoids carrying over Windows line endings, stale
`node_modules` and local state ([0007](../../decisions/0007-code-on-ext4.md)).

Once a zone's projects are verified working, the corresponding `Desktop\projects\<zone>\`
folder can be deleted. **Check for uncommitted work first.**

## 12. Snapshot

```powershell
wsl --terminate dev-work; wsl --export dev-work C:\wsl-backups\dev-work-YYYY-MM-DD.tar
```

See [0012](../../decisions/0012-backup-and-snapshots.md). Exports contain that zone's
credentials — treat the `.tar` accordingly.

## Recurring operations

| Task | Command |
| --- | --- |
| Apply `.wslconfig` changes | `wsl --shutdown` |
| Apply `wsl.conf` changes | `wsl --terminate <distro>` |
| List zones and state | `wsl --list --verbose` |
| Reclaim disk after big deletes | manual `diskpart compact vdisk` — see [0014](../../decisions/0014-no-sparse-vhd.md) |
| Snapshot a zone | `wsl --export <distro> <file>.tar` |
| Restore a zone | `wsl --import <distro> <location> <file>.tar` |

`wsl --unregister` deletes a distro and everything in it immediately, with no recycle
bin, and is one typo from other `wsl` commands. Snapshot first.
