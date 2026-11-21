# docker-ubuntu-desktop

Ubuntu 22.04 Desktop running in Docker.

## Features

- Ubuntu 22.04
- XFCE4 Desktop
- TigerVNC
- noVNC
- Firefox
- Root user
- Web browser access

## Build

```bash
docker build -t ubuntu-desktop .
```

## Run

```bash
docker run -it \
-p 5901:5901 \
-p 6080:6080 \
ubuntu-desktop
```

Open:

```
https://localhost:6080
```

or

```
http://localhost:6080
```

depending on your browser.

VNC Port:

```
5901
```
