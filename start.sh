#!/bin/bash
set -x
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/config.sh"

IMAGE_NAME="${IMAGE_NAME:-cursor-x11}"

DO_CLEAN=0
DO_GRANT_ACL=0
DO_AS_OWNER=0
for arg in "$@"; do
  case "$arg" in
    --clean) DO_CLEAN=1 ;;
    --grant-acl) DO_GRANT_ACL=1 ;;
    --as-owner) DO_AS_OWNER=1 ;;
    *)
      echo "ERROR: unknown argument: $arg"
      echo "Usage: ./start.sh [--clean] [--grant-acl] [--as-owner]"
      exit 1
      ;;
  esac
done

if [[ "$DO_CLEAN" -eq 1 ]]; then
  echo "Cleaning persisted state at ${PERSIST_BASE} ..."
  for d in cursor config cache mozilla local npm node-gyp; do
    [ -d "${PERSIST_BASE}/${d}" ] || continue
    ts=$(date +%Y%m%d-%H%M%S)
    mv "${PERSIST_BASE}/${d}" "${PERSIST_BASE}/${d}.bak-${ts}"
    echo "moved ${PERSIST_BASE}/${d} -> ${PERSIST_BASE}/${d}.bak-${ts}"
  done
fi

mkdir -p "${PERSIST_BASE}/config"
mkdir -p "${PERSIST_BASE}/cache"
mkdir -p "${PERSIST_BASE}/cursor"
mkdir -p "${PERSIST_BASE}/mozilla"
mkdir -p "${PERSIST_BASE}/local"
mkdir -p "${PERSIST_BASE}/npm"
mkdir -p "${PERSIST_BASE}/node-gyp"

if [[ "$DO_GRANT_ACL" -eq 1 ]]; then
  if ! command -v setfacl >/dev/null 2>&1; then
    echo "'setfacl' not found on host. Install 'acl' package or grant perms manually."
    exit 1
  fi
fi

trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

RO_LIST=$(mktemp)
RW_LIST=$(mktemp)
chmod 644 "$RO_LIST" "$RW_LIST"

declare -a VOLUMES
declare -a RW_HOSTS

# RO binds
while IFS= read -r line; do
  line=$(echo "$line" | trim)
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  host="${line%%->*}"; cont="${line##*->}"
  VOLUMES+=( "--volume" "${host}:${cont}:ro" )
  printf '%s\n' "${cont}" >> "${RO_LIST}"
done <<< "${RO_BINDS}"

# RW binds
while IFS= read -r line; do
  line=$(echo "$line" | trim)
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  host="${line%%->*}"; cont="${line##*->}"
  VOLUMES+=( "--volume" "${host}:${cont}:rw" )
  printf '%s\n' "${cont}" >> "${RW_LIST}"
  RW_HOSTS+=( "${host}" )
  if [[ "$DO_GRANT_ACL" -eq 1 ]]; then
    echo "Granting ACL rwx to uid:${TARGET_UID} on ${host} ..."
    sudo setfacl -m u:${TARGET_UID}:rwx "${host}" || echo "ACL grant failed on ${host} (FS may not support ACLs)"
    sudo setfacl -d -m u:${TARGET_UID}:rwx "${host}" || true
  fi
done <<< "${RW_BINDS}"

# Runtime identity - default to current user's UID/GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USERNAME=$(id -un)
TARGET_UID="${CURRENT_UID}"
TARGET_GID="${CURRENT_GID}"

# Validate current user
if [[ -z "$CURRENT_UID" || -z "$CURRENT_GID" ]]; then
  echo "ERROR: Could not determine current user UID/GID"
  exit 1
fi

# Override with --as-owner if specified
if [[ "$DO_AS_OWNER" -eq 1 ]]; then
  if [[ "${#RW_HOSTS[@]}" -eq 0 ]]; then
    echo "--as-owner requires at least one RW bind in config.sh"
    exit 1
  fi
  REF="${RW_HOSTS[0]}"
  if [[ ! -e "$REF" ]]; then
    echo "RW reference path not found on host: $REF"
    exit 1
  fi
  TARGET_UID=$(stat -c %u "$REF")
  TARGET_GID=$(stat -c %g "$REF")
  echo "Running container as owner of ${REF}: uid=${TARGET_UID} gid=${TARGET_GID}"
