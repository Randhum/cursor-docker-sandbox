# Cursor AppImage in Docker with Controlled File System Access

Run the **Cursor** editor inside a Docker container with controlled read only and read write mounts, software OpenGL, and D-Bus. The setup is **config driven**, edit `config.sh` only.

---

## 📂 Folder Structure

```
.
├── config.sh                          # Main configuration file
├── build.sh                           # Build the Docker image
├── start.sh                           # Start the container, apply mounts from config.sh
├── download_latest_cursor_AppImage.sh # Fetch the latest Cursor AppImage
├── Dockerfile                         # Image definition
├── entry.sh                           # Entrypoint, root to runtime uid
├── run_cursor.sh                      # Launches the Cursor AppImage
├── verify_fs.sh                       # Verifies RO, RW, exec permissions
└── README.md                          # This file
```

---

## ✅ Requirements

* Docker installed on the host
* X11 available on the host
  Local desktop, `DISPLAY=":0"`
  SSH with X forwarding, `ssh -Y`, `DISPLAY="localhost:N.0"`
* Cursor AppImage present at `${APPIMAGE_HOST_DIR}/${APPIMAGE_FILENAME}`
  Fetch via `./download_latest_cursor_AppImage.sh`

---

## ⚙️ Configuration

Edit **`config.sh`** and review:

* `IMAGE_NAME`
* `APPIMAGE_HOST_DIR`, `APPIMAGE_FILENAME`, `APPIMAGE_CONTAINER_DIR`
* `RO_BINDS` list of `host->container` read only paths
* `RW_BINDS` list of `host->container` read write paths
* `PERSIST_BASE` for `.config`, `.cache`, `.cursor`, `.mozilla`
* User identity is now dynamically determined from the host user (no more hardcoded UID/GID)
* `USE_X11` set to `1` to enable X11
* `SHM_SIZE` default `1g`

Example:

```bash
RO_BINDS="
/mnt/share->/mnt/share
${APPIMAGE_HOST_DIR}->/appimage
"
RW_BINDS="
/home/${USER}/monitor_cursor->/home/${USER}/monitor_cursor
"
```

Notes:

* `config.sh` in this repo resolves the current user automatically and supports `/home/vault/users/<user>` layouts.
* If you must elevate, prefer `sudo -E` so `DISPLAY` and `XAUTHORITY` are preserved.

---

## ⬇️ Download Latest Cursor AppImage

```bash
./download_latest_cursor_AppImage.sh
```

Saves to `${APPIMAGE_HOST_DIR}/${APPIMAGE_FILENAME}`.

---

## 🔨 Build

```bash
./build.sh
```

Creates `${PERSIST_BASE}/{config,cache,cursor,mozilla}` and builds the image with X11, Mesa software GL, D-Bus, Firefox and a Python 3.14 environment. The image contains **no FUSE dependencies** -- the AppImage is launched via `--appimage-extract`, so `/dev/fuse` and `SYS_ADMIN` are not needed and the sandbox works in a **Docker rootless** environment.

---

## 🚀 Start, recommended flags for NFS and SSH

Most reliable command on corporate and NFS setups:

```bash
./start.sh --as-owner
```

What these flags do:

* `--as-owner` runs the app as the owner uid,gid of the first RW bind, matching host permissions

Other useful flags:

* `--clean` rotate `${PERSIST_BASE}` dirs to `.bak-<timestamp>`
* `--grant-acl` apply `setfacl` for `CONTAINER_UID` on RW host dirs if the filesystem supports ACLs

Examples:

```bash
./start.sh
./start.sh --as-owner
./start.sh --clean --as-owner
```

SSH X forwarding tips:

* Run from the same shell where `echo $DISPLAY` prints `localhost:N.0`
* Avoid plain `sudo`; if needed use `sudo -E ./start.sh` to preserve `DISPLAY` and `XAUTHORITY`

---

## 🔍 What happens on start

1. `start.sh` parses bind lists, sets up X11, passes your `DISPLAY`
2. `verify_fs.sh` confirms RO cannot be written, RW can be written, and an exec tmpfs works
3. `run_cursor.sh` starts a session D-Bus, extracts the AppImage (`--appimage-extract`) and launches `AppRun` with software GL

Example output:

```
== FS verify ==
-- RO checks --
RO: /appimage ... OK
-- RW checks --
RW: /home/you/monitor_cursor ... OK
-- EXEC check -- OK
Launching Cursor AppImage with system+session D-Bus and software GL...
```

