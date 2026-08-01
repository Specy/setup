#!/usr/bin/env bash
#
# Assert that this environment matches what the repo says it should be.
#
#     ./verify/verify.sh [--zone <name>]
#
# Zone is read from ~/.zone when not given. Exits non-zero if any check fails.
#
# Documentation rots silently; assertions fail loudly. Every config that matters
# should have a check here — see AGENTS.md.

# Deliberately no -e: a failed check must not stop the remaining checks.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO_ROOT/env/lib/config.sh"

ZONE=""
PASS=0
FAIL=0
SKIP=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--zone) ZONE="${2:-}"; shift 2 ;;
		-h|--help) printf 'Usage: verify.sh [--zone <daily|work|personal|external>]\n'; exit 0 ;;
		*) printf 'unknown argument: %s\n' "$1" >&2; exit 1 ;;
	esac
done

if [[ -z "$ZONE" ]]; then
	if [[ -f "$HOME/.zone" ]]; then
		ZONE="$(cat "$HOME/.zone")"
	else
		printf 'error: no --zone given and ~/.zone does not exist\n' >&2
		printf 'hint: run env/bootstrap.sh --zone <name> first\n' >&2
		exit 1
	fi
fi

ok()   { printf '  PASS  %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
skip() { printf '  SKIP  %s (%s)\n' "$1" "$2"; SKIP=$((SKIP + 1)); }

is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; }
is_dev_zone() { [[ "$ZONE" != "daily" ]]; }

# Test the mount table, NOT whether /mnt/c exists.
#
# A distro launched once before its wsl.conf was applied keeps an EMPTY /mnt/c
# directory afterwards. `[[ -d /mnt/c ]]` is therefore true even when automount is
# correctly disabled and no Windows filesystem is reachable — a false failure in a
# dev zone, and worse, a false pass in daily if automount ever silently broke.
#
# A real mount looks like:  C:\134 /mnt/c 9p rw,...aname=drvfs;path=C:\...
windows_drive_mounted() {
	grep -qE '^[^ ]+ /mnt/[a-z] ' /proc/mounts 2>/dev/null
}

printf 'Verifying zone: %s\n' "$ZONE"
if is_wsl; then
	printf 'Platform: WSL (%s)\n\n' "${WSL_DISTRO_NAME:-unknown}"
else
	printf 'Platform: native Linux — WSL-specific checks will be skipped\n\n'
fi

# ---------------------------------------------------------------------------
printf 'Isolation\n'

# Interop is disabled in EVERY zone, including the daily driver: a distro that can
# execute wsl.exe can read every other distro's filesystem with no password.
# See decisions/0002-wsl-conf-hardening.md.
if is_wsl; then
	if compgen -G '/proc/sys/fs/binfmt_misc/WSLInterop*' >/dev/null; then
		bad 'Windows interop is ENABLED (binfmt handler registered) — expected disabled'
	else
		ok 'Windows interop disabled'
	fi
else
	skip 'Windows interop disabled' 'not WSL'
fi

# Dev zones must not mount the Windows filesystem; the daily driver keeps it.
if is_wsl; then
	if is_dev_zone; then
		if windows_drive_mounted; then
			bad 'a Windows drive is mounted — dev zones must have automount disabled'
		else
			ok 'no Windows drive mounted'
		fi
	else
		if windows_drive_mounted; then
			ok 'Windows drive mounted (expected in the daily zone)'
		else
			bad 'no Windows drive mounted — the daily zone is meant to keep automount'
		fi
	fi
else
	skip 'Windows filesystem mount' 'not WSL'
fi

# No Windows tooling on PATH, so agents cannot resolve npm.cmd / git.exe.
if is_dev_zone; then
	if printf '%s' "$PATH" | grep -q '/mnt/c'; then
		bad 'PATH contains Windows paths — expected appendWindowsPath = false'
	else
		ok 'PATH free of Windows paths'
	fi
else
	skip 'PATH free of Windows paths' 'daily zone'
fi

# ---------------------------------------------------------------------------
printf '\nEnvironment\n'

