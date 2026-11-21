# Miracle Cloud VM

**Ubuntu 22.04 LTS · XFCE · TigerVNC · noVNC · Railway · Docker**

Miracle Cloud VM is a remote Linux desktop **container**, not a full virtual machine. It provides XFCE, a terminal, common developer utilities, authenticated browser access through noVNC, and optional persistent user files through a Railway Volume.

## Original repository review

The upstream `dxdgame/docker-ubuntu-desktop` Dockerfile was inspected before redesign. It used Ubuntu 22.04 and installed XFCE, TigerVNC, noVNC, websockify, systemd, and Firefox. Its `CMD` started VNC with `-SecurityTypes None`, generated a self-signed certificate inside the container, daemonized websockify, then used `tail -f /dev/null`. That left the desktop unauthenticated, made the long-running container process unrelated to service health, and did not integrate with Railway's HTTPS termination. This project retains the useful desktop stack but removes those insecure lifecycle choices. Upstream project: <https://github.com/dxdgame/docker-ubuntu-desktop> (MIT; original copyright belongs to its authors).

## Modes: choose deliberately

### Mode A — Railway-compatible (default)

`MODE=railway` runs Supervisor as PID 1. Supervisor owns the VNC, websockify, readiness server, and nginx processes, restarts failed services, and writes logs to stdout/stderr. Use `miraclectl status`, `miraclectl restart miracle-vnc`, and `miraclectl restart miracle-novnc` for service control. `systemctl` is installed, but it **does not manage the desktop services in this mode** because systemd is not PID 1.

### Mode B — genuine systemd (conditional)

Set `MODE=systemd` only on a compatible Linux VM/container host that supplies working systemd/cgroup support. The entrypoint executes `/sbin/init`; it does **not** silently fall back to Supervisor. Units are in `systemd/`. Check `ps -p 1 -o comm=` and `systemctl status` on that host. Railway runs application containers and does not document a guarantee of writable host cgroups or the init capabilities needed for systemd PID 1; therefore this mode is **not guaranteed on Railway**. No privileged mode or host mounts are requested by this project.

## What is exposed

- Public HTTP: nginx listens on Railway's runtime `PORT` and serves `/vnc.html`.
- Public health endpoint: `/health` returns 200 only after both the VNC and WebSocket gateway TCP listeners are accepting connections. It intentionally reveals no credentials or host details.
- Internal VNC: `127.0.0.1:5901` only; not published directly.
- Internal websockify: `127.0.0.1:6081` only.
- Browser authentication: nginx HTTP Basic Auth with a bcrypt password file created at runtime. The VNC password is separate from the web password if configured separately. Never expose port 5901 publicly.

Railway terminates public HTTPS at its proxy. Open the Railway `https://` domain; no self-signed TLS certificate is created in the container. The browser automatically negotiates a secure WebSocket through HTTPS.

**Security notes:** choose a unique random `WEB_PASSWORD` (at least 12 characters; longer is better). Basic Auth credentials are protected in transit by Railway HTTPS, but users should still treat the desktop as a sensitive remote-access service. Classic VNC password authentication uses a legacy format with an effective 8-character password limit; it is not a substitute for the longer web gateway password. The web gateway protects both noVNC assets and the WebSocket route; `/health` is the only unauthenticated endpoint.

## Build and run locally

Requires Docker with AMD64 support. On an ARM machine, Docker may use emulation, but native AMD64 is preferred.

```bash
git clone <your-fork-or-repository-url> miracle-cloud-vm
cd miracle-cloud-vm
docker build -t miracle-cloud-vm:local .
docker run --rm --name miracle-cloud-vm \
  -p 8080:8080 \
  -e PASSWORD='replace-with-a-long-random-secret' \
  -e VNC_PASSWORD='a-different-vnc-secret' \
  -e PORT=8080 \
  -v miracle-cloud-data:/data \
  miracle-cloud-vm:local
```

