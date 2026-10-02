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
# No browsers -- Cursor provides its own browser.
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

# -------------------------------------------------------------------
# Port metadata, expose both Cursor IDE and VeloQuant Trading Monitor ports
# -------------------------------------------------------------------
EXPOSE 8000
EXPOSE 8001
EXPOSE 3000

ENTRYPOINT ["/entry.sh"]

