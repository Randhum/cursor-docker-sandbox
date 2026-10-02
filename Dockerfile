# syntax=docker/dockerfile:1

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_CACHE_DIR=/tmp/pip-cache \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/root/.local/bin:${PATH}

# ===================================================================
# Base system + complete native development environment
# ===================================================================
#
# Keep ALL Ubuntu packages in one layer.
#
# This is intentionally a broad "ultra development" environment:
# Python extensions, C/C++, databases, scientific computing,
# graphics/Electron, compression, RPC, storage, hardware, etc.
#
# No browsers -- Cursor provides its own browser. - A Vision newer to come true, see the evolution of browsers. Install Firefox below
# ===================================================================
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    \
    # ---------------------------------------------------------------
    # Core utilities
    # ---------------------------------------------------------------
    ca-certificates \
    curl \
    wget \
    gnupg \
    gosu \
    uuid-runtime \
    git \
    git-lfs \
    openssh-client \
    rsync \
    sudo \
    \
    # ---------------------------------------------------------------
    # Build toolchain
    # ---------------------------------------------------------------
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    ninja-build \
    meson \
    autoconf \
    automake \
    libtool \
    m4 \
    gettext \
    pkg-config \
    \
    # ---------------------------------------------------------------
    # Debugging / diagnostics
    # ---------------------------------------------------------------
    gdb \
    strace \
    ltrace \
    lsof \
    psmisc \
    procps \
    file \
    patch \
    diffutils \
    findutils \
    util-linux \
    \
    # ---------------------------------------------------------------
    # Shell / CLI utilities
    # ---------------------------------------------------------------
    jq \
    tree \
    less \
    vim-tiny \
    nano \
    \
    # ---------------------------------------------------------------
    # Archive / compression utilities
    # ---------------------------------------------------------------
    unzip \
    zip \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    zstd \
    \
    # ---------------------------------------------------------------
    # Hardware / system inspection
    # ---------------------------------------------------------------
    pciutils \
    usbutils \
    \
    # ---------------------------------------------------------------
    # Cursor / Electron / X11
    # ---------------------------------------------------------------
    xauth \
    x11-utils \
    xdg-utils \
    libgtk-3-0t64 \
    libasound2t64 \
    libnss3 \
    libxss1 \
    libxtst6 \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libx11-xcb1 \
    libxkbcommon0 \
    libxcb-render0 \
    libxcb-shm0 \
    libxcb-xfixes0 \
    libxcb-randr0 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-icccm4 \
    libxcb-util1 \
    libdrm2 \
    libgbm1 \
    \
    # ---------------------------------------------------------------
    # D-Bus
    # ---------------------------------------------------------------
    dbus \
    dbus-x11 \
    \
    # ---------------------------------------------------------------
    # OpenGL / Mesa
    # ---------------------------------------------------------------
    mesa-utils \
    libgl1 \
    libglx-mesa0 \
    libgl1-mesa-dri \
    libegl1 \
    libgles2 \
    \
    # ---------------------------------------------------------------
    # Python 3.14
    # ---------------------------------------------------------------
    python3.14 \
    python3.14-dev \
    python3.14-venv \
    python3.14-full \
    pipx \
    \
    # ---------------------------------------------------------------
    # Python native extension development
    # ---------------------------------------------------------------
    libffi-dev \
    libssl-dev \
    libbz2-dev \
    liblzma-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses-dev \
    libgdbm-dev \
    libexpat1-dev \
    tk-dev \
    uuid-dev \
    libdb-dev \
    \
    # ---------------------------------------------------------------
    # Compression libraries
    # ---------------------------------------------------------------
    zlib1g-dev \
    libzstd-dev \
    liblz4-dev \
    libsnappy-dev \
    liblzo2-dev \
    \
    # ---------------------------------------------------------------
    # XML / HTML
    # ---------------------------------------------------------------
    libxml2-dev \
    libxslt1-dev \
    \
    # ---------------------------------------------------------------
    # Image / font libraries
    # ---------------------------------------------------------------
    libjpeg-turbo8-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    libopenjp2-7-dev \
    libfreetype-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    \
    # ---------------------------------------------------------------
    # Database development
    # ---------------------------------------------------------------
    libpq-dev \
    libpqxx-dev \
    default-libmysqlclient-dev \
    unixodbc-dev \
    freetds-dev \
    \
    # ---------------------------------------------------------------
    # Scientific / numerical
    # ---------------------------------------------------------------
    libhdf5-dev \
    libnuma1 \
    libnuma-dev \
    hwloc \
    libopenblas-dev \
    liblapack-dev \
    libgomp1 \
    \
    # ---------------------------------------------------------------
    # C / C++ ecosystem
    # ---------------------------------------------------------------
    libboost-all-dev \
    libeigen3-dev \
    libtbb-dev \
    libjemalloc-dev \
    libunwind-dev \
    libtcmalloc-minimal4t64 \
    \
    # ---------------------------------------------------------------
    # RPC / serialization
    # ---------------------------------------------------------------
    protobuf-compiler \
    libprotobuf-dev \
    libprotoc-dev \
    libgrpc++-dev \
    \
    # ---------------------------------------------------------------
    # Embedded / high-performance storage
    # ---------------------------------------------------------------
    libleveldb-dev \
    librocksdb-dev \
    liblmdb-dev \
    \
    # ---------------------------------------------------------------
    # Hardware / device development
    # ---------------------------------------------------------------
    libpci-dev \
    libpciaccess-dev \
    libudev-dev \
    libusb-1.0-0-dev \
    libdrm-dev \
    \
    # ---------------------------------------------------------------
    # Networking / system libraries
    # ---------------------------------------------------------------
    libcurl4-openssl-dev \
    libevent-dev \
    libarchive-dev \
    libyaml-dev \
    libedit-dev \
    libpoco-dev \
    \
    # NOTE: No FUSE packages (libfuse, fuse3, fuse-overlayfs, fusermount) on
    # purpose -- the AppImage is run with --appimage-extract, so FUSE,
    # /dev/fuse and SYS_ADMIN are NOT required. This keeps the image fully
    # compatible with Docker rootless and hardened (cap-drop ALL) profiles.
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

 # ===================================================================
