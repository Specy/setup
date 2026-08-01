#!/usr/bin/env bash
#
# Install base system packages for a zone. Idempotent - safe to re-run.
#
# MUST run as root:
#     wsl -d dev-work -u root -- /home/dev/setup/env/packages.sh --zone work
#
# Separate from bootstrap.sh on purpose: this needs root, bootstrap.sh configures
# the user's own environment and must not. Keeping them apart means bootstrap.sh
# never prompts for a password.
#
# Must work on native Linux as well as inside WSL.

set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ENV_DIR/lib/config.sh"

ZONE=""
CHANGES=0

log()     { printf '    %s\n' "$*"; }
changed() { printf '  + %s\n' "$*"; CHANGES=$((CHANGES + 1)); }
section() { printf '\n%s\n' "$*"; }
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--zone) ZONE="${2:-}"; shift 2 ;;
		-h|--help) printf 'Usage: packages.sh --zone <daily|work|personal|external>\n'; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
done

[[ -n "$ZONE" ]] || die "--zone is required"
cfg_require >/dev/null || die "config.json is required"
[[ -n "$(cfg_zone_field "$ZONE" uid)" ]] || die "zone '$ZONE' is not defined in config.json"

[[ "$(id -u)" -eq 0 ]] || die "must run as root (wsl -d <distro> -u root -- ...)"

export DEBIAN_FRONTEND=noninteractive

apt_install() {
	local missing=()
	for pkg in "$@"; do
		if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
			missing+=("$pkg")
		fi
	done
	if [[ ${#missing[@]} -eq 0 ]]; then
		log "already installed: $*"
		return
	fi
	apt-get install -y -qq "${missing[@]}" >/dev/null
	changed "installed: ${missing[*]}"
}

printf 'Installing packages for zone: %s\n' "$ZONE"

section 'Base packages'
apt-get update -qq >/dev/null
# bubblewrap: unprivileged sandboxing, used by env/sandbox/sandbox.sh.
# Installed everywhere because it is tiny, but only wired into daily use in
# external. See decisions/0008-agent-execution-boundary.md.
apt_install ca-certificates curl wget gnupg unzip jq bubblewrap

# ---------------------------------------------------------------------------
section 'GitHub CLI'
# Zones with "github": false hold no credentials, so they have no use for gh.
# See SECRETS.md and decisions/0006-credential-placement.md.
if [[ "$(cfg_zone_field "$ZONE" github)" != "true" ]]; then
	log "skipped for '$ZONE' - this zone holds no GitHub credentials"
else
	# GitHub's own signed apt repository rather than Ubuntu's archive, which
	# carries a version roughly two years old. gh holds auth tokens and talks to a
	# live API, so staleness is a real cost. This is a signed repo with a pinned
	# keyring, not curl | bash. See decisions/0017-github-cli-source.md.
	keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
	listfile=/etc/apt/sources.list.d/github-cli.list

	if [[ -f "$keyring" && -f "$listfile" ]]; then
		log 'apt repository already configured'
	else
		install -d -m 0755 /etc/apt/keyrings
		wget -nv -O "$keyring" https://cli.github.com/packages/githubcli-archive-keyring.gpg
		chmod go+r "$keyring"
		printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
			"$(dpkg --print-architecture)" "$keyring" > "$listfile"
		apt-get update -qq >/dev/null
		changed 'configured GitHub CLI apt repository'
	fi
	apt_install gh
fi

# ---------------------------------------------------------------------------
section 'mise'
# Runtime version manager - see decisions/0011-toolchain-management.md.
# Not in Ubuntu's archive, and mise's advertised installer is a piped shell script,
# which 0011 rules out. Its signed apt repository is the verifiable equivalent, on
# the same reasoning as decisions/0017-github-cli-source.md.
#
# Every zone gets it, including external: building untrusted code is exactly where
# pinned, per-project runtimes matter.
mise_keyring=/etc/apt/keyrings/mise-archive-keyring.gpg
mise_list=/etc/apt/sources.list.d/mise.list

if [[ -f "$mise_keyring" && -f "$mise_list" ]]; then
	log 'apt repository already configured'
else
	install -d -m 0755 /etc/apt/keyrings
	wget -qO - https://mise.jdx.dev/gpg-key.pub | gpg --dearmor > "$mise_keyring"
	chmod go+r "$mise_keyring"
	printf 'deb [signed-by=%s arch=%s] https://mise.jdx.dev/deb stable main\n' \
		"$mise_keyring" "$(dpkg --print-architecture)" > "$mise_list"
	apt-get update -qq >/dev/null
	changed 'configured mise apt repository'
fi
apt_install mise

# ---------------------------------------------------------------------------
section 'Rust'
# rustup rather than mise, deliberately - see decisions/0019-rust-via-rustup.md.
# From Ubuntu's archive, so no extra trust root.
#
# Only zones with "rust": true in config.json. The toolchain is around a gigabyte
# and disk is not reclaimed automatically (decisions/0014-no-sparse-vhd.md), so
# installing it where it is unused is a real cost.
if [[ "$(cfg_zone_field "$ZONE" rust)" == "true" ]]; then
	apt_install rustup
else
	log "skipped for '$ZONE' - rust is not enabled for this zone in config.json"
fi

# ---------------------------------------------------------------------------
# Optional per-user extension point, run as root. See overrides/README.md.
_override="$(cd "$ENV_DIR/.." && pwd)/overrides/env/packages.sh"
if [[ -x "$_override" ]]; then
	section 'Overrides'
	"$_override" --zone "$ZONE" || die "override packages failed"
	CHANGES=$((CHANGES + 1))
fi

# ---------------------------------------------------------------------------
section 'Summary'
if [[ "$CHANGES" -eq 0 ]]; then
	log 'nothing to change'
else
	log "$CHANGES change(s) applied"
fi

if command -v gh >/dev/null 2>&1; then
	printf '\ngh %s\n' "$(gh --version | head -1 | awk '{print $3}')"
fi
