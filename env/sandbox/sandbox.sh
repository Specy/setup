#!/usr/bin/env bash
#
# Run a command confined to one project directory.
#
#     sandbox                     # interactive shell, no network
#     sandbox npm test            # one command, no network
#     sandbox --net npm install   # allow network
#     sandbox --dir ~/code/foo ls # explicit project instead of $PWD
#
# Installed to ~/.local/bin/sandbox by env/bootstrap.sh.
#
# WHAT THIS IS FOR
#
# The zone is the primary boundary: separate filesystem, separate credentials, no
# access to Windows or to other zones. This is the SECOND layer, for running code
# you do not trust inside the zone that exists to hold it.
#
# It stops a build script or agent from reading the rest of the zone - other
# projects, shell history, agent config, any credential that lands there later -
# and from writing anywhere except the project itself.
#
# WHAT IT IS NOT
#
# Not a security boundary against a kernel exploit. bubblewrap uses user
# namespaces; a kernel vulnerability defeats it. It raises the cost of a hostile
# postinstall considerably and is not a guarantee.
#
# Network isolation is per-command and DEFAULTS TO OFF-NETWORK. Note that
# --net grants the full shared namespace, which per
# decisions/0015-shared-network-namespace.md reaches every other zone's services.

set -euo pipefail

NET=0
PROJECT=""

usage() {
	sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--net)  NET=1; shift ;;
		--dir)  PROJECT="${2:-}"; shift 2 ;;
		-h|--help) usage 0 ;;
		--) shift; break ;;
		-*) printf 'sandbox: unknown option %s\n' "$1" >&2; usage 1 ;;
		*) break ;;
	esac
done

PROJECT="${PROJECT:-$PWD}"
PROJECT="$(readlink -f "$PROJECT")"

command -v bwrap >/dev/null 2>&1 || {
	printf 'sandbox: bubblewrap not installed (run env/packages.sh as root)\n' >&2
	exit 1
}

[[ -d "$PROJECT" ]] || { printf 'sandbox: not a directory: %s\n' "$PROJECT" >&2; exit 1; }

# Refuse to sandbox $HOME itself or anything outside ~/code. Binding $HOME
# read-write would defeat the entire point, and it is an easy mistake to make by
# running `sandbox` from the wrong directory.
CODE_ROOT="$(readlink -f "$HOME/code")"
case "$PROJECT" in
	"$CODE_ROOT"/*) ;;
	*)
		printf 'sandbox: refusing - %s is not inside %s\n' "$PROJECT" "$CODE_ROOT" >&2
		printf 'sandbox: cd into a project first, or pass --dir\n' >&2
		exit 1
		;;
esac

args=(
	# System, read-only.
	--ro-bind /usr /usr
	--ro-bind /etc /etc
	--proc /proc
	--dev /dev

	# Writable scratch that disappears with the sandbox.
	--tmpfs /tmp
	--tmpfs /var/tmp

	# $HOME becomes an empty tmpfs: nothing in it is visible unless bound back
	# below. This is what hides other projects, shell history and agent config.
	--tmpfs "$HOME"

	# The project itself, read-write. The only persistent writable path.
	--bind "$PROJECT" "$PROJECT"
	--chdir "$PROJECT"

	--unshare-all
	--die-with-parent
	--new-session
	--setenv HOME "$HOME"
	--setenv SANDBOX 1
	--setenv PS1 '(sandbox) \w\$ '
)

# On merged-usr systems (Ubuntu, Fedora, Arch) /bin, /sbin and /lib are SYMLINKS
# into /usr. bwrap builds an empty root, so binding /usr alone leaves no /bin at
# all and every command fails with:
#     bwrap: execvp /bin/bash: No such file or directory
# The symlinks have to be recreated inside. On split-usr systems they are real
# directories and get bound instead.
for d in /bin /sbin /lib /lib64 /lib32; do
	if [[ -L "$d" ]]; then
		args+=(--symlink "$(readlink "$d")" "$d")
	elif [[ -d "$d" ]]; then
		args+=(--ro-bind "$d" "$d")
	fi
done

# Toolchains, read-only. Without these there is no node, no cargo, nothing.
#
# ~/.config/mise is not optional: the shims resolve a version by reading
# config.toml, and without it every shim fails with a bare "mise ERROR" while
# cargo and other non-shimmed tools keep working - a confusing half-broken state.
#
# Note this binds ~/.config/mise specifically, NOT ~/.config, which would expose
# gh credentials in the zones that have them.
for d in "$HOME/.local/share/mise" "$HOME/.config/mise" "$HOME/.rustup" "$HOME/.cargo" "$HOME/.local/bin"; do
	[[ -e "$d" ]] && args+=(--ro-bind "$d" "$d")
done

# npm config, read-only - carries ignore-scripts=true, which must hold inside too.
[[ -f "$HOME/.npmrc" ]] && args+=(--ro-bind "$HOME/.npmrc" "$HOME/.npmrc")

if [[ "$NET" -eq 1 ]]; then
	args+=(--share-net)

	# Under WSL /etc/resolv.conf is a symlink to /mnt/wsl/resolv.conf, which the
	# sandbox root does not contain - so the symlink dangles and every name lookup
	# fails while connections to a bare IP still work. Bind the resolved target.
	# Only with --net: an off-network sandbox has no use for it.
	resolv="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
	if [[ -n "$resolv" && -f "$resolv" && "$resolv" != "/etc/resolv.conf" ]]; then
		args+=(--ro-bind "$resolv" "$resolv")
	fi
else
	# Loopback only. Without this, code that binds a port fails confusingly.
	args+=(--unshare-net)
fi

if [[ $# -eq 0 ]]; then
	exec bwrap "${args[@]}" /bin/bash --norc -i
else
	exec bwrap "${args[@]}" /bin/bash --norc -lc "$(printf '%q ' "$@")"
fi
