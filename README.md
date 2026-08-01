# setup

A sandboxed development environment for Windows. Your projects and your coding agents run
inside separate Linux environments, so a bad dependency or a confused agent can only reach
one of them instead of everything you own.

It is opinionated. It makes choices for you and writes down why in [decisions/](decisions/).

## The idea

Install a package on a normal dev machine and its install script runs as you. It can read
every token, every SSH key, every project you have, and your browser data. That is the
actual attack, and it happens regularly.

Here you get four separate Linux environments, each a WSL distro with its own filesystem,
user, and credentials:

| Zone | For | Credentials |
| --- | --- | --- |
| `daily` | your existing distro, general Linux use | none |
| `work` | work projects | work GitHub token |
| `personal` | personal projects | personal GitHub token |
| `external` | other people's code, untrusted repos | none, on purpose |

A compromise in one gets that one. Your work token is not in the zone where you build
random GitHub projects.

Inside a zone you can go further. `sandbox npm install` runs a command with access to one
project directory and nothing else, and no network unless you ask for it.

## What you get

- Zones that cannot see your Windows drive and have no Windows programs on `PATH`, so
  agents use Linux tools instead of finding half broken Windows ones
- A separate GitHub token per zone
- npm install scripts disabled, which is how most recent npm attacks actually ran
- mise for Node and other runtimes, uv for Python, rustup where you want Rust
- Docker inside the zone that needs it, not Docker Desktop
- Claude Code, Codex and Gemini installed in each zone, with a rule blocking them from
  reading your keys and tokens
- `verify.sh`, which checks a zone still matches what you asked for and complains if
  something appeared that should not be there

## What it does not do

Worth reading before you rely on it.

The zones do not have separate networks. Anything listening on a port in one zone can be
reached from the others, including containers you did not publish ports for. Put a real
password on anything that holds data. See
[0015](decisions/0015-shared-network-namespace.md).

The separation between zones is roughly container strength, not virtual machine strength.
The separation between WSL and Windows is stronger.

Your Windows account can reach every zone without a password. That is normal and expected,
but it means this protects you from bad code, not from someone who already has your laptop.

## Requirements

Windows 11 with WSL2, about 40 GB free, and an hour. Most of that hour is downloads.

## Running it

The repo is written to be handed to a coding agent. Open one in this folder and say:

```
Read AGENTS.md and set this up on my machine.
```

[AGENTS.md](AGENTS.md) tells it what order to do things in, what to check after each step,
and which steps it must stop and ask you to do yourself. There are four of those: setting a
password for each zone, logging into GitHub, signing into the agents, and clicking Windows
permission prompts. Everything else it can do on its own.

If you would rather do it by hand, [hosts/windows/README.md](hosts/windows/README.md) is the
same thing written for a person.

Either way, start by copying `config.example.json` to `config.json` and filling it in. That
file is where your machine goes: your Windows username, your git name and email, which
distro you already use, and which repos belong in which zone.

## Making it yours

Do not edit the scripts. Two places are yours:

**`config.json`** for your machine. Zone names, which zones get Docker or Rust, which repos
get cloned where.

**`overrides/`** for everything else. Extra packages, extra setup steps, your editor config,
your own checks. It hooks into the setup at four points and runs after the normal steps, so
you are adding to it rather than replacing it. [overrides/README.md](overrides/README.md)
has the details.

Keeping to those two means you can pull updates to this repo later without fighting merge
conflicts, and anything genuinely useful you build can go back upstream without your
personal details tagging along.

If you want your own instance tracked in git, keep it in a private repo with this one as a
submodule. The scripts work either way.

## Day to day

| What | How |
| --- | --- |
| Open a zone | Windows Terminal, one profile per zone, each a different colour |
| VS Code | Connect to WSL, pick the zone |
| Zed | Run `hosts\windows\zones\enable-zed.ps1` once first |
| Run one command from Windows | `wsl -d dev-work -- bash -lc 'npm test'` |
| Run something you do not trust | `sandbox npm test`, or `sandbox --net npm install` |
| Check a zone is still right | `~/setup/verify/verify.sh --zone work` |
| Back up a zone | `wsl --export dev-work backup.tar` |

The colours are not decoration. They are what stops you pasting a work token into the
untrusted zone at one in the morning.

## About the decisions folder

Every choice here has a file explaining what was picked, what was rejected, and what would
make it worth changing. Some of them look wrong until you read why. Turning off WSL interop
looks like pointless friction, for example, until you find out any distro that can run
`wsl.exe` can read every other distro without a password.

A few of them record where the first answer turned out to be wrong once it was actually
tested. Those are left in rather than quietly fixed, because a plausible wrong answer is the
one you would arrive at yourself.

## License

MIT.