---

## 🐞 Debug mode (verbose logging)

Debug mode is **ON by default** in `run_cursor.sh` (and `entry.sh`). It enables:

* `DBUS_VERBOSE=1` on the system **and** session `dbus-daemon`s (both stay
  daemonized with `--fork`; their internal warnings are detached from the
  terminal — important because `--nofork` here would block the script forever)
* `ELECTRON_ENABLE_LOGGING=1` + `--enable-logging=stderr` for Chromium/Electron
* `--vmodule="dbus*=3,login*=3,session*=2"` so the logind/session code paths log in detail
* A **D-Bus self-check** at startup: dumps the system bus names, the `login1`
  activation files, and prints them right before launching

On top of that (off by default):

* `CURSOR_DEBUG_STRACE=1` — record the app's syscalls to
  `${CURSOR_LOG_DIR}/cursor-strace-<ts>.log`. `CURSOR_LOG_DIR` defaults to
  `${HOME}/.local/logs`, which is **persisted** on the host (see `PERSIST_BASE`),
  so the trace survives a container crash.
* `CURSOR_DEBUG_CHROMIUM_V=1|2|3` — raise the global Chromium `-v` level

Disable/adjust per run (the scripts are baked into the image, but these env vars are
read at **container start**, so no rebuild is needed to toggle them):

```bash
EXTRA_DOCKER_ARGS="--env CURSOR_DEBUG=0" ./start.sh            # back to normal logging
EXTRA_DOCKER_ARGS="--env CURSOR_DEBUG_STRACE=1" ./start.sh     # + syscall trace
EXTRA_DOCKER_ARGS="--env CURSOR_DEBUG_CHROMIUM_V=2" ./start.sh # + Chromium -v=2
```

---

## 🧹 Cleanup

Containers run with `--rm` and are removed on exit.
To erase persisted state:

```bash
rm -rf "${PERSIST_BASE}"
```

---

## 🔧 Troubleshooting

**X11 connection rejected, or platform failed to initialize**
Ensure `DISPLAY=localhost:N.0` and run from the same SSH session. Avoid plain `sudo`; use `sudo -E`.

**`ERROR:dbus/object_proxy.cc ... Failed to call method: org.freedesktop.login1.Manager.Inhibit ... Spawn.ChildExited`**
Benign, expected in this container. The image has no `systemd-logind`, but ships the
systemd D-Bus activation stub `/usr/share/dbus-1/system-services/org.freedesktop.login1.service`
whose `Exec=` is literally `/bin/false`. So when Chromium asks the system bus to inhibit
idle/suspend, `dbus-daemon` spawns `/bin/false`, it exits 1, and Chromium logs that error
and continues. Cursor still starts. Use debug mode (below) if something *else* fails after it.

**On NFS, RW path says permission denied**
Use `./start.sh --as-owner` so the kernel sees the same uid,gid as on the host.

**Firefox shows “profile cannot be loaded”**
`.mozilla` is persisted and mounted. After `--clean`, the first run recreates it. If an old unreadable profile exists, remove `${PERSIST_BASE}/mozilla`.

**Corporate proxy blocks login or re‑signs TLS**
Export your proxy on the host so Firefox inside inherits it:

```bash
export HTTPS_PROXY=http://proxy.example.com:3128
export HTTP_PROXY=http://proxy.example.com:3128
export NO_PROXY=localhost,127.0.0.1,::1
./start.sh --as-owner
```

If TLS interception errors appear, place your corporate root CA PEM into `${PERSIST_BASE}/certs` and follow certificate import notes in `entry.sh`.

**Firefox prints `glxtest: libpci missing`**
Benign with software GL; the Dockerfile installs `libpci3` and `libpciaccess0` to silence it.

---

## 📌 Notes

* Software rendering only, no GPU passthrough required
* Firefox is installed and registered as default browser, `xdg-open` uses it
* X11 over SSH requires valid `DISPLAY` and `XAUTHORITY` in your shell
* FUSE-free: the AppImage is unpacked with `--appimage-extract`, so the container needs **no** `/dev/fuse`, **no** `SYS_ADMIN` and runs with `--cap-drop ALL` -- compatible with Docker rootless
* Python 3.14 is installed from the distro and isolated in a dedicated venv at `/opt/venv` (activated via `PATH`, `VIRTUAL_ENV` set)

---

**Tagline**
Run Cursor in a secure, configurable Docker sandbox, controlled filesystem access, predictable auth and rendering paths.

