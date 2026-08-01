#!/usr/bin/env bash
#
# Import migrated Codex threads into a database that THIS build of codex created.
# Run inside the zone, as the zone user. Idempotent.
#
#     ~/setup/hosts/windows/session-restore/import-codex-threads.sh
#
# WHY THIS EXISTS
#
# Copying state_5.sqlite from another machine looks like it works and then codex
# refuses to start:
#
#   Codex couldn't start because its local database appears to be damaged.
#   migration 1 was previously applied but has been modified
#
# codex validates sqlx migration checksums. A database written by a different
# codex build carries different checksums, and it is rejected even when the
# schema is identical - on this machine both were 34 columns, so nothing about
# the data was wrong.
#
# The fix is to never transplant the file. Let codex create its own database,
# then insert the rows.

set -uo pipefail

CODEX="$HOME/.codex"
FRESH="$CODEX/state_5.sqlite"
SAVED="$CODEX/state_5.imported.sqlite"

command -v codex >/dev/null 2>&1 || { echo "codex not installed" >&2; exit 1; }

cd "$CODEX" || exit 1

# Keep the transplanted database once; re-runs reuse it as the source.
if [[ ! -f "$SAVED" && -f "$FRESH" ]]; then
	mv "$FRESH" "$SAVED"
	echo "  set aside the transplanted DB as $(basename "$SAVED")"
fi
[[ -f "$SAVED" ]] || { echo "  nothing to import: $SAVED not found" >&2; exit 1; }

rm -f "$FRESH" "$FRESH-wal" "$FRESH-shm"

# `codex doctor` does NOT create the database; this does. stdin is closed because
# it would otherwise wait on a terminal.
timeout 30 codex resume --last >/dev/null 2>&1 </dev/null || true
[[ -f "$FRESH" ]] || { echo "  codex did not create a database" >&2; exit 1; }
echo "  codex created a fresh database with its own migrations"

python3 - <<'PY'
import sqlite3, pathlib, os
h = pathlib.Path.home()/".codex"
fresh = sqlite3.connect(str(h/"state_5.sqlite"))
old   = sqlite3.connect(str(h/"state_5.imported.sqlite"))
fresh.row_factory = old.row_factory = sqlite3.Row

fcols = [r[1] for r in fresh.execute("PRAGMA table_info(threads)")]
ocols = [r[1] for r in old.execute("PRAGMA table_info(threads)")]
common = [c for c in fcols if c in ocols]
missing = [c for c in fcols if c not in ocols]
if missing:
    print("  columns only in the new schema, left at their defaults: " + ", ".join(missing))

rows = old.execute("SELECT %s FROM threads" % ",".join('"%s"' % c for c in common)).fetchall()
sql = "INSERT OR REPLACE INTO threads (%s) VALUES (%s)" % (
    ",".join('"%s"' % c for c in common), ",".join("?" for _ in common))
n = 0
for r in rows:
    try:
        fresh.execute(sql, tuple(r[c] for c in common)); n += 1
    except Exception as e:
        print("  stopped at a row: %s" % e); break
fresh.commit()

total = fresh.execute("SELECT COUNT(*) FROM threads").fetchone()[0]
bad = [r["rollout_path"] for r in fresh.execute("SELECT rollout_path FROM threads")
       if not os.path.exists(r["rollout_path"])]
print("  imported %d/%d threads" % (n, len(rows)))
print("  rollout files present: %d/%d" % (total - len(bad), total))
if bad:
    print("  MISSING e.g. %s" % bad[0])
fresh.close(); old.close()
PY

echo "  done - start codex normally from a project directory"
