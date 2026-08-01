# Shared config reader for the in-zone scripts. Source it:
#
#     . "$ENV_DIR/lib/config.sh"
#     if [[ "$(cfg_zone_field "$ZONE" rust)" == "true" ]]; then ...
#
# Uses python3, not jq: jq is installed BY packages.sh, so depending on it here
# would be a bootstrap ordering problem. python3 ships with Ubuntu.

# Resolve config.json relative to the repo root, unless SETUP_CONFIG overrides it.
_cfg_file() {
	if [[ -n "${SETUP_CONFIG:-}" ]]; then printf '%s' "$SETUP_CONFIG"; return; fi
	local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
	printf '%s' "$here/config.json"
}

cfg_require() {
	local f; f="$(_cfg_file)"
	if [[ ! -f "$f" ]]; then
		printf 'error: config.json not found at %s\n' "$f" >&2
		printf 'hint: copy config.example.json to config.json and edit it\n' >&2
		return 1
	fi
	command -v python3 >/dev/null 2>&1 || { printf 'error: python3 not found\n' >&2; return 1; }
	printf '%s' "$f"
}

# cfg_zone_field <zone> <field> -> value on stdout, empty if absent.
# Booleans come back as "true"/"false" so callers can compare as strings.
cfg_zone_field() {
	local f; f="$(cfg_require)" || return 1
	python3 - "$f" "$1" "$2" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
zones = [z for z in cfg.get("zones", []) if z.get("name") == sys.argv[2]]
if not zones:
    sys.exit(0)
v = zones[0].get(sys.argv[3])
if v is None:
    pass
elif isinstance(v, bool):
    print("true" if v else "false")
else:
    print(v)
PY
}

# cfg_field <dotted.path> -> value on stdout, e.g. cfg_field git.email
cfg_field() {
	local f; f="$(cfg_require)" || return 1
	python3 - "$f" "$1" <<'PY'
import json, sys
cur = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    if not isinstance(cur, dict) or part not in cur:
        sys.exit(0)
    cur = cur[part]
if isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is not None:
    print(cur)
PY
}

# cfg_zone_repos <zone> -> one "remote<TAB>dir<TAB>anonymous" line per repository.
cfg_zone_repos() {
	local f; f="$(cfg_require)" || return 1
	python3 - "$f" "$1" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
for z in cfg.get("zones", []):
    if z.get("name") != sys.argv[2]:
        continue
    for r in z.get("repos", []):
        if isinstance(r, str):
            remote, d, anon = r, r.split("/")[-1], False
        else:
            remote = r["remote"]
            d = r.get("dir") or remote.split("/")[-1]
            anon = bool(r.get("anonymous"))
        print("%s\t%s\t%s" % (remote, d, "true" if anon else "false"))
PY
}
