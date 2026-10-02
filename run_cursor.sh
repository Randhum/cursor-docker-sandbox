#!/bin/bash
set -euo pipefail

# Ensure HOME is set (fallback to /home/$(whoami) if not set)
export HOME="${HOME:-/home/$(whoami)}"

# ---------------------------------------------------------------------------
# Debug mode (verbose logging) -- ON by default for troubleshooting.
#   CURSOR_DEBUG=0          fully silent / normal startup
#   CURSOR_DEBUG_STRACE=1   additionally strace the app (log in CURSOR_LOG_DIR)
#   CURSOR_DEBUG_CHROMIUM_V 0..3  raise Chromium -v level (0 = default)
# entry.sh mirrors CURSOR_DEBUG for the SYSTEM dbus-daemon (DBUS_VERBOSE).
# ---------------------------------------------------------------------------
CURSOR_DEBUG="${CURSOR_DEBUG:-1}"
CURSOR_DEBUG_STRACE="${CURSOR_DEBUG_STRACE:-0}"
CURSOR_DEBUG_CHROMIUM_V="${CURSOR_DEBUG_CHROMIUM_V:-0}"
CURSOR_LOG_DIR="${CURSOR_LOG_DIR:-${HOME}/.local/logs}"
if [[ "$CURSOR_DEBUG" -eq 1 ]]; then
  echo "DEBUG: verbose logging ENABLED (CURSOR_DEBUG=1, chromium -v=${CURSOR_DEBUG_CHROMIUM_V}, strace=${CURSOR_DEBUG_STRACE})"
  export ELECTRON_ENABLE_LOGGING=1
  export DBUS_VERBOSE=1            # also applied to the system daemon by entry.sh
else
  echo "DEBUG: verbose logging disabled (CURSOR_DEBUG=0)"
fi
CHROMIUM_LOG_FLAGS=( --enable-logging=stderr )
if (( CURSOR_DEBUG_CHROMIUM_V > 0 )); then
  CHROMIUM_LOG_FLAGS+=( --v="${CURSOR_DEBUG_CHROMIUM_V}" )
fi
# Always trace the dbus/login1/session code paths a bit more verbosely:
# this is exactly where the org.freedesktop.login1.Manager.Inhibit error comes from
CHROMIUM_LOG_FLAGS+=( --vmodule="dbus*=3,login*=3,session*=2" )

# Verify mounts and permissions
"${HOME}/verify_fs.sh"

echo "Launching Cursor AppImage with system+session D-Bus and software GL..."
echo "Current user: $(whoami) (uid=$(id -u), gid=$(id -g))"

# Private session D-Bus.
# NOTE: keep --fork (daemonize). Running with --nofork here would BLOCK this
# script forever (dbus-daemon never exits), so Cursor would never launch.
# The daemonized daemon detaches its log output anyway, so keeping --fork also
# keeps the daemon's internal warnings (e.g. the benign "Failed to set fd
# limit to 65536: Operation not permitted" under --cap-drop ALL) out of the
# terminal.
SESSION_ARGS=( --address="unix:path=/tmp/dbus-session.sock" --fork )
SESSION_BUS="/tmp/dbus-session.sock"
[ -S "$SESSION_BUS" ] && rm -f "$SESSION_BUS"
dbus-daemon --session "${SESSION_ARGS[@]}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${SESSION_BUS}"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"

# ---------------------------------------------------------------------------
# D-Bus self-check (debug mode): show what the system bus will actually do
# for the org.freedesktop.login1 calls that Chromium makes at startup.
# ---------------------------------------------------------------------------
if [[ "$CURSOR_DEBUG" -eq 1 ]]; then
  echo "== D-Bus self-check (system bus) =="
  dbus-send --system --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>&1 || true
  echo "-- activatable service files --"
  find /usr/share/dbus-1 -name "*login1*" 2>/dev/null || true
  for f in /usr/share/dbus-1/services/org.freedesktop.login1.service \
           /usr/share/dbus-1/system-services/org.freedesktop.login1.service; do
    if [[ -r "$f" ]]; then echo "--- $f ---"; cat "$f"; fi
  done
  echo "== end D-Bus self-check =="
fi

# BROWSER alone is not enough. xdg-open consults the x-scheme-handler/http
# association first, and if that handler exits nonzero it fails the whole call
# (exit 4) without ever falling back to BROWSER. A stale firefox association in
# the host-persisted ~/.config or ~/.local/share would do exactly that, so
# claim the http/https handler for the logger as well.
APPS_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
mkdir -p "${APPS_DIR}"
cat > "${APPS_DIR}/cursor-sandbox-open-url.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Log URL to sandbox terminal
Exec=/usr/bin/firefox %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/http;x-scheme-handler/https;
DESKTOP
xdg-mime default cursor-sandbox-open-url.desktop \
  x-scheme-handler/http x-scheme-handler/https 2>/dev/null || true

# Software GL via ANGLE SwiftShader
export ELECTRON_OZONE_PLATFORM_HINT=x11
export LIBGL_ALWAYS_SOFTWARE=1
export ANGLE_DEFAULT_PLATFORM=swiftshader
export LIBGL_DEBUG=quiet
export MESA_DEBUG=silent

WRITABLE_DIR="${HOME}/writable"
mkdir -p "${WRITABLE_DIR}"

# Resolve AppImage path from env
APPIMAGE_CONTAINER_DIR="${APPIMAGE_CONTAINER_DIR:-/appimage}"
APPIMAGE_FILENAME="${APPIMAGE_FILENAME:-cursor.AppImage}"
APPIMAGE_SRC="${APPIMAGE_CONTAINER_DIR%/}/${APPIMAGE_FILENAME}"

# FUSE-free launch: extract the AppImage instead of mounting it.
# Works in Docker rootless and without SYS_ADMIN or /dev/fuse.
EXTRACT_DIR="${WRITABLE_DIR}/cursor-extracted"
if [ ! -x "${EXTRACT_DIR}/squashfs-root/AppRun" ]; then
  rm -rf "${EXTRACT_DIR}"
  mkdir -p "${EXTRACT_DIR}"
  echo "Extracting AppImage (FUSE-free mode, --appimage-extract)..."
  (cd "${EXTRACT_DIR}" && "${APPIMAGE_SRC}" --appimage-extract)
  chmod +x "${EXTRACT_DIR}/squashfs-root/AppRun" 2>/dev/null || true
fi

cd "${EXTRACT_DIR}/squashfs-root"

# ---------------------------------------------------------------------------
# Launch. In debug mode we optionally capture a strace log first (strace is
# in the image) so syscall-level failures (X11, dbus, GL) are inspectable.
# ---------------------------------------------------------------------------
if [[ "$CURSOR_DEBUG_STRACE" -eq 1 ]]; then
  mkdir -p "${CURSOR_LOG_DIR}"
  TS="$(date +%Y%m%d-%H%M%S)"
  STRACE_LOG="${CURSOR_LOG_DIR}/cursor-strace-${TS}.log"
  echo "DEBUG: strace enabled, writing syscall trace to ${STRACE_LOG}"
  exec strace -f -s 256 -o "${STRACE_LOG}" ./AppRun \
    --no-sandbox --disable-gpu "${CHROMIUM_LOG_FLAGS[@]}"
fi

exec ./AppRun --no-sandbox --disable-gpu "${CHROMIUM_LOG_FLAGS[@]}"