# Each zone must use a distinct uid: systemd's user@<uid>.service collides across
# distros on the uid, and every zone after the first to claim one fails with EBUSY
# for the life of that boot. See decisions/0016-systemd-user-manager.md.
want_uid="$(cfg_zone_field "$ZONE" uid 2>/dev/null)"
if [[ -z "$want_uid" && "$ZONE" == "$(cfg_field daily.distro 2>/dev/null | tr '[:upper:]' '[:lower:]')" ]]; then
	want_uid="$(cfg_field daily.uid 2>/dev/null)"
fi
have_uid="$(id -u)"

if [[ -z "$want_uid" ]]; then
	skip 'zone uid' "no expectation recorded for '$ZONE'"
elif [[ "$have_uid" == "$want_uid" ]]; then
	ok "uid is $have_uid as expected for '$ZONE'"
else
	bad "uid is $have_uid but '$ZONE' expects $want_uid — will collide with another zone"
fi

if command -v systemctl >/dev/null 2>&1; then
	if [[ "$(systemctl is-active "user@${have_uid}.service" 2>/dev/null)" == "active" ]]; then
		ok "systemd user manager active (user@${have_uid})"
	else
		bad "user@${have_uid}.service is not active — systemctl --user will not work"
	fi
else
	skip 'systemd user manager' 'systemctl not present'
fi

if [[ -f "$HOME/.zone" ]]; then
	if [[ "$(cat "$HOME/.zone")" == "$ZONE" ]]; then
		ok "zone marker is '$ZONE'"
	else
		bad "zone marker is '$(cat "$HOME/.zone")' but verifying as '$ZONE'"
	fi
else
	bad '~/.zone missing — run env/bootstrap.sh'
fi

if [[ -d "$HOME/code" ]]; then
	ok '~/code exists'
else
	bad '~/code missing — run env/bootstrap.sh'
fi

# Nothing should be worked on from /mnt: slow, and outside the boundary.
# See decisions/0007-code-on-ext4.md.
if is_wsl && [[ -d "$HOME/code" ]]; then
	if find "$HOME/code" -maxdepth 1 -type l -lname '/mnt/*' 2>/dev/null | grep -q .; then
		bad '~/code contains symlinks into /mnt — code must live on the native filesystem'
	else
		ok '~/code has no links into /mnt'
	fi
fi

# ---------------------------------------------------------------------------
printf '\nSupply chain\n'

# See decisions/0005-npm-ignore-scripts.md.
if command -v npm >/dev/null 2>&1; then
	if [[ "$(npm config get ignore-scripts 2>/dev/null)" == "true" ]]; then
		ok 'npm ignore-scripts = true'
	else
		bad 'npm ignore-scripts is NOT true — lifecycle scripts will execute on install'
	fi
else
	skip 'npm ignore-scripts' 'npm not installed'
fi

if git config --global --get-all include.path 2>/dev/null | grep -qxF '~/.gitconfig.common'; then
	ok 'git includes ~/.gitconfig.common'
else
	bad 'git include.path not set — run env/bootstrap.sh'
fi

# NOT --global. `git config --global --get` reads the global file itself and does
# NOT follow include.path, so settings that live in ~/.gitconfig.common are invisible
# to it. Reading the merged config is also the more meaningful assertion: it is the
# value git will actually use. Anchored to $HOME so a repo-local override in the
# current directory cannot mask the answer.
if [[ "$(git -C "$HOME" config --get transfer.fsckobjects 2>/dev/null)" == "true" ]]; then
	ok 'git object integrity checking enabled'
else
	bad 'git transfer.fsckobjects not enabled'
fi

# ---------------------------------------------------------------------------
printf '\nTooling\n'

# Second isolation layer. See decisions/0008-agent-execution-boundary.md.
if [[ -x "$HOME/.local/bin/sandbox" ]]; then
	ok 'sandbox installed'
else
	bad 'sandbox missing — run env/bootstrap.sh'
fi

if command -v bwrap >/dev/null 2>&1; then
	ok 'bubblewrap present'
else
	bad 'bubblewrap not installed — run env/packages.sh as root'
fi

# Backstop against prompt injection reading credentials. Not the boundary.
if [[ -f "$HOME/.claude/settings.json" ]] && grep -q '"deny"' "$HOME/.claude/settings.json" 2>/dev/null; then
	ok 'claude deny-list present'
