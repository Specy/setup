# 0018 — Docker CE in `dev-work`, from Docker's own repository

- **Status:** Accepted
- **Date:** 2026-07-31

## Context

[0004](0004-no-docker-desktop.md) settled that Docker runs inside the zone that needs it
rather than as Docker Desktop. This record covers what was actually installed and what
was learned doing it.

The open worry was that Ubuntu 26.04 is new enough that Docker might not publish for it,
in which case the fallback was Ubuntu's `docker.io` package. That turned out to be
unnecessary: Docker publishes for `resolute`, the 26.04 codename.

## Decision

Docker CE from Docker's official signed apt repository, in **`dev-work` only**:

| Component | Version |
| --- | --- |
| Docker Engine | 29.7.1 |
| Docker Compose | v5.3.1 |

Packages: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
`docker-compose-plugin`. Service enabled under systemd. The `dev` user is in the `docker`
group.

Reproduce with:

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
  "$(dpkg --print-architecture)" "$VERSION_CODENAME" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker dev
systemctl enable --now docker
```

Not yet promoted to `env/docker.sh`. It should be, if a second zone ever needs Docker or
this machine is rebuilt.

## What was verified

| Check | Result |
| --- | --- |
| `docker run --rm hello-world` as `dev` | works |
| `/var/run/docker.sock` | `srw-rw---- root:docker` — a Unix socket |
| Engine listening on TCP | none |

The socket being a filesystem object, not a network endpoint, is what makes the engine
itself correctly confined to this zone — the property [0004](0004-no-docker-desktop.md)
was chosen for.

## The consequence that is not confined

Containers are **not** confined to this zone, and this is the important part.

Measured from `dev-external`, the least trusted zone:

```
work container, NO -p flag,  IP 172.17.0.2   ->  curl http://172.17.0.2/    HTTP 200
work container, -p 127.0.0.1:3456:80         ->  curl http://127.0.0.1:3456 HTTP 200
docker0 visible from external at 172.17.0.1/16
```

The docker bridge is created in the network namespace shared by every distro
([0015](0015-shared-network-namespace.md)), so **every container in `work` is reachable
from every other zone, whether or not any port is published.** Binding to `127.0.0.1`
does not help. `internal` Compose networks do not help.

This invalidated the "do not publish ports" advice originally written into 0015, which has
been removed rather than softened.

### What follows for daily use

- **Every container service needs real authentication.** A Postgres with a password is
  fine. A Postgres trusting connections from `127.0.0.1` is exposed to `external`.
- Use `--network none` for containers that need no network at all.
- Port ranges (`work` 3000–3999) exist to prevent collisions, not to isolate.

## Consequences

- Membership in `docker` is root-equivalent **within `dev-work`**: the socket grants full
  engine access, and the engine can mount any path into a privileged container. It does
  not cross to other zones, but "docker access" and "root in this zone" are the same
  thing. Rootless Docker remains deferred in
  [0010](0010-deferred-hardening.md).
- One more trust root, `download.docker.com`, in `dev-work` only.
- Image cache is per-zone, as intended, and not reclaimable automatically
  ([0014](0014-no-sparse-vhd.md)).

## What would change this

Another zone needing containers — which should trigger promoting the commands above into
`env/docker.sh` and reconsidering rootless mode, since `external` running containers as an
effective root is a materially worse proposition than `work` doing so.
