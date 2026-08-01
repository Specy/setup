# Secrets

**No secret values ever go in this repository.** This file records what each environment
needs, where it comes from, and where it lives once obtained. Nothing here should be
sensitive on its own.

## Principles

- Credentials are scoped to a single zone. A token that works in `work` must not exist
  in `personal` or `external`.
- The VPS SSH key lives on the Windows host only, so no zone can reach the VPS.
- GitHub access inside zones is an HTTPS token via `gh`, not an SSH key. Nothing to
  steal from a filesystem, and revoking is a single click.
- `external` gets no credentials at all. If a task there needs one, that task is in the
  wrong zone.

## Per environment

### Windows host

| Secret | Source | Stored |
| --- | --- | --- |
| VPS SSH key | existing key, or `ssh-keygen -t ed25519` | `%USERPROFILE%\.ssh\` |
| GitHub token (`gh` on host) | `gh auth login` | Windows credential keyring |
| BitLocker recovery key | Windows setup | **off-device** — password manager or printed |

The host `gh` login exists only to clone this repo on a fresh machine.

### GitHub tokens — `dev-work` and `dev-personal`

If both zones authenticate as the same GitHub account, separation comes from **two
fine-grained PATs with different repository selections**, not from different identities.

| | `dev-work` | `dev-personal` |
| --- | --- | --- |
| Repository selection | the work zone.s repositories | personal repos |
| Stored | `~/.config/gh/hosts.yml` | same |
| Created | 2026-07-31, 1 year expiry | 2026-07-31, 1 year expiry |

Issue at <https://github.com/settings/personal-access-tokens>, then in the zone run
`gh auth login` and choose **"Paste an authentication token"** — the browser flow cannot
work with interop disabled ([0002](decisions/0002-wsl-conf-hardening.md)).

**Repository permissions to grant:**

| Permission | Level | Why |
| --- | --- | --- |
| Metadata | Read | Mandatory; auto-enables with any other permission |
| Contents | Read and write | clone, fetch, push, commits, branches, tags |
| Pull requests | Read and write | open, review, merge, review comments |
| Issues | Read and write | issues, and PR conversation comments |
| Commit statuses | Read | `gh pr checks`, CI status on PRs |
| Workflows | Read and write | **only** if committing to `.github/workflows/` — without it an ordinary push is rejected |
| Actions | Read | viewing or re-running CI from `gh` |

Not needed: Administration, Webhooks, Environments, Secrets, Pages.

**Verified 2026-07-31:** `dev-work` returns 404 for `<you>/setup` while `dev-personal`
reads it — the scoping produces genuine separation, so a compromise in one zone cannot
reach the other's repositories.

**Consequence:** `dev-work` cannot pull this repo, because `setup` is in the personal
selection and stays there. That is deliberate — widening the work token to reach an
infrastructure repo would weaken the separation for a non-project reason. Zones other than
`personal` are provisioned by pushing from the host with
`hosts/windows/provision-zone.ps1`.

**Expiry:** both tokens lapse around **2027-07-31**. Symptom will be `gh` and `git push`
failing with 401 in that zone. Worth a calendar reminder.

### Other per-zone secrets

| Secret | Zone | Stored |
| --- | --- | --- |
| Project `.env` values | `work`, `personal` | `~/code/<project>/.env`, gitignored |
| Docker registry auth | `work` | `~/.docker/config.json`, only if a private registry is used |

### `dev-external`

None. Clone over HTTPS anonymously. If a repository requires authentication to read,
decide deliberately whether it belongs in `work` or `personal` instead.

### `Ubuntu-26.04` (daily)

None. This zone is for tinkering and has no project credentials by design.

## Recovery

Losing the machine means re-obtaining every item above. Nothing here is recoverable from
this repo, which is the point. The only item that cannot be regenerated is the BitLocker
recovery key — verify it is stored off-device.

## Deferred

Encrypted `.env` handling via `sops` + `age` was considered and deferred; see
[decisions/0010-deferred-hardening.md](decisions/0010-deferred-hardening.md). Until then,
`.env` files are plaintext, gitignored, and confined to their zone.