else
	bad 'claude deny-list missing — run env/bootstrap.sh'
fi

# Agent CLIs come from env/agents.sh, which is a separate step because it is slow.
# Asserted rather than skipped: a zone without them is not fully provisioned.
for agent in claude codex gemini; do
	if command -v "$agent" >/dev/null 2>&1 && "$agent" --version >/dev/null 2>&1; then
		ok "$agent working"
	elif command -v "$agent" >/dev/null 2>&1; then
		bad "$agent installed but not working — run env/agents.sh"
	else
		bad "$agent not installed — run env/agents.sh"
	fi
done

# Rust and Docker are asserted BOTH ways: present where config.json enables them,
# and absent where it does not. A zone quietly acquiring a toolchain it should not
# have is drift, and drift is what this script exists to catch.
if [[ "$(cfg_zone_field "$ZONE" rust 2>/dev/null)" == "true" ]]; then
	if command -v cargo >/dev/null 2>&1; then
		ok "rust present ($(rustc --version 2>/dev/null | cut -d' ' -f2))"
	else
		bad 'rust missing — run env/packages.sh as root, then env/bootstrap.sh'
	fi
else
	if command -v cargo >/dev/null 2>&1; then
		bad "rust installed in '$ZONE', which does not enable it — see decisions/0019"
	else
		ok "no rust, as expected for '$ZONE'"
	fi
fi

# See decisions/0004-no-docker-desktop.md and 0018-docker-in-work-zone.md.
if [[ "$(cfg_zone_field "$ZONE" docker 2>/dev/null)" == "true" ]]; then
	if ! command -v docker >/dev/null 2>&1; then
		bad 'docker missing — see decisions/0018-docker-in-work-zone.md'
	elif docker info >/dev/null 2>&1; then
		ok "docker working ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,))"
	else
		bad 'docker installed but the engine is unreachable — check: systemctl status docker'
	fi
else
	if command -v docker >/dev/null 2>&1; then
		bad "docker installed in '$ZONE', which does not enable it — see decisions/0004"
	else
		ok "no docker, as expected for '$ZONE'"
	fi
fi

printf '\nIdentity\n'

# Zones with "github": false must hold no credentials at all. That is the whole
# point of having one. See SECRETS.md and decisions/0006.
if [[ "$(cfg_zone_field "$ZONE" github 2>/dev/null)" != "true" ]]; then
	if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
		bad "zone '$ZONE' is authenticated to GitHub — config.json says github:false"
	else
		ok "no GitHub credentials, as expected for '$ZONE'"
	fi
else
	if git config --global user.email >/dev/null 2>&1; then
		ok "git identity set ($(git config --global user.email))"
	else
		bad 'git user.email not set for this zone'
	fi

	# Each credentialed zone should hold a token scoped to that zone's own
	# repositories. If the zones share a GitHub account, the separation is the
	# repository selection rather than the identity - which is weaker, and is why
	# fine-grained PATs matter here. See SECRETS.md and decisions/0006.
	if command -v gh >/dev/null 2>&1; then
		if gh auth status >/dev/null 2>&1; then
			ok 'gh authenticated'
		else
			bad 'gh not authenticated — run: gh auth login'
		fi
	else
		bad 'gh not installed — run env/packages.sh as root'
	fi
fi

# The VPS key lives on the Windows host only, so no zone can reach it.
# See decisions/0006-credential-placement.md.
if compgen -G "$HOME/.ssh/id_*" >/dev/null; then
	bad "SSH private keys present in $HOME/.ssh — zones use HTTPS tokens, not SSH keys"
else
	ok 'no SSH private keys in this zone'
fi

# ---------------------------------------------------------------------------
# Optional per-user assertions. Sourced, not executed, so ok/bad/skip and the
# counters are already in scope and its results join the totals.
# See overrides/README.md.
_override="$REPO_ROOT/overrides/verify/verify.sh"
if [[ -f "$_override" ]]; then
	printf '\nOverrides\n'
	# shellcheck source=/dev/null
	. "$_override"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"

if [[ "$FAIL" -gt 0 ]]; then
	printf '\nSee decisions/ for why each of these is expected.\n'
	exit 1
fi
exit 0
