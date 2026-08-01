# 0020 — Agent history follows the project into its zone

- **Status:** Accepted
- **Date:** 2026-08-01

## Context

Claude Code and Codex both key conversation history on the project's **working directory**.
Moving projects from `C:\Users\<you>\Desktop\projects\<group>\<repo>` to
`/home/dev/code/<repo>` ([0007](0007-code-on-ext4.md)) therefore orphaned every existing
conversation: the history was still on the host, attached to paths that no longer exist,
and invisible from the zone where the project now lives.

Roughly 150 Codex threads and 30 Claude sessions were affected — months of context.

## Decision

Migrate each conversation into the zone that owns its project, rewriting paths so the
history is both discoverable and internally coherent. Implemented in
[`hosts/windows/session-restore/`](../hosts/windows/session-restore/).

| Zone | Claude sessions | Codex threads |
| --- | --- | --- |
| `dev-work` | 9 across 5 projects | 29 |
| `dev-personal` | 22 across 4 projects | 91 |
| `dev-external` | none | none |

History for directories that were never migrated stays on the host. Nothing is deleted from
the host — the migration copies.

**The zone boundary applies to history too.** A conversation is routed by the project it
belongs to, so work conversations exist only in `dev-work`. This matters more than it first
appears: transcripts quote source, credentials, and internal discussion. Copying everything
everywhere would have leaked across the boundary the whole setup exists to maintain, which
is also why the shared Codex memory databases were **not** migrated.

## What made this non-trivial

Copying files was not enough, in two separate ways.

**Codex keeps a separate index.** `codex resume` populates its picker from the `threads`
table in `~/.codex/state_5.sqlite`, holding `cwd` and an absolute `rollout_path`. Rollout
files alone are present but invisible. The table is filtered and rewritten per zone.

**And that index cannot simply be transplanted.** Copying the rebuilt database into the
zone appeared to work, then codex refused to start:

```
Codex couldn't start because its local database appears to be damaged.
migration 1 was previously applied but has been modified
```

codex validates sqlx migration checksums, so a database written by a different codex build
is rejected — even though the schema was byte-for-byte compatible, 34 columns on both
sides. The data was never the problem.

The working sequence is therefore: let codex create its own database, then insert the rows
into it. `import-codex-threads.sh` does this. Also worth knowing: `codex doctor`, which the
error message recommends, does **not** create the database. `codex resume --last` does.

**Transcripts refer to paths that predate the current layout.** Beyond the live `cwd`, they
referenced `Desktop\progetti\<repo>`, `Desktop\progetti\<group>\<repo>`, bare
`Desktop\<repo>`, and one project under an older name. Over 52,000 stale references were
rewritten, so a resumed agent is not handed paths that no longer exist and does not waste a
turn discovering that.

## Verification

The Claude directory-name encoding — non-alphanumeric characters replaced with `-`, so
`/home/dev/code/<repo>` becomes `-home-dev-code-<repo>` — was **tested, not assumed**. Running
`claude -p` in `~/code/<repo>` after the restore created no new directory and appended its
session to the restored one.

For Codex, every indexed thread was checked against the filesystem: 29/29 in `work` and
91/91 in `personal` resolve to a rollout file that exists, with zero remaining Windows
`cwd` values.

## Rejected alternatives

**Leave history on the host and run agents there.** Would defeat
[0008](0008-agent-execution-boundary.md) entirely.

**Copy everything to every zone.** Simpler, and it puts work transcripts inside `external`.

**Start fresh.** The cost is invisible until the moment you want the context back, at which
point it is unrecoverable.

## What would change this

Either tool moving to a project-relative or content-addressed history store would make the
path rewriting unnecessary. Until then, any future move of `~/code` needs the same
treatment — which is the reason the scripts and their gotchas are kept rather than
discarded as one-off work.
