# overrides

Your customisations, kept out of the template.

`main` is the template and should stay generic. Everything personal — extra packages,
extra setup steps, editor config backups, your own `verify` assertions — goes here, so that
improvements can move between a personal branch and `main` without dragging personal
details along.

The template ships this directory containing only this file. That is intended.

## Why not just edit the base scripts

Because then every improvement to the template collides with your edits. With overrides,
`main` and a personal branch differ in exactly two places:

| | `main` | a personal branch |
| --- | --- | --- |
| `config.json` | gitignored | force-added and tracked |
| `overrides/` | this README only | whatever you need |

Backporting is then a normal cherry-pick of files that were never personalised, and
pulling template updates into a personal branch is a merge that touches nothing of yours.

## Hooks

Each hook is optional. If the file does not exist, nothing happens and nothing is
reported. If it exists it must be executable, and a non-zero exit fails the run — an
override that breaks should be loud.

| Hook | Runs | As | Receives |
| --- | --- | --- | --- |
| `overrides/env/packages.sh` | after the base `env/packages.sh` | **root**, in the zone | `--zone <name>` |
| `overrides/env/bootstrap.sh` | after the base `env/bootstrap.sh` | zone user | `--zone <name>` |
| `overrides/verify/verify.sh` | after the base assertions | zone user | `--zone <name>` |
| `overrides/hosts/windows/post-provision.ps1` | at the end of `provision-zone.ps1` | host | `-Zone <name>` |

Hooks run **after** the base step, so they extend rather than replace it. If you need to
change base behaviour rather than add to it, that belongs in the template with a decision
record — not here.

Read `config.json` from a hook with the same helpers the base scripts use:

```bash
. "$REPO_ROOT/env/lib/config.sh"
[[ "$(cfg_zone_field "$ZONE" docker)" == "true" ]] && ...
```

## Assets

`overrides/assets/` is for verbatim copies of host application config — editor settings,
themes, keybindings — so a rebuild does not mean recreating them by hand.

Nothing there is provisioned or verified. It is a backup you restore deliberately, which
is why it is not part of the template.

## Verify assertions

`overrides/verify/verify.sh` is sourced with the base script's `ok`, `bad` and `skip`
functions already defined, so extra checks look exactly like the built-in ones:

```bash
if command -v gcloud >/dev/null 2>&1; then
    ok 'gcloud present'
else
    bad 'gcloud missing - required in this zone'
fi
```

Counts and the exit code include your assertions.