else
  echo "Running container as current user (${CURRENT_USERNAME}): uid=${TARGET_UID} gid=${TARGET_GID}"
fi

# Detect rootless Docker: the daemon itself runs as an unprivileged user.
# In rootless mode in-container root == the host user, so we run the app as
# in-container root (see entry.sh) and mount the writable tmpfs as 0:0.
ROOTLESS=0
if command -v pgrep >/dev/null 2>&1; then
  DOCKERD_PID=$(pgrep -x dockerd | head -n1 || true)
  if [[ -n "${DOCKERD_PID}" && -d "/proc/${DOCKERD_PID}" ]]; then
    DAEMON_UID=$(stat -c %u "/proc/${DOCKERD_PID}")
    if [[ "${DAEMON_UID}" != "0" ]]; then
      ROOTLESS=1
      echo "Detected rootless Docker daemon (uid=${DAEMON_UID})"
    fi
  fi
fi

if [[ "${ROOTLESS}" -eq 1 ]]; then
  TMPFS_UIDGID="uid=0,gid=0"
else
  TMPFS_UIDGID="uid=${TARGET_UID},gid=${TARGET_GID}"
fi

# X11 handling
DISPLAY_VAL="${DISPLAY:-}"
if [[ -z "$DISPLAY_VAL" ]]; then
  echo "DISPLAY is empty, cannot open X11"
  exit 1
fi

# Local X server via Unix socket
if [[ "$DISPLAY_VAL" =~ ^:([0-9]+) ]]; then
  if [[ "${USE_X11}" -eq 1 ]]; then
    xhost +local:docker >/dev/null
    VOLUMES+=( "--volume" "/tmp/.X11-unix:/tmp/.X11-unix:ro" )
  fi
else
  # SSH forwarded display over TCP, mount real Xauthority
  AUTH_FILE="${XAUTHORITY:-$HOME/.Xauthority}"
  if [[ -r "$AUTH_FILE" ]]; then
    VOLUMES+=( "--volume" "${AUTH_FILE}:/tmp/.Xauthority:ro" )
    ENV_XAUTH=( "--env" "XAUTHORITY=/tmp/.Xauthority" )
  else
    echo "XAUTHORITY not readable at ${AUTH_FILE}. Run without sudo, or export XAUTHORITY=~/.Xauthority"
    exit 1
  fi
fi

# Verify image
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "Image '${IMAGE_NAME}' not found. Run ./build.sh first."
  exit 1
fi

# Env
ENV_ARGS=(
  "--env" "DISPLAY=${DISPLAY_VAL}"
  "--env" "XDG_CONFIG_HOME=/home/${CURRENT_USERNAME}/.config"
  "--env" "XDG_CACHE_HOME=/home/${CURRENT_USERNAME}/.cache"
  "--env" "APPIMAGE_CONTAINER_DIR=${APPIMAGE_CONTAINER_DIR}"
  "--env" "APPIMAGE_FILENAME=${APPIMAGE_FILENAME}"
  "--env" "TARGET_UID=${TARGET_UID}"
  "--env" "TARGET_GID=${TARGET_GID}"
  "--env" "HOST_USER=${CURRENT_USERNAME}"
  "--env" "ROOTLESS=${ROOTLESS}"
  )

# Add XAUTH env if set
if [[ -n "${ENV_XAUTH+set}" ]]; then
  ENV_ARGS+=( "${ENV_XAUTH[@]}" )
fi

# SSH Agent detection and forwarding
SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}"
SSH_AGENT_PID="${SSH_AGENT_PID:-}"

