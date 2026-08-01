# Restoring agent conversation history into the zones

One-off migration, run 2026-08-01, moving Claude Code and Codex history from the Windows
host into the zone that owns each project. Kept because a future reset would need it again,
and because the gotchas below cost real time to find.

Both tools key their history on the project's **working directory**. Moving projects from
`C:\Users\<you>\Desktop\projects\<group>\<repo>` to `/home/dev/code/<repo>` therefore
orphans every conversation until the paths are rewritten.

## What was moved

| Zone | Claude sessions | Codex threads |
| --- | --- | --- |
| `dev-work` | 9 across 5 projects | 29 |
| `dev-personal` | 22 across 4 projects | 91 |
| `dev-external` | none | none |

Left on the host: history for any directory that was never migrated.
`casa`, `Desktop\notes-fisica`, `physics`, `test2`, `TODO`, and the `Desktop\projects`
session in which this environment was built.

## The three parts

**1. Claude Code — `stage-sessions.ps1`**

History lives in `~/.claude/projects/<encoded-cwd>/`, where the encoding is the working
directory with every non-alphanumeric character replaced by `-`. So
`C:\Users\<you>\Desktop\projects\personal\<repo>` is stored as
`C--Users-<you>-Desktop-projects-personal-<repo>`, and the destination is
`-home-dev-code-<repo>`.

**Verified empirically rather than assumed**: running `claude -p` in `~/code/<repo>` after
the restore created no new directory and added its session to the restored one.

**2. Codex rollouts — `stage-sessions.ps1`**

Rollouts live in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. The first line is a
`session_meta` record carrying `cwd`, which is what routes each file to a zone. The
directory layout is preserved as-is.

**3. Codex thread index — `rebuild-codex-index.py`, then `import-codex-threads.sh`**

Copying rollout files is **not sufficient**. `codex resume` reads its picker from the
`threads` table in `~/.codex/state_5.sqlite`, which stores `cwd` and an absolute
`rollout_path`. Without rebuilding it, the files are present and invisible.

`rebuild-codex-index.py` filters that table per zone and rewrites both columns.

**Then do not transplant the resulting file into the zone.** Doing so appears to work and
codex refuses to start:

```
Codex couldn't start because its local database appears to be damaged.
migration 1 was previously applied but has been modified
```

codex validates sqlx migration checksums, and a database written by a different codex build
carries different ones. It is rejected even when the schema is identical — here both sides
had the same 34 columns, so nothing about the data was wrong.

`import-codex-threads.sh` is the correct final step, run inside the zone: it sets the
transplanted database aside, lets codex create its own with matching checksums, and inserts
the rows into that. Note `codex doctor` does **not** create the database —
`codex resume --last` does.

## Gotchas, all of which bit

**The database is mostly WAL.** `state_5.sqlite` on its own has no `threads` table — the
data lives in `state_5.sqlite-wal`. Consequences:

- Copy `.sqlite`, `-wal` **and** `-shm` together.
- Do **not** run `PRAGMA wal_checkpoint` on the copy. With a `-shm` carried over from
  another machine the checkpoint discards the data and the table vanishes.
- Everything must happen inside **one connection**: take `src.backup(dst)` for every zone
  first, then close. Closing and reopening loses the WAL contents.

**`/tmp` is a tmpfs and the VM idles out.** `vmIdleTimeout` is 60s, so staging files under
`/tmp` between two commands can find them gone. Stage under `~/.cache/`.

**Cross-distro binary pipes drop data.** Piping `wsl -d a -- cat file | wsl -d b -- cat >`
produced a 0-byte result. Build each zone's database inside that zone instead.

**PowerShell pipelines corrupt binary.** Same reason `provision-zone.ps1` stages through a
tar file and uses `cmd`'s redirection. From Git Bash, `cat` piping works.

**Paths inside transcripts predate the current layout.** Beyond the live `cwd`, transcripts
referenced `Desktop\progetti\<repo>`, `Desktop\progetti\<group>\<repo>`, bare
`Desktop\<repo>`, and one project under an older name. Over 52,000 stale
references were rewritten so a resumed agent is not told to read paths that no longer
exist.

## Not migrated

`memories_1.sqlite`, `goals_1.sqlite` and `logs_2.sqlite` reference threads but hold
cross-project state that has no clean per-zone split. They stay on the host. If Codex
memories matter later, they need a deliberate decision about which zone should own them —
copying them everywhere would leak personal context into `work`.
