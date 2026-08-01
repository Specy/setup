# Windows Terminal profiles

One profile per zone, each with a distinct colour scheme.

This looks cosmetic and is not. The colour of the window is the fastest signal of which
trust zone a command is about to run in — it is what stops a work token being pasted into
`external`, or a destructive command being run against the wrong projects. Colour
registers before you read the prompt.

| Zone | Scheme | Background | Meaning |
| --- | --- | --- | --- |
| `daily` | `zone-daily` | neutral grey | no credentials, general use |
| `work` | `zone-work` | blue | work credentials, docker |
| `personal` | `zone-personal` | green | personal credentials |
| `external` | `zone-external` | **red** | untrusted code, no credentials |

Red for `external` is deliberate: it is the zone where hostile code is expected to run.

Each profile is renamed to its zone, has `suppressApplicationTitle` set so the tab keeps
that name, and opens in `~/code`.

## Applying

```powershell
.\apply.ps1
```

Idempotent — schemes are matched by name and profiles by guid, so re-running replaces
rather than duplicates. `settings.json` is backed up to `settings.json.bak` before every
write, and everything not listed here is left untouched.

Restart Windows Terminal afterwards to see the change.

To undo, copy the `.bak` back over `settings.json`.

## Why profiles are matched by name, not guid

Windows Terminal generates the WSL profiles itself and assigns each one a guid. `apply.ps1`
therefore **matches the generated profiles by distro name** and edits them in place — it
does not create profiles, and it does not carry any guids, which would only ever be correct
on the machine they were copied from.

Adding a zone needs nothing here: launch Terminal once after creating the distro so the
profile is generated, then re-run `apply.ps1`. A zone with no scheme of its own falls back
to the neutral one rather than being skipped.

## Caveat

`apply.ps1` uses PowerShell 5.1's JSON parser, which rejects `//` comments. Terminal writes
plain JSON by default, but if you hand-edit `settings.json` and add comments the script
will refuse to run rather than corrupt the file. Strip them, or merge by hand.
