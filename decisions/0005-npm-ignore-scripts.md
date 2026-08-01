# 0005 — npm with lifecycle scripts disabled; pnpm deferred

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

Every significant npm compromise of the last year executed through **lifecycle scripts**
(`preinstall`, `install`, `postinstall`) and spread because people installed the malicious
version within hours of it being published. Two independent controls address this: block
script execution, and refuse to install packages that are only hours old.

pnpm 10+ provides both — it blocks lifecycle scripts by default behind an explicit
`onlyBuiltDependencies` allowlist, and supports a `minimumReleaseAge` cooldown. npm
provides only the first.

Migrating package managers across every project at the same time as rebuilding the
machine is too much change at once.

## Decision

Stay on npm for now, with `ignore-scripts = true` set globally in `~/.npmrc` per zone.

Migrate to pnpm later, per project, deliberately.

## Consequences

Packages that genuinely compile or download during install will not do so until
explicitly allowed:

```bash
npm rebuild <package>
```

The friction is the security property: it makes visible exactly which dependencies want
to execute code on install.

### Measured, 2026-07-31 — the friction is smaller than assumed

This record originally claimed "roughly three to five packages per project" would need a
rebuild, naming `esbuild` among them. Tested in `dev-personal` with
`ignore-scripts = true`:

```
npm install esbuild@0.25.0   ->  added 2 packages
./node_modules/.bin/esbuild --version  ->  0.25.0     (works, no rebuild)
```

`esbuild` needs nothing. Modern packages ship platform-specific prebuilt binaries as
`optionalDependencies` — `@esbuild/linux-x64` and similar — which npm simply unpacks. No
lifecycle script is involved, so disabling them costs nothing. The same pattern is used by
`@swc/core`, `rollup` and others.

The packages that still need attention are the ones doing real work at install time:
node-gyp compilation (`better-sqlite3`) and postinstall downloads. One of those has since
been met, and it matters more than the general case because **the documented remedy did
not work**.

### `@anthropic-ai/claude-code` — where `npm rebuild` fails

Installing the Claude Code CLI globally with `ignore-scripts = true` succeeds, and then:

```
$ claude --version
Error: claude native binary not installed.
```

Its `postinstall` is `node install.cjs`, which downloads a ~275 MB native binary. Blocking
it leaves a package that installs cleanly and does not run.

`npm rebuild -g @anthropic-ai/claude-code` reports **`rebuilt dependencies successfully`**
and changes nothing. The install script has to be invoked directly:

```bash
cd "$(npm root -g)/@anthropic-ai/claude-code" && node install.cjs
```

`env/agents.sh` does this automatically and idempotently.

The general lesson: `npm rebuild` is the *usual* remedy, not a reliable one. When a package
still misbehaves after a rebuild, read its `scripts` block and run the install script
yourself rather than assuming the rebuild worked — it will claim success either way.

## Rejected alternatives

**`npm install --before=<date>` as a cooldown.** npm has no per-package release-age
control. `--before` applies to the entire dependency resolution and conflicts with the
lockfile. Not usable in practice, which is a real reason to move to pnpm eventually
rather than a reason to stay.

**Doing nothing until the pnpm migration.** `ignore-scripts` is one line and addresses
the actual execution mechanism today. No reason to wait.

**Yarn or Bun.** Bun also has a release-age cooldown, but changing runtime and package
manager simultaneously is a larger migration than pnpm for the same benefit.

## What would change this

Migrating a project to pnpm, at which point that project gains the cooldown and the
allowlist and no longer needs the global `ignore-scripts` fallback. When every project
has moved, supersede this record.