Open `http://localhost:8080/vnc.html` and sign in with the web username (default: `miracle`) and the value of `PASSWORD` unless `WEB_PASSWORD` is set. The VNC password is used internally by TigerVNC; noVNC connects through the authenticated gateway. Do not use example passwords outside local testing.

## Deploy to Railway

1. Create a GitHub repository and upload the complete contents of this project at its root. Ensure the file is named exactly `Dockerfile`.
2. In Railway, create a project and select **New → GitHub Repo**. Choose the repository. Railway detects the root Dockerfile automatically.
3. Open the service's **Variables** panel and add:
   - `USERNAME` = `miracle` (or a lowercase Linux username)
   - `PASSWORD` = a long, unique random secret (minimum 12 characters). This is the browser password unless `WEB_PASSWORD` is supplied.
   - `VNC_PASSWORD` = a separate VNC password, recommended; classic VNC effectively uses only the first 8 characters.
   - `WEB_USERNAME` = `miracle` (optional; defaults to `USERNAME`)
   - `WEB_PASSWORD` = a separate long random browser password (optional; defaults to `PASSWORD`)
   - `VNC_GEOMETRY` = `1440x900` (optional)
   - `VNC_DEPTH` = `24` (optional; allowed: 16, 24, 32)
   - `MODE` = `railway` (recommended/default)
   - `DATA_DIR` = `/data` (default)
   Do not paste secrets into the repository, Dockerfile, build arguments, or logs.
4. In service **Settings → Networking**, generate a public domain.
5. In **Settings → Deploy**, configure the health check path as `/health` if it is not read from `railway.json`.
6. To persist user files, add a Railway Volume mounted at `/data`. On startup, the entrypoint creates `/data/home` and links it to `~/Files`. The root filesystem and other unmounted paths remain ephemeral.
7. Deploy and inspect deployment logs. Wait for the health check to pass, then open `https://YOUR-DOMAIN/vnc.html`. Authenticate with `WEB_USERNAME` and `WEB_PASSWORD` (or their defaults).
8. Check logs and the service's CPU/RAM metrics in Railway if the desktop is slow. Increase allocated resources in Railway settings as needed; the container reports the host-visible CPU/memory and does not emulate a Xeon CPU.

Railway's `PORT` is injected at runtime and the nginx configuration is generated from it. The service binds to all interfaces for the public HTTP listener. The VNC port is deliberately loopback-only; do not assume Railway's HTTP proxy exposes arbitrary TCP. A direct VNC client requires a separately supported TCP proxy/network design and should not be enabled by simply binding VNC to `0.0.0.0`.

## Persistence details

Railway Volumes are mounted at runtime, not during image build. Mount one at `/data`. User-created files in `~/Files` persist through `/data/home`. Other application settings can be copied to `/data` and symlinked by the user, or a future deployment can extend `runtime-setup.sh` to selectively persist settings. Credentials and `/etc/nginx/.htpasswd` are intentionally kept outside the volume and regenerated at startup. Back up the volume separately; a volume is persistence, not a complete backup strategy.

## Desktop and utilities

Included packages provide XFCE, XFCE Terminal, Thunar, Mousepad, task manager, TigerVNC, noVNC, websockify, Bash, sh, curl, wget, sudo, git, nano, vim, htop, `ip`, `ping`, `ss`, `dig`, unzip, zip, tar, gzip, xz, find, grep, sed, awk, ps, top, lsof, file, tree, Python 3, pip, gcc, g++, make, build-essential, OpenSSH client, certificates, and related base utilities. `fastfetch` and `neofetch` are installed only if an Ubuntu 22.04 package candidate exists; the interactive banner falls back to kernel/memory information otherwise. Noninteractive shells do not run the banner.

## Service management in Railway mode

```bash
ps -p 1 -o comm=                 # supervisord in Railway mode
supervisorctl -c /opt/miracle/config/supervisord.conf status
miraclectl status
miraclectl restart miracle-vnc
miraclectl restart miracle-novnc
miraclectl tail -f miracle-vnc
```

