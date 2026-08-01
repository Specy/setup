#!/usr/bin/env bash
#
# Install the coding agent CLIs for a zone. Idempotent - safe to re-run.
#
#     ~/setup/env/agents.sh
#
# Runs as the zone user, NOT root: npm's global prefix is inside the mise-managed
# node install, which the user owns.
#
# Separate from bootstrap.sh because it is slow - claude alone pulls a ~275 MB
# native binary - and is not needed to have a working environment.
#
# Agents must execute INSIDE the zone. A desktop chat app reaching project files
# over MCP runs on the Windows host with host permissions and bypasses every
# boundary in this repo. See decisions/0008-agent-execution-boundary.md.

set -uo pipefail

log()     { printf '    %s\n' "$*"; }
changed() { printf '  + %s\n' "$*"; }
warn()    { printf '  ! %s\n' "$*" >&2; }
section() { printf '\n%s\n' "$*"; }

command -v npm >/dev/null 2>&1 || { printf 'error: npm not found - run bootstrap.sh first\n' >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || { printf 'error: run as the zone user, not root\n' >&2; exit 1; }

ZONE="$(cat "$HOME/.zone" 2>/dev/null || echo unknown)"
printf 'Installing agents for zone: %s\n' "$ZONE"

install_agent() {
	local pkg="$1" bin="$2"
	if command -v "$bin" >/dev/null 2>&1 && "$bin" --version >/dev/null 2>&1; then
		log "$bin already working ($("$bin" --version 2>&1 | head -1))"
		return 0
	fi
	npm install -g "$pkg" --no-audit --no-fund >/dev/null 2>&1 \
		|| { warn "npm install failed for $pkg"; return 1; }
	changed "installed $pkg"
	return 0
}

section 'Agent CLIs'
install_agent '@openai/codex'            codex
install_agent '@google/gemini-cli'       gemini
install_agent '@anthropic-ai/claude-code' claude

# ---------------------------------------------------------------------------
section 'claude native binary'
# ~/.npmrc sets ignore-scripts=true (decisions/0005-npm-ignore-scripts.md), which
# blocks this package's postinstall - and that postinstall is what downloads the
# native binary. Without it `claude` exits with:
#     Error: claude native binary not installed.
#
# `npm rebuild -g @anthropic-ai/claude-code` reports success and does NOT fix it.
# The install script has to be run directly. This is the documented remedy in 0005
# failing on a real package, which is worth knowing.
claude_dir="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code"

if ! command -v claude >/dev/null 2>&1; then
	warn 'claude not installed, skipping native binary step'
elif claude --version >/dev/null 2>&1; then
	log "native binary present ($(claude --version 2>&1 | head -1))"
elif [[ -f "$claude_dir/install.cjs" ]]; then
	( cd "$claude_dir" && node install.cjs ) >/dev/null 2>&1
	if claude --version >/dev/null 2>&1; then
		changed "native binary fetched ($(claude --version 2>&1 | head -1))"
	else
		warn 'install.cjs ran but claude still reports no native binary'
	fi
else
	warn "install.cjs not found at $claude_dir"
fi

# ---------------------------------------------------------------------------
section 'Versions'
for c in claude codex gemini; do
	if command -v "$c" >/dev/null 2>&1; then
		printf '    %-8s %s\n' "$c" "$("$c" --version 2>&1 | head -1)"
	else
		printf '    %-8s not installed\n' "$c"
	fi
done

printf '\nAgents are not authenticated. Sign in inside the zone when you first use them.\n'
