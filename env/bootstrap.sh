#!/usr/bin/env bash
#
# Configure a Linux environment for a zone. Idempotent — safe to re-run.
#
#     ./env/bootstrap.sh --zone work
#
# Must work on native Linux as well as inside WSL.
# See env/README.md and decisions/0013-repo-layout.md.

set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZONE=""
CHANGES=0

usage() {
	cat <<'EOF'
Usage: bootstrap.sh --zone <daily|work|personal|external>

Configures the current Linux environment for a zone. Safe to re-run; reports only
what it changes.
EOF
}

log()     { printf '    %s\n' "$*"; }
changed() { printf '  + %s\n' "$*"; CHANGES=$((CHANGES + 1)); }
warn()    { printf '  ! %s\n' "$*" >&2; }
section() { printf '\n%s\n' "$*"; }
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--zone) ZONE="${2:-}"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
	esac
done

case "$ZONE" in
	daily|work|personal|external) ;;
	"") usage >&2; die "--zone is required" ;;
	*)  die "unknown zone '$ZONE' (expected daily, work, personal or external)" ;;
esac

# Copy src to dest only if it differs. Backs up anything already there.
install_file() {
	local src="$1" dest="$2"
	[[ -f "$src" ]] || die "missing source file: $src"
	if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
		log "$(basename "$dest") already current"
		return
	fi
	if [[ -e "$dest" ]]; then
		cp -p "$dest" "${dest}.bak"
		warn "backed up existing $dest to ${dest}.bak"
	fi
	mkdir -p "$(dirname "$dest")"
	cp "$src" "$dest"
	changed "installed $dest"
}

printf 'Bootstrapping zone: %s\n' "$ZONE"

# ---------------------------------------------------------------------------
section 'Zone marker'
# Read by the shell prompt, by verify.sh, and by anything else needing to know
# where it is running. Makes the environment self-describing.

if [[ -f "$HOME/.zone" ]] && [[ "$(cat "$HOME/.zone")" == "$ZONE" ]]; then
	log "~/.zone already set to '$ZONE'"
else
	if [[ -f "$HOME/.zone" ]]; then
		warn "~/.zone was '$(cat "$HOME/.zone")', changing to '$ZONE'"
	fi
	printf '%s\n' "$ZONE" > "$HOME/.zone"
	changed "~/.zone = $ZONE"
fi

# ---------------------------------------------------------------------------
section 'Project directory'
# Code lives on the native filesystem, never under /mnt.
# See decisions/0007-code-on-ext4.md.

if [[ -d "$HOME/code" ]]; then
	log '~/code already exists'
else
	mkdir -p "$HOME/code"
	changed '~/code created'
fi

# ---------------------------------------------------------------------------
section 'npm'
# See decisions/0005-npm-ignore-scripts.md.

install_file "$ENV_DIR/node/npmrc" "$HOME/.npmrc"

# ---------------------------------------------------------------------------
section 'git'
# Shared settings go in an included file so that per-zone identity, which lives in
# ~/.gitconfig, survives re-running this script.

install_file "$ENV_DIR/git/gitconfig.common" "$HOME/.gitconfig.common"

if git config --global --get-all include.path 2>/dev/null | grep -qxF '~/.gitconfig.common'; then
	log 'git include.path already set'
else
	git config --global --add include.path '~/.gitconfig.common'
	changed 'git include.path -> ~/.gitconfig.common'
fi

if ! git config --global user.email >/dev/null 2>&1; then
	warn "git identity not set for this zone. Set it with:"
	warn "    git config --global user.name  \"...\""
	warn "    git config --global user.email \"...\""
fi

# ---------------------------------------------------------------------------
section 'Shell'
# Managed blocks delimited by markers so they can be rewritten in place.
# Everything outside the markers is the user's own and is never touched.

BLOCK_BEGIN='# >>> managed by setup repo >>>'
BLOCK_END='# <<< managed by setup repo <<<'

ensure_managed_block() {
	local file="$1" body="$2" label="$3"
	touch "$file"

	local stripped desired
	stripped="$(awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
		index($0, b) { skip = 1 }
		!skip        { print }
		index($0, e) { skip = 0 }
	' "$file")"

	desired="$(printf '%s\n%s\n%s\n%s\n' "$stripped" "$BLOCK_BEGIN" "$body" "$BLOCK_END")"

	if [[ "$desired" == "$(cat "$file")" ]]; then
		log "$label managed block already current"
	else
		printf '%s' "$desired" > "$file"
		changed "$label managed block updated"
	fi
}