`systemctl` exists because systemd tools are installed, but commands such as `systemctl status miracle-vnc` are expected to fail or report that systemd is not the init system in Railway mode. Use `miraclectl` instead. In genuine systemd mode on a compatible host, use:

```bash
ps -p 1 -o comm=
systemctl --version
systemctl list-units --type=service
systemctl status
systemctl restart miracle-vnc
systemctl status miracle-novnc
journalctl -u miracle-vnc
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `MODE` | `railway` | `railway` or explicit `systemd` mode |
| `USERNAME` | `miracle` | Linux desktop user, lowercase Linux username |
| `PASSWORD` | required | Browser password fallback; at least 12 characters |
| `WEB_USERNAME` | `USERNAME` | HTTP Basic Auth username |
| `WEB_PASSWORD` | `PASSWORD` | Browser password, at least 12 characters |
| `VNC_PASSWORD` | `PASSWORD` | TigerVNC password; classic VNC limit applies |
| `VNC_GEOMETRY` | `1440x900` | Desktop resolution, e.g. `1600x900` |
| `VNC_DEPTH` | `24` | Color depth: 16, 24, or 32 |
| `PORT` | `8080` locally | Public HTTP port; Railway injects it |
| `DATA_DIR` | `/data` | Persistent data mount path |

The desktop user is not granted passwordless sudo by this project. The base image includes sudo, but privileged changes require an appropriate sudo policy. Avoid granting broad sudo access to a publicly reachable desktop unless you understand the implications.

## Testing and validation report

Validation that can be done without a Docker daemon or Railway account:

- Source files and configuration are included in the archive.
- Shell scripts are written with strict error handling and validated for syntax as part of package creation where Bash is available.
- Python health server syntax can be checked with `python3 -m py_compile`.
- SVG/XML can be parsed locally.

Not verified in this environment:

- Docker image build and apt package availability in the final image (Docker is not available in the build environment).
- Actual XFCE/VNC/noVNC runtime and nginx syntax inside Ubuntu 22.04.
- Public Railway deployment, Railway domain routing, and volume behavior.
- Genuine systemd PID 1 behavior, which depends on host cgroup/init support.

Before production use, build locally with Docker, test `/health`, verify browser authentication and WebSocket connectivity, restart VNC with `miraclectl`, and deploy a staging service to Railway. This README deliberately does not claim a successful deployment that has not been performed.

## Troubleshooting

- **Build fails fetching packages:** retry the Docker build; check Ubuntu Jammy package repository/network status. Optional Fastfetch/Neofetch installs are guarded so absence alone does not fail the build.
- **Container exits at startup:** inspect Railway deploy logs. Missing `PASSWORD`/`WEB_PASSWORD`, malformed username, unsupported geometry/depth, or invalid port causes an explicit startup error.
- **Health check returns 503:** check `miraclectl status` and logs for `miracle-vnc` and `miracle-novnc`; readiness only succeeds when ports 5901 and 6081 accept connections.
- **Browser asks for credentials repeatedly:** use `WEB_USERNAME`/`WEB_PASSWORD`, clear stale Basic Auth credentials, and reload `/vnc.html`.
- **WebSocket disconnects:** use the HTTPS Railway domain, ensure nginx has the `/websockify` upgrade proxy, and check VNC/websockify logs.
- **Black screen or XFCE does not appear:** inspect `miraclectl tail miracle-vnc`; confirm geometry/depth values and that `startxfce4` is installed. Restart with `miraclectl restart miracle-vnc`.
- **Files disappear after redeploy:** confirm a Railway Volume is mounted at `/data` and write files under `~/Files`.
- **`systemctl` reports not booted with systemd:** expected in Railway mode. Use `miraclectl`; switch to `MODE=systemd` only on a host that supports systemd as PID 1. It will fail visibly rather than silently switching modes.
- **Direct VNC does not connect:** expected; port 5901 is loopback-only. Browser access is the supported Railway path.

## License and attribution

This implementation is provided under the MIT License. The upstream repository is credited above; see `NOTICE` for attribution. Ubuntu and included desktop software retain their respective licenses.