# Firefox, from Mozilla's APT repository
# ===================================================================
#
# Ubuntu's own "firefox" package is a ~76 kB stub that Pre-Depends on snapd and
# only installs the Firefox snap. snapd cannot run in this container, so that
# package is useless here; Mozilla's repository ships a real .deb.
#
# The apt pin is required, not cosmetic. Ubuntu's stub carries an epoch
# (1:1snap1-0ubuntu8) which sorts ABOVE Mozilla's unepoched 156.0, so without a
# higher pin priority apt would keep choosing the snap stub.
#
# Firefox's dependencies use pre-time_t-transition names (libgtk-3-0,
# libasound2, libatk1.0-0, libglib2.0-0, libgcc1); on Ubuntu 26.04 these are
# all satisfied via Provides: by the t64 packages, so no shims are needed.
# ===================================================================
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
      -o /etc/apt/keyrings/packages.mozilla.org.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
      > /etc/apt/sources.list.d/mozilla.list \
 && printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
      > /etc/apt/preferences.d/mozilla \
 && apt-get update \
 && apt-get install -y --no-install-recommends firefox \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean \
 && test -x /usr/bin/firefox \
 && firefox --version

# Register Firefox as the system-wide http/https handler, so xdg-open resolves
# it for every runtime uid. xdg-open consults this association BEFORE $BROWSER
# and aborts if the handler fails, so it must point at something real.
RUN mkdir -p /etc/xdg \
 && printf '[Default Applications]\nx-scheme-handler/http=firefox.desktop\nx-scheme-handler/https=firefox.desktop\n' \
      > /etc/xdg/mimeapps.list



# ===================================================================
# Python development environment
# ===================================================================
#
# Do NOT modify Ubuntu's system Python.
# Create one dedicated Python 3.14 environment.
# ===================================================================

RUN python3.14 -m venv "${VIRTUAL_ENV}" \
 && "${VIRTUAL_ENV}/bin/python" -m pip install --upgrade \
      pip \
      setuptools \
      wheel \
      packaging \
      build \
      hatch \
      uv \
 && mkdir -p "${PIP_CACHE_DIR}" \
 && chmod 1777 "${PIP_CACHE_DIR}"


# ===================================================================
# General Python development / scientific stack
# ===================================================================

RUN --mount=type=cache,target=/tmp/pip-cache \
    python -m pip install \
      numpy \
      pandas \
      scipy \
      matplotlib \
      seaborn \
      scikit-learn \
      h5py \
      Cython \
      psutil \
      lxml \
      tabulate \
      sortedcontainers \
      decorator \
      defusedxml \
      filelock \
      tqdm \
      tornado \
      beartype \
      einops


# ===================================================================
# Machine learning
# ===================================================================

RUN --mount=type=cache,target=/tmp/pip-cache \
    python -m pip install \
      torch \
      torchvision \
      torch-optimizer \
      catboost \
      xgboost \
      lightgbm


# ===================================================================
# Database / finance / scientific packages
# ===================================================================

RUN --mount=type=cache,target=/tmp/pip-cache \
    python -m pip install \
      psycopg2-binary \
      polygon-api-client \
      exchange_calendars \
      holidays \
      openturns


# ===================================================================
# Web / ASGI development
# ===================================================================

RUN --mount=type=cache,target=/tmp/pip-cache \
    python -m pip install \
      "uvicorn[standard]" \
      watchfiles


# ===================================================================
# Final verification
# ===================================================================

RUN python --version \
 && python -m pip --version \
 && python -c "import sys; print('Python:', sys.version)" \
 && python -c "import numpy, pandas, scipy; print('Scientific stack: OK')" \
 && python -c "import torch; print('PyTorch:', torch.__version__)" \
 && cmake --version \
 && gcc --version | head -1 \
 && g++ --version | head -1


# ===================================================================
# Default working directory
# ===================================================================
RUN mkdir -p /home/workspace
WORKDIR /home/workspace

# -------------------------------------------------------------------
# Passwordless sudo configuration (will be set up dynamically at runtime)
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# App scripts
# -------------------------------------------------------------------
COPY entry.sh /entry.sh
COPY verify_fs.sh /home/workspace/verify_fs.sh
COPY run_cursor.sh /home/workspace/run_cursor.sh
RUN chmod +x /entry.sh /home/workspace/verify_fs.sh /home/workspace/run_cursor.sh \
 && chmod a+rx /home/workspace /home/workspace/run_cursor.sh \
 && chmod 1777 /home/workspace

ENTRYPOINT ["/entry.sh"]

