#!/usr/bin/env bash
set -euo pipefail

# Inputs (env or defaults)
PROBE_RS_VERSION="${PROBE_RS_VERSION:-v0.31.0}"          # e.g. v0.31.0
PROBE_RS_INSTALL_ROOT="${PROBE_RS_INSTALL_ROOT:-/opt/probe-rs}"
PROBE_RS_GIT_URL="${PROBE_RS_GIT_URL:-https://github.com/probe-rs/probe-rs}"
PROBE_RS_FEATURES="${PROBE_RS_FEATURES:-remote}"
PROBE_RS_FORCE_INSTALL="${PROBE_RS_FORCE_INSTALL:-0}"    # set to 1 to force reinstall

# Choose install root (prefer persistent path if writable)
if [ -w "${PROBE_RS_INSTALL_ROOT}" ] || (mkdir -p "${PROBE_RS_INSTALL_ROOT}" 2>/dev/null); then
  INSTALL_ROOT="${PROBE_RS_INSTALL_ROOT}"
else
  INSTALL_ROOT="$HOME/.local/probe-rs"
  mkdir -p "${INSTALL_ROOT}"
fi
echo "Using INSTALL_ROOT=${INSTALL_ROOT}"

BIN="${INSTALL_ROOT}/bin/probe-rs"
REQ_VER="${PROBE_RS_VERSION#v}" # normalize: v0.31.0 -> 0.31.0

installed_version() {
  if [ -x "${BIN}" ]; then
    # Expected output: "probe-rs 0.31.0"
    "${BIN}" --version 2>/dev/null | awk '{print $2}' || true
  fi
}

has_remote_serve() {
  [ -x "${BIN}" ] && "${BIN}" help serve >/dev/null 2>&1
}

INSTALLED_VER="$(installed_version || true)"

if [ "${PROBE_RS_FORCE_INSTALL}" = "1" ]; then
  echo "Force install enabled."
  NEED_INSTALL=1
elif [ -z "${INSTALLED_VER}" ]; then
  echo "probe-rs not found."
  NEED_INSTALL=1
elif [ "${INSTALLED_VER}" != "${REQ_VER}" ]; then
  echo "probe-rs version mismatch: installed=${INSTALLED_VER}, required=${REQ_VER}"
  NEED_INSTALL=1
elif ! has_remote_serve; then
  echo "probe-rs is present but does not support 'serve' (remote feature missing)."
  NEED_INSTALL=1
else
  NEED_INSTALL=0
fi

if [ "${NEED_INSTALL}" = "0" ]; then
  echo "probe-rs ${INSTALLED_VER} already installed and supports 'serve'."
else
  echo "Installing probe-rs-tools (${PROBE_RS_VERSION}) with --features ${PROBE_RS_FEATURES}"

  # OS deps
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
      curl git pkg-config libusb-1.0-0-dev ca-certificates build-essential
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache \
      curl git pkgconfig libusb-dev ca-certificates build-base
  else
    echo "No supported package manager found (apt-get/apk)."
    exit 1
  fi

  # Rust toolchain
  if ! command -v cargo >/dev/null 2>&1; then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
  fi

  # Ensure a clean-ish install if version/feature changed
  rm -f "${INSTALL_ROOT}/bin/probe-rs" 2>/dev/null || true

  cargo install probe-rs-tools \
    --git "${PROBE_RS_GIT_URL}" \
    --tag "${PROBE_RS_VERSION}" \
    --locked \
    --features "${PROBE_RS_FEATURES}" \
    --root "${INSTALL_ROOT}"

  "${BIN}" --version
  "${BIN}" help serve >/dev/null
fi

# Export PATH for subsequent workflow steps
echo "${INSTALL_ROOT}/bin" >> "${GITHUB_PATH:?GITHUB_PATH is required}"

# Optional outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "install_root=${INSTALL_ROOT}"
    echo "bin_dir=${INSTALL_ROOT}/bin"
    echo "version=$("${BIN}" --version 2>/dev/null | awk '{print $2}' || true)"
  } >> "$GITHUB_OUTPUT"
fi
