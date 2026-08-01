#!/usr/bin/env python3
"""Rewrite old Windows project paths inside restored agent transcripts.

    python3 rewrite-legacy-paths.py ~/setup/config.json [old-group ...]

Run inside a zone, after the transcripts have been transferred.

Beyond the live `cwd`, transcripts quote file paths from wherever the projects
used to live. A resumed agent handed those paths tries to read them, finds them
gone, and wastes a turn - so they are rewritten to the new location.

Repository names and the Windows username come from config.json. The optional
"old group" arguments are the folder names that used to sit between the projects
root and each repository:

    C:\\Users\\<you>\\Desktop\\projects\\work\\<repo>   ->  old group "work"

Pass every layout the transcripts might mention, including ones you have since
renamed. Transcripts outlive directory structures, and on the machine this was
written for they referenced three different layouts going back two renames.
"""
import json, pathlib, re, sys

if len(sys.argv) < 2:
    sys.exit(__doc__)

cfg = json.load(open(sys.argv[1], encoding="utf-8"))
groups = sys.argv[2:] or [z["name"] for z in cfg.get("zones", [])]

repos = []
for z in cfg.get("zones", []):
    for r in z.get("repos", []):
        repos.append(r.split("/")[-1] if isinstance(r, str)
                     else (r.get("dir") or r["remote"].split("/")[-1]))
if not repos:
    sys.exit("no repositories in config.json")

user = cfg["windowsUser"]
B    = chr(92)
bs   = re.escape(B)
sep  = "(?:" + bs + bs + "|" + bs + "|/)"          # matches \\ or \ or /
U    = "C:" + sep + "Users" + sep + re.escape(user) + sep + "Desktop" + sep

# Most specific prefix first - regex alternation is ordered.
alts  = [U + "projects" + sep + re.escape(g) + sep for g in groups]
alts += [U + re.escape(g) + sep for g in groups]
alts += [U + "projects" + sep, U]
prefixes = "(?:" + "|".join(alts) + ")"

trailing = "((?:(?:" + bs + bs + "|" + bs + "|/)[A-Za-z0-9_.@+-]+)*)"
pats = [(re.compile(prefixes + re.escape(name) + trailing), name)
        for name in sorted(set(repos), key=len, reverse=True)]


def fix(m, repo):
    tail = (m.group(1) or "").replace(B + B, "/").replace(B, "/")
    return "/home/dev/code/" + repo + tail


changed = 0
for root in (pathlib.Path.home() / ".claude" / "projects",
             pathlib.Path.home() / ".codex" / "sessions"):
    if not root.exists():
        continue
    for p in root.rglob("*"):
        if not p.is_file() or p.suffix not in (".jsonl", ".json", ".md", ".txt"):
            continue
        try:
            t = p.read_text(encoding="utf-8", errors="surrogateescape")
        except Exception:
            continue
        o = t
        for pat, repo in pats:
            t = pat.sub(lambda m, r=repo: fix(m, r), t)
        if t != o:
            p.write_text(t, encoding="utf-8", errors="surrogateescape")
            changed += 1
print("  rewrote %d file(s)" % changed)
