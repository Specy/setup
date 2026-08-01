#!/usr/bin/env python3
"""Split the Codex thread index per zone, rewriting cwd and rollout paths.

    python3 rebuild-codex-index.py <config.json> <state_5.sqlite> <outdir>

Produces <outdir>/state_5.<zone>.sqlite for each zone.

DO NOT then copy those files into the zones. codex validates sqlx migration
checksums and rejects a database written by a different codex build, even when
the schema is identical. Use import-codex-threads.sh, which lets codex create its
own database and inserts these rows into it.

Two traps in the source database, both of which cost real time:

  * The data is mostly in state_5.sqlite-wal, so copy the .sqlite, -wal AND -shm
    together, and never run PRAGMA wal_checkpoint on the copy - with a -shm from
    another machine it discards the data and the threads table vanishes.
  * Everything must happen in ONE connection. Take src.backup(dst) for every zone
    before closing, because closing and reopening loses the WAL contents.
"""
import json, os, re, sqlite3, sys

if len(sys.argv) < 4:
    sys.exit(__doc__)

CFG, SRC, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
B = chr(92)

cfg = json.load(open(CFG, encoding="utf-8"))
repo_zone = {}
for z in cfg.get("zones", []):
    for r in z.get("repos", []):
        d = r.split("/")[-1] if isinstance(r, str) else (r.get("dir") or r["remote"].split("/")[-1])
        repo_zone[d] = z["name"]
zones = [z["name"] for z in cfg.get("zones", [])]
groups = "|".join(re.escape(g) for g in zones)

src = sqlite3.connect(SRC)
src.row_factory = sqlite3.Row
outs = {}
for z in zones:                                   # all backups BEFORE any close
    p = os.path.join(OUT, "state_5.%s.sqlite" % z)
    if os.path.exists(p):
        os.remove(p)
    d = sqlite3.connect(p)
    src.backup(d)
    outs[z] = (p, d)
print("  backups taken with data visible: threads=%d"
      % src.execute("SELECT COUNT(*) FROM threads").fetchone()[0])
src.close()


def repo_of(cwd):
    if not cwd:
        return None
    n = cwd.replace("/", B)
    m = re.search(r"Desktop" + re.escape(B) + r"proje(?:cts|tti)" + re.escape(B)
                  + r"(?:" + groups + r")" + re.escape(B)
                  + r"([^" + re.escape(B) + r"]+)", n)
    return m.group(1) if (m and m.group(1) in repo_zone) else None


for z, (p, d) in outs.items():
    d.row_factory = sqlite3.Row
    keep, drop = [], []
    for r in d.execute("SELECT id,cwd,rollout_path FROM threads"):
        rp = repo_of(r["cwd"])
        (keep if (rp and repo_zone[rp] == z) else drop).append((r["id"], rp, r["rollout_path"]))
    for row in drop:
        d.execute("DELETE FROM threads WHERE id=?", (row[0],))
    for tid, rp, path in keep:
        t = path.replace(B, "/")
        i = t.find("/sessions/")
        d.execute("UPDATE threads SET cwd=?,rollout_path=? WHERE id=?",
                  ("/home/dev/code/" + rp, "/home/dev/.codex" + t[i:] if i >= 0 else t, tid))
    for tbl, col in (("thread_dynamic_tools", "thread_id"), ("thread_spawn_edges", "parent_thread_id")):
        try:
            d.execute("DELETE FROM %s WHERE %s NOT IN (SELECT id FROM threads)" % (tbl, col))
        except Exception:
            pass
    d.commit()
    d.execute("VACUUM")
    d.commit()
    n = d.execute("SELECT COUNT(*) FROM threads").fetchone()[0]
    d.close()
    print("  %-9s %3d kept  %3d dropped  (%.0f KB)" % (z, n, len(drop), os.path.getsize(p) / 1024))
