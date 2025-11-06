# ============================================================
# Module : defaults.sh
# Purpose: Define default configuration values for the builder
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================
#!/usr/bin/env bash

# Default Proxmox container settings
DEFAULT_CTID=2000
DEFAULT_CTNAME="velocloud-builder"
DEFAULT_STORAGE="local-lvm"
DEFAULT_TEMPLATE_STORAGE="local"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_CPU=2
DEFAULT_MEMORY=2048
DEFAULT_ROOT_PASS="velocloud123"
DEFAULT_PORT=8080
DEFAULT_TAILSCALE_KEY=""
DEFAULT_VELOCLOUD_VERSION="4.5.0"

# Guard rails
MIN_CTID=100
TAILSCALE_POLL_INTERVAL="${TAILSCALE_POLL_INTERVAL:-60}"
PROMPT_MODE="${PROMPT_MODE:-auto}"

# Debian template detection
DEBIAN_TEMPLATE_GLOB="debian-*-standard_*_amd64.tar.zst"
DEBIAN_TEMPLATE_REGEX="debian-[0-9]+-standard.*amd64\.tar\.zst"
TEMPLATE_DIR="/var/lib/vz/template/cache"
TEMPLATE=""

# Resolvable configuration defaults with environment overrides
CTID="${CTID:-$DEFAULT_CTID}"
CTNAME="${CTNAME:-$DEFAULT_CTNAME}"
STORAGE="${STORAGE:-$DEFAULT_STORAGE}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-$DEFAULT_TEMPLATE_STORAGE}"
BRIDGE="${BRIDGE:-$DEFAULT_BRIDGE}"
CPU="${CPU:-$DEFAULT_CPU}"
MEMORY="${MEMORY:-$DEFAULT_MEMORY}"
ROOT_PASS="${ROOT_PASS:-$DEFAULT_ROOT_PASS}"
PORT="${PORT:-$DEFAULT_PORT}"
TAILSCALE_KEY="${TAILSCALE_KEY:-$DEFAULT_TAILSCALE_KEY}"
VELOCLOUD_VERSION="${VELOCLOUD_VERSION:-$DEFAULT_VELOCLOUD_VERSION}"
