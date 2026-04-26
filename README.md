# zzci/init

Minimal container init image based on `scratch`, bundling tini + supervisord + busybox.

Use as a PID 1 init system that runs one or more long-lived processes inside a container, with proper signal forwarding and zombie reaping.

## Components

- [tini](https://github.com/krallin/tini) `v0.19.0` — PID 1 signal handling and zombie reaping
- [zzci/supervisord](https://github.com/zzci/supervisord) — process supervisor (Go, single static binary, container-focused fork of ochinchina/supervisord)
- [busybox](https://busybox.net) — coreutils for shell scripts

Final image is built `FROM scratch` — only the three binaries above plus `start.sh` / `sctl`. All binaries are pre-built; no compile toolchain at build time.

## Usage

Run directly with a mounted work dir:

```bash
docker run --rm -ti -v $PWD/work:/work zzci/init
```

## Building a derived image

Most of the time you bake services into a downstream image with `COPY`.

### Bundle service templates

```dockerfile
FROM zzci/init
COPY services/ /build/services/
# enable at runtime via env: docker run -e ZSRV_web=true ...
```

### Enable services at build time (skip the enable step)

```dockerfile
FROM zzci/init
COPY services/ /build/services/
# pre-bake into run/ so supervisord starts them immediately
COPY services/web.conf services/redis.conf /.init/services/run/
```

### Add app binary + service definition

```dockerfile
FROM zzci/init
COPY --from=builder /out/myserver /usr/bin/myserver
COPY web.conf /build/services/
COPY init.sh /work/.init/init.sh
```

### Override supervisord config

```dockerfile
FROM zzci/init
COPY init.conf /.init/init.conf
COPY services/ /build/services/
```

### Full example

```dockerfile
FROM golang:alpine AS builder
WORKDIR /src
COPY . .
RUN go build -o /out/myserver

FROM zzci/init
COPY --from=builder /out/myserver /usr/bin/myserver
COPY services/ /build/services/
ENV ZSRV_myserver=true
CMD ["/start.sh"]
```

### Inject into any base image

`COPY --from=zzci/init` lets you graft the init system onto an existing image (alpine, ubuntu, distroless, etc.) instead of `FROM zzci/init`. Useful when you need a real userland or tools alongside the init system.

```dockerfile
FROM alpine:3.20
COPY --from=zzci/init / /
COPY services/ /build/services/
CMD ["/start.sh"]
```

`start.sh` / `sctl` use absolute paths internally (`/build/bin/...`, `/.init/...`) and export their own `PATH`, so no extra `ENV` is needed and the layout must be preserved.

If you want `sctl` reachable from an interactive shell (e.g. `docker exec -it <ctr> sctl restart web`), the injected layout's binaries are **not** on the parent image's `PATH`. Either call by absolute path:

```bash
docker exec -it <ctr> /build/bin/sctl restart web
```

or extend `PATH` in the derived Dockerfile:

```dockerfile
FROM alpine:3.20
COPY --from=zzci/init / /
ENV PATH=$PATH:/build/bin:/build/bin/busybox
CMD ["/start.sh"]
```

Runtime supervision works either way — this only affects interactive use.

## Adding service definitions

Drop supervisord-format `.conf` files into one of:

| Path | When | Purpose |
|------|------|---------|
| `/build/services/` | image build time | bundled templates |
| `/work/.init/services/` | runtime mount | extra/override templates |

Example `web.conf`:

```ini
[program:web]
command=/usr/bin/myserver
autostart=true
autorestart=true
```

Files in `services/` are **templates** — they must be enabled before supervisord runs them.

## Enabling services

Three ways. They can be combined.

### 1. `ZSRV_*` environment variables

```yaml
environment:
  ZSRV_web: true        # enable web.conf
  ZSRV_redis: false     # skip (keep var for easy debug toggle)
  ZSRV_HTTP: web-http   # value used as service name (for names with -, .)
```

Value semantics:

| Value | Behavior |
|-------|----------|
| empty / `true` / `1` / `yes` / `on` | enable, service name = suffix after `ZSRV_` |
| `false` / `0` / `no` / `off` | disable: move `run/<name>.conf` to `run/.disabled/<name>.conf` |
| any other string | enable, value used as service name (for names with `-`, `.`) |

Disable preserves the file under `.disabled/` (the `run/` directory may be the only source — e.g. when files are pre-baked there directly), so you can re-enable just by removing the env var. Works for both template-based services and pre-baked ones.

### 2. `/work/.init/init.sh`

A shell script run before supervisord starts. Useful for dynamic logic:

```sh
#!/bin/sh
sctl enable web
[ "$ENABLE_REDIS" = "1" ] && sctl enable redis
```

### 3. Pre-baked `run/` dir

Mount or `ADD` `.conf` files directly to `/work/.init/services/run/`. They get copied verbatim and skip the enable step.

## Runtime control with `sctl`

```bash
sctl start    <name>
sctl stop     <name>
sctl restart  <name>
sctl enable   <name>
sctl disable  <name>
sctl show     <name>
```

## Customizing supervisord config

Default config is `/.init/init.conf`. Override by mounting `/work/.init/init.conf`.

## File layout

```
/.init/
  init.conf          # supervisord main config (default)
  services/          # service templates
    run/             # enabled services (loaded by supervisord)
/build/
  services/          # build-time bundled templates (optional)
  bin/
    tini
    supervisord
    sctl
    busybox/         # busybox applets
/work/.init/         # user mount point
  init.conf          # optional override
  init.sh            # optional pre-start hook
  services/          # additional templates or direct run/ overrides
```

## Local development

The `aa` helper script wraps common docker actions:

```bash
./aa build           # docker build -t zzci/init .
./aa test            # docker run with /work mounted
./aa exec [cmd]      # exec into running container
./aa rm              # docker compose down
```

## Build

```bash
docker build -t zzci/init .
```

CI (`.github/workflows/docker.yml`) builds `linux/amd64` + `linux/arm64` on a monthly schedule and pushes to Docker Hub as `zzci/init`.