# ~/.profile — PATH only, and deliberately NOT `mise activate`.
#
# Ubuntu's stock ~/.bashrc begins with a `case $- in *i*) ;; *) return;; esac`,
# so anything appended there is skipped entirely by non-interactive shells. Without
# the shims on PATH, `node` is missing from login shells, scripts, and anything an
# agent runs non-interactively - it only works when a human is typing.
#
# Shims are mise's answer to exactly this: real executables on disk, no shell hook
# required.
ensure_managed_block "$HOME/.profile" "$(cat <<-'BODY'
	# mise shims: makes node/npm/uv resolvable without a shell hook, which is what
	# non-interactive shells and tooling need. See decisions/0011.
	if [ -d "$HOME/.local/share/mise/shims" ]; then
	    PATH="$HOME/.local/share/mise/shims:$PATH"
	fi

	# Which trust zone is this shell in?
	if [ -r "$HOME/.zone" ]; then
	    SETUP_ZONE="$(cat "$HOME/.zone")"
	    export SETUP_ZONE
	fi
	BODY
)" '~/.profile'

# ~/.bashrc — full activation for interactive use. This supersedes the shims when
# present and adds per-directory version switching on cd.
ensure_managed_block "$HOME/.bashrc" "$(cat <<-'BODY'
	# Runtime version manager. Interactive only: it installs a shell hook that
	# switches versions on cd. Non-interactive shells use the shims from ~/.profile.
	if command -v mise >/dev/null 2>&1; then
	    eval "$(mise activate bash)"
	fi
	BODY
)" '~/.bashrc'

# ---------------------------------------------------------------------------
section 'Toolchains'
# See decisions/0011-toolchain-management.md.

if ! command -v mise >/dev/null 2>&1; then
	warn 'mise not installed — run env/packages.sh as root first, then re-run this'
else
	install_file "$ENV_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"

	# `mise install` is idempotent but not silent, so only report real work.
	before="$(mise ls --installed --quiet 2>/dev/null | wc -l)"
	mise install --yes >/dev/null 2>&1 || warn 'mise install reported an error'
	after="$(mise ls --installed --quiet 2>/dev/null | wc -l)"

	if [[ "$before" == "$after" ]]; then
		log "toolchains already installed ($after)"
	else
		changed "toolchains installed ($before -> $after)"
	fi
fi

# ---------------------------------------------------------------------------
section 'Sandbox'
# Second isolation layer for running untrusted code inside a zone.
# See decisions/0008-agent-execution-boundary.md.

mkdir -p "$HOME/.local/bin"
install_file "$ENV_DIR/sandbox/sandbox.sh" "$HOME/.local/bin/sandbox"
chmod +x "$HOME/.local/bin/sandbox"

# ---------------------------------------------------------------------------
section 'Agent config'
# The CLIs themselves are installed by env/agents.sh, which is slow and separate.
# This is just the deny-list, which is cheap and should exist whether or not an
# agent is installed yet. See decisions/0008-agent-execution-boundary.md.

install_file "$ENV_DIR/agents/claude-settings.json" "$HOME/.claude/settings.json"

# ---------------------------------------------------------------------------
section 'Rust'
# rustup itself is installed by packages.sh, and only in zones with Rust projects.
# The toolchain is per-user, so selecting it belongs here rather than there.

if ! command -v rustup >/dev/null 2>&1; then
	log 'rustup not installed — not a Rust zone'
elif rustup default 2>/dev/null | grep -q 'stable'; then
	log "toolchain already set ($(rustup default 2>/dev/null | cut -d' ' -f1))"
else
	rustup default stable >/dev/null 2>&1 && changed 'rust toolchain set to stable' \
		|| warn 'rustup default stable failed'
fi

# ---------------------------------------------------------------------------
# Not yet implemented. Each is written when its runbook phase is executed, rather
# than speculatively in advance. See env/README.md for the current state.
#
#   docker/  docker-ce, work zone only         (decisions/0004)
#   agents/  agent config, deny-lists, sandbox (decisions/0008)

# ---------------------------------------------------------------------------
# Optional per-user extension point. Runs AFTER the base steps so it extends
# rather than replaces them. See overrides/README.md.
_override="$(cd "$ENV_DIR/.." && pwd)/overrides/env/bootstrap.sh"
if [[ -x "$_override" ]]; then
	section 'Overrides'
	"$_override" --zone "$ZONE" || die "override bootstrap failed"
	CHANGES=$((CHANGES + 1))
fi

# ---------------------------------------------------------------------------
section 'Summary'

if [[ "$CHANGES" -eq 0 ]]; then
	log 'nothing to change — environment already matches the repo'
else
	log "$CHANGES change(s) applied"
fi

printf '\nNext: ./verify/verify.sh --zone %s\n' "$ZONE"
