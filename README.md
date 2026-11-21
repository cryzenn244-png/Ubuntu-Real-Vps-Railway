
# Miracle Cloud Desktop

Ubuntu 22.04 desktop container with XFCE, TigerVNC, noVNC, Docker Engine,
Docker Compose, Buildx, and optional KVM device detection.

## Features

- XFCE graphical desktop
- Browser-based access through noVNC
- Password-protected VNC connection
- Docker Engine and Docker Compose
- Docker Buildx
- Optional KVM detection through `/dev/kvm`
- Persistent Docker data and workspace mount points
- Railway-compatible HTTP port selection through `PORT`

## Repository files

Only these four project files are required:

- `Dockerfile`
- `README.md`
- `.gitignore`
- `.dockerignore`

The container startup script is generated inside the Docker image.

## Requirements

- Docker-compatible container host
- Bash and Linux kernel features supplied by the host
- `VNC_PASSWORD` environment variable
- Privileged execution or equivalent host capabilities for Docker-in-Docker
- `/dev/kvm` passed through from the host for KVM acceleration

The Docker image cannot create host CPU, RAM, disk, or hardware virtualization
capabilities that have not been provisioned.

## Build

```bash
docker build --no-cache -t miracle-cloud-desktop .
```

## Run locally

```bash
docker volume create miracle-docker
docker volume create miracle-data

docker run -d \
  --name miracle-cloud-desktop \
  --privileged \
  --restart unless-stopped \
  -p 6080:6080 \
  -e PORT=6080 \
  -e VNC_PASSWORD='change-this-password' \
  -v miracle-docker:/var/lib/docker \
  -v miracle-data:/data \
  miracle-cloud-desktop
```

Use a unique, strong password. Avoid sharing it in source code or logs.

## Access the desktop

Open:

http://localhost:6080/vnc.html

Enter the VNC password when prompted.

Ports:

| Service | Port |
|---|---:|
| TigerVNC | 5901, internal only |
| noVNC / HTTP | `PORT`, default 6080 |

## Docker tests

```bash
docker exec miracle-cloud-desktop docker version
docker exec miracle-cloud-desktop docker info
docker exec miracle-cloud-desktop docker compose version
docker exec miracle-cloud-desktop docker buildx version
```

To test pulling and running a container, use:

```bash
docker exec miracle-cloud-desktop docker run --rm hello-world
```

The nested Docker daemon requires host support. If startup fails, inspect:

```bash
docker logs miracle-cloud-desktop
```

The daemon log inside the container is:

```text
/var/log/dockerd.log
```

## KVM

The entrypoint checks whether `/dev/kvm` exists and is accessible.

For KVM acceleration, the host must provide:

- Hardware virtualization support
- A compatible host kernel and KVM modules
- The `/dev/kvm` device passed into the container
- Permissions to access that device

For example, on a compatible Linux host:

```bash
docker run --device=/dev/kvm ...
```

This option does not enable KVM on a host that lacks virtualization support.
KVM is not guaranteed to work on Railway or other restricted container platforms.

## Railway deployment

1. Push the four files to your repository.
2. Deploy the repository as a Dockerfile-based service.
3. Add `VNC_PASSWORD` under service variables.
4. In Settings → Networking → Public Networking, generate a domain.
5. Let the entrypoint use Railway's assigned `PORT`.
6. Redeploy and inspect deployment logs.

Open the generated HTTPS domain with `/vnc.html` appended:

```text
https://YOUR-GENERATED-DOMAIN/vnc.html
```

The web server binds to `0.0.0.0:$PORT` for Railway routing. VNC itself
is configured to listen on localhost inside the container.

**Security:** The generated domain exposes the noVNC web interface. Use
appropriate access controls at the platform or network layer if the service
must remain private. Do not expose the raw VNC port publicly.

## CPU, memory, and storage

The requested target is:

- 32 CPU cores
- More than 300 GB RAM
- At least 1.5 TB disk

These are host-level resource requirements, not values a Dockerfile can
guarantee. Provision a host or service plan that actually supplies them.
Docker runtime limits, platform quotas, and available disk capacity determine
the resources the container can use.

Persistent volumes preserve data only within the storage capacity provided
by the host. The `vfs` Docker storage driver prioritizes compatibility but
can consume considerably more disk space than overlay-based drivers.

## Troubleshooting

### `set: Illegal option -o pipefail`

The startup script is executed using Bash and the image installs Bash.
Rebuild the image without using a stale cached version:

```bash
docker build --no-cache -t miracle-cloud-desktop .
```

### Docker daemon fails

Check the container logs and `/var/log/dockerd.log`. The host may not permit
privileged containers, nested mounts, or the required kernel features.

### KVM unavailable

The host must pass `/dev/kvm` into the container. Installing KVM-related
packages inside the image alone does not enable hardware virtualization.

### noVNC domain does not open

Verify the service is healthy, `PORT` is set by the platform, the web server
is listening on that port, and the platform's target port matches the listener.
