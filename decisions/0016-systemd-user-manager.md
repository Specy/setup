# 0016 — Each zone needs a distinct uid

- **Status:** Accepted
- **Date:** 2026-07-31

## Symptom

Entering a dev zone printed:

```
Failed to start the systemd user session for 'dev'. See journalctl for more details.
```

`systemctl is-system-running` reported `degraded`, with:

```
user@1000.service: Failed to spawn executor: Device or resource busy
user@1000.service: Failed with result 'resources'.
```

Once failed, the unit could not be recovered within that boot — `reset-failed` followed
by `start` failed identically.

## Root cause

systemd runs a per-user manager as `user@<uid>.service`. **All WSL2 distros share one
kernel**, and that unit collides across distros on the uid: whichever distro starts a
given uid's manager first wins, and every other distro using the same uid fails with
`EBUSY` for the life of that boot.

Every zone had been created with the distribution default of uid 1000, so only one zone
at a time could have a working user manager.

The evidence, in the order it was gathered:

| Observation | What it ruled in or out |
| --- | --- |
| `user@0` (root) worked while `user@1000` failed in the same distro | not distro-wide |
| the pre-existing user in the daily distro worked while `dev` failed | not systemd-wide |
| `dev` had a locked password | plausible, and **wrong** — see below |
| After setting passwords: `dev-work` healthy, others still failing | password was not the cause |
| Booting `dev-personal` alone three times: healthy each time | not a property of the zone |
| Cold VM, then booting zones in order: only the **first** got a working manager | uid collision |
| `dev-personal` moved to uid 1001, booted alongside `dev-work` at 1000: **both active** | confirmed |

The password was a red herring. It correlated once because `dev-work` happened to be the
first zone booted after the passwords were set.

## Decision

Each zone's user gets a distinct uid and gid, assigned by
`hosts/windows/zones/create-zone.ps1`:

| Zone | User | uid/gid |
| --- | --- | --- |
| `daily` | pre-existing user | 1000 — left alone |
| `work` | `dev` | 1001 |
| `personal` | `dev` | 1002 |
| `external` | `dev` | 1003 |

Verified with all four zones running simultaneously: every `user@<uid>.service` active,
every zone `running` rather than `degraded`.

`verify.sh` asserts both the expected uid and an active user manager, so a zone created
by hand with the default uid fails the check rather than silently degrading.

## Known remaining noise

- **`user@0.service` fails in any distro that is not the first to run a root session.**
  Root is uid 0 everywhere, so it collides by exactly the same mechanism and cannot be
  fixed by renumbering. It appears only when running `wsl -u root`, which normal use does
  not, and root's user manager is not used for anything here. Harmless.
- **`getty@tty1.service` fails in every zone.** Expected under WSL, which has no physical
  tty. Unrelated.

## What would change this

WSL isolating the systemd user-manager namespace per distro, which would make the uid
assignment unnecessary but harmless. The uid scheme is worth keeping regardless — it
makes `ls -ln` output across zones unambiguous.
