#!/usr/bin/env bash
#
# Clone a zone's repositories from config.json into ~/code. Idempotent.
#
#     ~/setup/env/clone-repos.sh --zone work
#
# Runs as the zone user. Code lives on the native filesystem, never under /mnt -
# see decisions/0007-code-on-ext4.md.
#
# Zones with "github": false hold no credentials by design, so their entries must
# be marked "anonymous": true and be publicly readable. See decisions/0006.

set -uo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ENV_DIR/lib/config.sh"

ZONE=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--zone) ZONE="${2:-}"; shift 2 ;;
		-h|--help) printf 'Usage: clone-repos.sh --zone <name>\n'; exit 0 ;;
		*) printf 'unknown argument: %s\n' "$1" >&2; exit 1 ;;
	esac
done

if [[ -z "$ZONE" ]]; then
	ZONE="$(cat "$HOME/.zone" 2>/dev/null || true)"
fi
[[ -n "$ZONE" ]] || { printf 'error: --zone is required (and ~/.zone is unset)\n' >&2; exit 1; }

cfg_require >/dev/null || exit 1

HAS_GH="$(cfg_zone_field "$ZONE" github)"
mkdir -p "$HOME/code"
cd "$HOME/code" || exit 1

printf 'Cloning repositories for zone: %s\n' "$ZONE"

cloned=0; present=0; failed=0
while IFS=$'\t' read -r remote dir anon; do
	[[ -n "$remote" ]] || continue

	if [[ -d "$dir/.git" ]]; then
		printf '    %-24s already present\n' "$dir"
		present=$((present + 1))
		continue
	fi

	# A zone without a GitHub login can only take public repositories, and only
	# over anonymous HTTPS. Fail loudly rather than prompting for credentials
	# that this zone is not supposed to have.
	if [[ "$anon" != "true" && "$HAS_GH" != "true" ]]; then
		printf '  ! %-24s needs credentials, but zone "%s" has github:false\n' "$dir" "$ZONE" >&2
		printf '    mark it "anonymous": true in config.json, or move it to another zone\n' >&2
		failed=$((failed + 1))
		continue
	fi

	if [[ "$anon" == "true" ]]; then
		ok=0
		git clone --quiet "https://github.com/$remote.git" "$dir" 2>/dev/null && ok=1
	else
		ok=0
		if command -v gh >/dev/null 2>&1; then
			gh repo clone "$remote" "$dir" -- --quiet 2>/dev/null && ok=1
		else
			printf '  ! %-24s gh not installed - run env/packages.sh as root\n' "$dir" >&2
		fi
	fi

	if [[ "$ok" -eq 1 ]]; then
		printf '  + %-24s cloned from %s\n' "$dir" "$remote"
		cloned=$((cloned + 1))
	else
		printf '  ! %-24s FAILED (%s)\n' "$dir" "$remote" >&2
		failed=$((failed + 1))
	fi
done < <(cfg_zone_repos "$ZONE")

printf '\n  %d cloned, %d already present, %d failed\n' "$cloned" "$present" "$failed"
[[ "$failed" -eq 0 ]]