if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]]; then
  echo "🔑 SSH Agent detected: $SSH_AUTH_SOCK"
  ENV_ARGS+=("--env" "SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
  ENV_ARGS+=("--env" "SSH_AGENT_PID=$SSH_AGENT_PID")
  ENV_ARGS+=("--env" "HOST_USER=$CURRENT_USER")
  # Mount SSH agent socket
  VOLUMES+=("--volume" "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK:ro")
else
  echo "⚠️  No SSH Agent detected. Starting SSH agent..."
  # Start SSH agent and load default key
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/id_rsa 2>/dev/null || echo "No default key found"
  ENV_ARGS+=("--env" "SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
  ENV_ARGS+=("--env" "SSH_AGENT_PID=$SSH_AGENT_PID")
  ENV_ARGS+=("--env" "HOST_USER=$CURRENT_USER")
  VOLUMES+=("--volume" "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK:ro")
fi

# Persisted dirs
VOLUMES+=( "--volume" "${PERSIST_BASE}/cursor:/home/${CURRENT_USERNAME}/.cursor:rw" )
VOLUMES+=( "--volume" "${PERSIST_BASE}/config:/home/${CURRENT_USERNAME}/.config:rw" )
VOLUMES+=( "--volume" "${PERSIST_BASE}/cache:/home/${CURRENT_USERNAME}/.cache:rw" )
VOLUMES+=( "--volume" "${PERSIST_BASE}/mozilla:/home/${CURRENT_USERNAME}/.mozilla:rw" )
VOLUMES+=( "--volume" "${PERSIST_BASE}/local:/home/${CURRENT_USERNAME}/.local:rw" )

# npm and Node.js cache directories for React development
VOLUMES+=( "--volume" "${PERSIST_BASE}/npm:/home/${CURRENT_USERNAME}/.npm:rw" )
VOLUMES+=( "--volume" "${PERSIST_BASE}/node-gyp:/home/${CURRENT_USERNAME}/.node-gyp:rw" )





# Mount verify lists
VOLUMES+=( "--volume" "${RO_LIST}:/etc/cursor-ro.list:ro" )
VOLUMES+=( "--volume" "${RW_LIST}:/etc/cursor-rw.list:ro" )

# Optional extra docker args
# e.g. EXTRA_DOCKER_ARGS="--env CURSOR_DEBUG=0 --env CURSOR_DEBUG_STRACE=1"
declare -a EXTRA_RUN_ARGS
EXTRA_RUN_ARGS=()
if [[ -n "${EXTRA_DOCKER_ARGS:-}" ]]; then
  # Intentional word splitting: one token per flag ("--env" "KEY=VALUE" ...)
  # shellcheck disable=SC2206
  EXTRA_RUN_ARGS+=(${EXTRA_DOCKER_ARGS})
fi

# Rootless-friendly, hardened run profile:
# - No --device /dev/fuse (AppImage uses --appimage-extract, see run_cursor.sh)
# - No --cap-add SYS_ADMIN (not granted by docker rootless anyway)
# - --cap-drop ALL: drop every capability the container would otherwise get
# - SETUID/SETGID kept ONLY so entry.sh can drop privileges via gosu
#   (root -> runtime user); the runtime user cannot gain anything back,
#   chown-style ownership changes stay unavailable (entry.sh is best-effort)
# - No apparmor:unconfined: keep the default profile for tighter confinement
docker run --rm -it \
  --cap-drop ALL \
  --cap-add SETUID \
  --cap-add SETGID \
  --shm-size="${SHM_SIZE}" \
  --net=host \
  --tmpfs "/home/${CURRENT_USERNAME}/writable:exec,${TMPFS_UIDGID}" \
  --tmpfs "/run:uid=0,gid=0,mode=755" \
  "${ENV_ARGS[@]}" \
  "${VOLUMES[@]}" \
  "${EXTRA_RUN_ARGS[@]}" \
  "${IMAGE_NAME}"

# Cleanup temp lists
rm -f "${RO_LIST}" "${RW_LIST}"

if [[ "${USE_X11}" -eq 1 && "$DISPLAY_VAL" =~ ^:([0-9]+) ]]; then
  xhost -local:docker >/dev/null
fi

