#!/bin/bash
set -euo pipefail

# Ensure HOME is set (fallback to /home/$(whoami) if not set)
export HOME="${HOME:-/home/$(whoami)}"

# Verify mounts and permissions
"${HOME}/verify_fs.sh"

echo "Launching Cursor AppImage with system+session D-Bus and software GL..."
echo "Current user: $(whoami) (uid=$(id -u), gid=$(id -g))"

# Private session D-Bus
SESSION_BUS="/tmp/dbus-session.sock"
[ -S "$SESSION_BUS" ] && rm -f "$SESSION_BUS"
dbus-daemon --session --address="unix:path=${SESSION_BUS}" --fork
export DBUS_SESSION_BUS_ADDRESS="unix:path=${SESSION_BUS}"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"

# Browser for xdg-open
export BROWSER=/usr/bin/firefox

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
exec ./AppRun --no-sandbox --disable-gpu

