#!/usr/bin/env bash
# Cloud-Init Builder (Proxmox + Tailscale + Flask)
# Modular Single-File Installer -- GitHub Ready

set -euo pipefail
IFS=$'\n\t'

# ========= GLOBAL CONFIG =========
SCRIPT_NAME="$(basename "$0")"

DEFAULT_CTID=450
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
DEFAULT_TAILSCALE_MODE="link"
MIN_CTID=100

CTID="${CTID:-$DEFAULT_CTID}"
TAILSCALE_MODE="${TAILSCALE_MODE:-$DEFAULT_TAILSCALE_MODE}"
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

DEBIAN_TEMPLATE_GLOB="debian-*-standard_*_amd64.tar.zst"
DEBIAN_TEMPLATE_REGEX="debian-[0-9]+-standard.*amd64\.tar\.zst"
TEMPLATE_DIR="/var/lib/vz/template/cache"
TEMPLATE=""
TAILSCALE_POLL_INTERVAL=60
PROMPT_MODE="${PROMPT_MODE:-auto}"

have_tty() {
  [[ -t 0 ]] || [[ -t 1 ]] || [[ -t 2 ]] || [[ -r /dev/tty ]]
}

# ========= UTILITY FUNCTIONS =========
log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_ok()   { echo -e "\033[1;32m[OK]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_err()  { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

tty_print() {
  if have_tty; then
    printf "%s\n" "$1" > /dev/tty
  else
    printf "%s\n" "$1"
  fi
}

prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local silent="${3:-0}"
  local input=""

  if [[ "$PROMPT_MODE" == "off" ]]; then
    echo "$default"
    return
  fi

  if ! have_tty; then
    log_warn "TTY not available for prompt '${prompt//\n/ }'; using default."
    echo "$default"
    return
  fi

  local tty="/dev/tty"
  if [[ "$silent" == "1" ]]; then
    printf "%s" "$prompt" > "$tty"
    IFS= read -r -s input < "$tty" || true
    printf "\n" > "$tty"
  else
    printf "%s" "$prompt" > "$tty"
    IFS= read -r input < "$tty" || true
  fi

  if [[ -z "$input" ]]; then
    input="$default"
  fi

  echo "$input"
}

die() {
  log_err "$1"
  exit "${2:-1}"
}

confirm() {
  local prompt="${1:-Proceed?}"
  if [[ "$PROMPT_MODE" == "off" ]]; then
    return 1
  fi
  if ! have_tty; then
    log_warn "TTY not available; defaulting to 'no' for prompt: $prompt"
    return 1
  fi
  local response=""
  printf "%s [y/N]: " "$prompt" > /dev/tty
  IFS= read -r response < /dev/tty || true
  case "${response,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Required command not found: $cmd"
  fi
}

run_safe() {
  local desc="$1"
  shift
  log_info "$desc"
  if "$@"; then
    log_ok "$desc"
  else
    die "Failed: $desc"
  fi
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\"'\"'/g")"
}

customize_configuration() {
  if [[ "$PROMPT_MODE" == "off" ]]; then
    log_info "Skipping interactive customization (PROMPT_MODE=off)"
    return
  fi

  if [[ "$PROMPT_MODE" == "auto" && ! have_tty ]]; then
    log_info "TTY not detected; using defaults. Use CLI flags or environment variables to override."
    return
  fi

  tty_print ""
  tty_print "=== Cloud-Init Builder Interactive Setup ==="
  tty_print "Current defaults:"
  tty_print "  CTID              : $CTID"
  tty_print "  CT Name           : $CTNAME"
  tty_print "  Storage           : $STORAGE"
  tty_print "  Template Storage  : $TEMPLATE_STORAGE"
  tty_print "  Bridge            : $BRIDGE"
  tty_print "  CPU Cores         : $CPU"
  tty_print "  Memory (MB)       : $MEMORY"
  tty_print "  Root Password     : (hidden)"
  tty_print "  WebUI Port        : $PORT"
  tty_print "  Velocloud Version : $VELOCLOUD_VERSION"
  tty_print ""

  local customize="no"
  if [[ "$PROMPT_MODE" == "on" ]]; then
    customize="yes"
  elif confirm "Customize container settings now?"; then
    customize="yes"
  fi

  if [[ "$customize" == "yes" ]]; then
    local value backup

    backup="$CTID"
    value=$(prompt_value "Container ID [$CTID]: " "$CTID")
    CTID="$value"
    if ! [[ "$CTID" =~ ^[0-9]+$ ]]; then
      tty_print "Invalid CTID value. Reverting to $backup."
      CTID="$backup"
    elif (( CTID < MIN_CTID )); then
      tty_print "CTID must be >= $MIN_CTID. Reverting to $backup."
      CTID="$backup"
    fi

    value=$(prompt_value "Container hostname [$CTNAME]: " "$CTNAME")
    [[ -n "$value" ]] && CTNAME="$value"

    value=$(prompt_value "Storage target [$STORAGE]: " "$STORAGE")
    [[ -n "$value" ]] && STORAGE="$value"

    value=$(prompt_value "Template storage [$TEMPLATE_STORAGE]: " "$TEMPLATE_STORAGE")
    [[ -n "$value" ]] && TEMPLATE_STORAGE="$value"

    value=$(prompt_value "Network bridge [$BRIDGE]: " "$BRIDGE")
    [[ -n "$value" ]] && BRIDGE="$value"

    backup="$CPU"
    value=$(prompt_value "CPU cores [$CPU]: " "$CPU")
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      CPU="$value"
    else
      tty_print "Invalid CPU value. Reverting to $backup."
      CPU="$backup"
    fi

    backup="$MEMORY"
    value=$(prompt_value "Memory (MB) [$MEMORY]: " "$MEMORY")
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      MEMORY="$value"
    else
      tty_print "Invalid memory value. Reverting to $backup."
      MEMORY="$backup"
    fi

    backup="$PORT"
    value=$(prompt_value "WebUI port [$PORT]: " "$PORT")
    if [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 65535 ]]; then
      PORT="$value"
    else
      tty_print "Invalid port value. Reverting to $backup."
      PORT="$backup"
    fi

    value=$(prompt_value "Velocloud version [$VELOCLOUD_VERSION]: " "$VELOCLOUD_VERSION")
    [[ -n "$value" ]] && VELOCLOUD_VERSION="$value"

    value=$(prompt_value "Root password (hidden) [$ROOT_PASS]: " "$ROOT_PASS" 1)
    [[ -n "$value" ]] && ROOT_PASS="$value"
  fi

  if [[ "$PROMPT_MODE" != "off" && have_tty ]]; then
    tty_print ""
    tty_print "Tailscale install options:"
    tty_print "  1) Join via login link"
    tty_print "  2) Join with auth key"
    tty_print "  3) Skip Tailscale installation"
    local mode_input
    mode_input=$(prompt_value "Select mode [1-3, default ${TAILSCALE_MODE}]: " "$TAILSCALE_MODE")
    case "${mode_input,,}" in
      1|link) TAILSCALE_MODE="link" ;;
      2|auth) TAILSCALE_MODE="auth" ;;
      3|skip) TAILSCALE_MODE="skip" ;;
      *)
        tty_print "Invalid selection; keeping ${TAILSCALE_MODE}."
        ;;
    esac
  fi

  if [[ "$TAILSCALE_MODE" == "auth" ]]; then
    if [[ -z "$TAILSCALE_KEY" ]]; then
      tty_print ""
      tty_print "Provide a reusable Tailscale auth key to auto-connect this container."
      tty_print "Expected format: tskey-auth-XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
      tty_print "Leave blank to skip auto-join and configure later from the WebUI or shell."
      local key
      key=$(prompt_value "Tailscale auth key: " "")
      if [[ -n "$key" ]]; then
        TAILSCALE_KEY="$key"
        if ! [[ "$TAILSCALE_KEY" =~ ^tskey-auth-[A-Za-z0-9_-]{10,}$ ]]; then
          log_warn "Provided Tailscale auth key does not match the typical tskey-auth- format. Double-check before proceeding."
        fi
      fi
    fi
  else
    TAILSCALE_KEY=""
  fi

  tty_print ""
  tty_print "Tip: Prepare a Tailscale API key (format tskey-api-XXXXXXXXXXXXXXXXXXXXXXXXXXXX) for the WebUI"
  tty_print "so the device list can be synchronized once the container is online."
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  --ctid <id>               Container ID (>= $MIN_CTID, default: $DEFAULT_CTID)
  --ctname <name>           Container hostname (default: $DEFAULT_CTNAME)
  --storage <name>          Storage for container rootfs (default: $DEFAULT_STORAGE)
  --template-storage <name> Storage for templates (default: $DEFAULT_TEMPLATE_STORAGE)
  --bridge <bridge>         Network bridge (default: $DEFAULT_BRIDGE)
  --cpu <cores>             CPU cores (default: $DEFAULT_CPU)
  --memory <mb>             Memory in MB (default: $DEFAULT_MEMORY)
  --root-pass <pass>        Root password (default: $DEFAULT_ROOT_PASS)
  --port <port>             WebUI port (default: $DEFAULT_PORT)
  --auth-key <key>          Tailscale auth key for auto-join
  --tailscale-mode <mode>   Tailscale install mode: link|auth|skip (default: $DEFAULT_TAILSCALE_MODE)
  --velocloud-version <ver> Target Velocloud version (default: $DEFAULT_VELOCLOUD_VERSION)
  --prompt                  Force interactive prompts even if defaults exist
  --no-prompt               Disable interactive prompts
  -h, --help                Show this help message

Environment variables with matching names can also override defaults.
EOF
}

# ========= VALIDATION =========
validate_environment() {
  log_info "Validating Proxmox environment"
  [[ "$(id -u)" -eq 0 ]] || die "This script must be run as root on the Proxmox host."
  for cmd in pct pvesm pveam pveversion awk sort tail grep find; do
    require_command "$cmd"
  done
  if pveversion | grep -q "^pve-manager/9"; then
    log_ok "Proxmox 9 detected"
  else
    log_warn "Proxmox 9 not detected. Continuing, but this script is tested against Proxmox 9."
  fi
}

validate_parameters() {
  [[ "$CTID" =~ ^[0-9]+$ ]] || die "CTID must be numeric."
  (( CTID >= MIN_CTID )) || die "CTID must be >= $MIN_CTID."
  [[ "$CPU" =~ ^[0-9]+$ ]] || die "CPU must be numeric."
  [[ "$MEMORY" =~ ^[0-9]+$ ]] || die "MEMORY must be numeric."
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die "PORT must be between 1 and 65535."
  [[ -n "$CTNAME" ]] || die "CTNAME cannot be empty."
  [[ -n "$STORAGE" ]] || die "STORAGE cannot be empty."
  [[ -n "$TEMPLATE_STORAGE" ]] || die "TEMPLATE_STORAGE cannot be empty."
  [[ -n "$BRIDGE" ]] || die "BRIDGE cannot be empty."
  [[ "$TAILSCALE_MODE" =~ ^(link|auth|skip)$ ]] || die "TAILSCALE_MODE must be 'link', 'auth', or 'skip'."
  [[ -n "$VELOCLOUD_VERSION" ]] || die "Velocloud version cannot be empty."
}

validate_storage() {
  log_info "Validating storage configuration"
  if ! pvesm status | awk '{print $1}' | grep -qx "$STORAGE"; then
    die "Storage '$STORAGE' not found in pvesm status."
  fi
  if ! pvesm status | awk '{print $1}' | grep -qx "$TEMPLATE_STORAGE"; then
    die "Template storage '$TEMPLATE_STORAGE' not found in pvesm status."
  fi
  log_ok "Storage configuration verified"
}

# ========= TEMPLATE HANDLER =========
ensure_template() {
  log_info "Ensuring Debian LXC template is available"
  mkdir -p "$TEMPLATE_DIR"
  local existing
  existing=$(find "$TEMPLATE_DIR" -maxdepth 1 -type f -name "$DEBIAN_TEMPLATE_GLOB" | sort -V | tail -n1 || true)
  if [[ -n "$existing" ]]; then
    TEMPLATE="$existing"
    log_ok "Using existing template $(basename "$TEMPLATE")"
    return
  fi

  log_info "Downloading latest Debian template from Proxmox repositories"
  pveam update >/dev/null 2>&1 || log_warn "Failed to update template catalog; attempting download with existing catalog."
  local latest
  latest=$(pveam available --section system | awk '{print $2}' | grep -E "$DEBIAN_TEMPLATE_REGEX" | sort -V | tail -n1 || true)
  [[ -n "$latest" ]] || die "Unable to determine latest Debian template name."
  run_safe "Downloading template $latest to $TEMPLATE_STORAGE" pveam download "$TEMPLATE_STORAGE" "$latest"
  TEMPLATE="${TEMPLATE_DIR}/${latest}"
  log_ok "Template downloaded: $(basename "$TEMPLATE")"
}

# ========= CONTAINER MANAGEMENT =========
container_exists() {
  pct status "$CTID" >/dev/null 2>&1
}

container_running() {
  pct status "$CTID" 2>/dev/null | grep -q "status: running"
}

wait_for_stop() {
  for _ in $(seq 1 30); do
    if ! container_running; then
      return 0
    fi
    sleep 1
  done
  die "Timed out waiting for container $CTID to stop."
}

stop_lxc() {
  if container_exists && container_running; then
    log_info "Stopping container $CTID"
    pct stop "$CTID" >/dev/null 2>&1 || true
    log_info "Waiting for container $CTID to stop..."
    wait_for_stop
  fi
}

destroy_lxc() {
  if container_exists; then
    log_warn "Existing container $CTID detected and will be recreated."
    stop_lxc
    sleep 2
    log_info "Disabling protection on container $CTID"
    pct set "$CTID" -protection 0 >/dev/null 2>&1 || true
    log_info "Destroying container $CTID"
    pct destroy "$CTID" -force 1
    log_ok "Container $CTID removed"
  fi
}

create_lxc() {
  [[ -n "$TEMPLATE" ]] || die "Template path not set. ensure_template() must be run before create_lxc()."
  log_info "Creating container $CTNAME (CTID $CTID)"
  run_safe "pct create $CTID" pct create "$CTID" "$TEMPLATE" \
    -hostname "$CTNAME" \
    -password "$ROOT_PASS" \
    -storage "$STORAGE" \
    -cores "$CPU" \
    -memory "$MEMORY" \
    -net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    -rootfs "${STORAGE}:8" \
    -features nesting=1 \
    -unprivileged 1 \
    -protection 1

  local conf="/etc/pve/lxc/${CTID}.conf"
  log_info "Applying additional LXC configuration tweaks"
  cat <<EOF >> "$conf"
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
lxc.apparmor.profile: unconfined
lxc.cap.drop:
EOF
  log_ok "Container configuration updated"
}

start_lxc() {
  log_info "Starting container $CTID"
  pct start "$CTID"
  sleep 5
  log_ok "Container $CTID started"
}

# ========= BUILDER SETUP =========
setup_cloudinit_structure() {
  log_info "Preparing Cloud-Init workspace inside container"
  pct exec "$CTID" -- bash -lc "$(cat <<'EOF'
set -e
mkdir -p /root/data /root/output
cat > /root/data/meta-data <<'META'
instance-id: vce
local-hostname: vce
META
cat > /root/data/user-data <<'USER'
#cloud-config
hostname: vce
password: Velocloud123
chpasswd: {expire: False}
ssh_pwauth: True
USER
cat <<'SCRIPT' > /root/build-iso.sh
#!/bin/bash
set -euo pipefail
ISO_DIR=/root/data
OUT_DIR=/root/output
DATE=`date +%Y%m%d-%H%M%S`
OUT_FILE="${OUT_DIR}/cloudinit-${DATE}.iso"
echo '[INFO] Building Cloud-Init ISO...'
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y genisoimage >/dev/null 2>&1
genisoimage -quiet -output "${OUT_FILE}" -volid cidata -joliet -rock "${ISO_DIR}/user-data" "${ISO_DIR}/meta-data"
echo "[OK] ISO created: ${OUT_FILE}"
SCRIPT
chmod +x /root/build-iso.sh
EOF
  )"
  log_ok "Cloud-Init workspace ready"
}

install_dependencies() {
  log_info "Installing container dependencies"
  pct exec "$CTID" -- bash -lc "$(cat <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip curl openssh-client genisoimage sshpass
if ! apt-get install -y python3-flask; then
  pip3 install --no-cache-dir flask
fi
EOF
  )"
  log_ok "Dependencies installed"
}

run_tailscale_login_link() {
  if ! have_tty; then
    log_warn "No TTY available for interactive tailnet login."
    return 1
  fi
  log_info "Running tailscale up --ssh --accept-routes --qr inside container (follow the URL/QR)."
  if pct exec "$CTID" -- bash -lc "set -e; tailscale up --ssh --accept-routes --qr"; then
    log_ok "Tailscale joined via login link."
    return 0
  else
    log_warn "tailscale up --qr failed or was cancelled."
    return 1
  fi
}

setup_tailscale() {
  if [[ "$TAILSCALE_MODE" == "skip" ]]; then
    log_info "Skipping Tailscale installation (mode=skip)."
    return
  fi
  log_info "Installing Tailscale inside container"
  pct exec "$CTID" -- bash -lc "set -e; curl -fsSL https://tailscale.com/install.sh | sh"
  pct exec "$CTID" -- bash -lc "set -e; systemctl enable --now tailscaled"
  if [[ "$TAILSCALE_MODE" == "auth" ]]; then
    if [[ -n "$TAILSCALE_KEY" ]]; then
      log_info "Attempting Tailscale login with provided auth key"
      local quoted_key
      quoted_key=$(printf '%q' "$TAILSCALE_KEY")
      if pct exec "$CTID" -- bash -lc "set -e; tailscale up --auth-key=${quoted_key} --ssh --accept-routes"; then
        log_ok "Tailscale joined tailnet using provided auth key"
      else
        log_warn "tailscale up failed. You may need to provide a fresh auth key manually."
      fi
    else
      log_warn "TAILSCALE_KEY not provided for auth mode."
    fi
  elif [[ "$TAILSCALE_MODE" == "link" ]]; then
    if ! run_tailscale_login_link; then
      log_info "Run: pct exec ${CTID} -- tailscale up --ssh --accept-routes --qr"
    fi
  fi
}

get_tailscale_ip() {
  if [[ "$TAILSCALE_MODE" == "skip" ]]; then
    return 1
  fi
  local ip
  ip=$(pct exec "$CTID" -- bash -lc "if command -v tailscale >/dev/null 2>&1; then tailscale ip -4 2>/dev/null | head -n1; fi" 2>/dev/null || true)
  ip="${ip//$'\r'/}"
  ip="${ip//$'\n'/}"
  if [[ -n "$ip" ]]; then
    printf '%s' "$ip"
    return 0
  fi
  return 1
}

# ========= WEBUI DEPLOYMENT =========
deploy_webui() {
  log_info "Deploying Cloud-Init WebUI for Velocloud ${VELOCLOUD_VERSION}"
  local env_root env_poll env_port env_version env_tail
  env_root=$(shell_quote "$ROOT_PASS")
  env_poll=$(shell_quote "$TAILSCALE_POLL_INTERVAL")
  env_port=$(shell_quote "$PORT")
  env_version=$(shell_quote "$VELOCLOUD_VERSION")
  env_tail="$env_poll"
  pct exec "$CTID" -- bash -c "CLOUDINIT_ROOT_PASS=${env_root} CLOUDINIT_POLL_INTERVAL=${env_poll} WEBUI_PORT=${env_port} VELOCLOUD_VERSION=${env_version} TAILSCALE_POLL_INTERVAL=${env_tail} bash -s" <<'EOF'
set -e
CLOUDINIT_SSH_PASSWORD="$CLOUDINIT_ROOT_PASS"
export CLOUDINIT_ROOT_PASS CLOUDINIT_SSH_PASSWORD CLOUDINIT_POLL_INTERVAL WEBUI_PORT VELOCLOUD_VERSION TAILSCALE_POLL_INTERVAL
cat > /root/webui.py <<'PYCODE'
#!/usr/bin/env python3
from flask import Flask, render_template_string, request, redirect
import subprocess, os, json, threading, base64, time, shlex, re
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

app = Flask(__name__)
DATA_DIR = '/root/data'
OUT_DIR = '/root/output'
BUILD_SCRIPT = '/root/build-iso.sh'
API_KEY_FILE = '/root/.tailscale_api_key'
TEMPLATE_DEFAULTS_FILE = '/root/.template_defaults'
TRUSTED_KEYS_FILE = '/root/.tailscale_trusted_keys'
BUILDER_KEY_PATH = '/root/.ssh/cloudinit_builder'
BUILDER_PUB_PATH = f'{BUILDER_KEY_PATH}.pub'
TAILSCALE_POLL_INTERVAL = int(os.environ.get('TAILSCALE_POLL_INTERVAL', '60'))
SSH_PASSWORD = os.environ.get('CLOUDINIT_SSH_PASSWORD', 'velocloud123')
WEBUI_PORT = int(os.environ.get('WEBUI_PORT', '8080'))
VELOCLOUD_VERSION = os.environ.get('VELOCLOUD_VERSION', '4.5.0')

HTML = """<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<title>Velocloud {{velocloud_version}} Cloud-Init Builder</title>
<style>
body {font-family: Inter,Arial,sans-serif; margin:2em; background:#fafafa; color:#222;}
h2 {color:#c70000;}
.card {background:#fff; border-radius:12px; padding:1.2em; margin-bottom:1.5em; box-shadow:0 2px 5px rgba(0,0,0,0.1);}
button {background:#c70000; color:white; border:none; padding:6px 12px; border-radius:6px; cursor:pointer;}
button:hover {background:#9f0000;}
textarea {width:100%; height:160px; border-radius:8px; border:1px solid #ccc; padding:8px;}
input[type=text], input[type=password]{padding:6px; border-radius:6px; border:1px solid #ccc;}
.form-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:0.75em;}
.field-row{display:flex;flex-direction:column;}
.field-row label{font-weight:600;margin-bottom:0.25em;}
.field-row.checkbox-row{flex-direction:row;align-items:center;gap:0.5em;}
.help-text{font-size:0.85em;color:#555;margin-top:0.75em;}
.device-entry{background:#f9f9f9;border-radius:8px;padding:0.75em;margin-bottom:0.75em;}
.device-meta{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:0.5em;margin-bottom:0.5em;}
.device-status{font-size:0.85em;font-weight:600;}
.badge-ok{color:#0a7a35;}
.badge-missing{color:#b00020;}
.device-form{display:flex;flex-wrap:wrap;gap:0.5em;}
.device-form input{flex:1 1 160px;}
.device-form button{flex:0 0 auto;}
pre {background:#111; color:#0f0; padding:10px; border-radius:8px;}
li {margin:6px 0; background:#f3f3f3; padding:8px; border-radius:6px;}
.btn-secondary {background:#555;}
.btn-secondary:hover {background:#333;}
.status-ok{color:#0a7a35;font-weight:600;}
.status-error{color:#b00020;font-weight:600;}
.status-warn{color:#a15c00;font-weight:600;}
</style>
</head>
<body>
<h2>Velocloud {{velocloud_version}} Cloud-Init Builder</h2>

{% if alert %}
<div class='card'>
<p class='{{alert_class}}'>{{alert}}</p>
</div>
{% endif %}

<div class='card'>
<h3>Tailscale Integration</h3>
<p class='{{status_class}}'>Status: {{status}} {% if last_sync %}(Last sync {{last_sync}}){% endif %}</p>
{% if error %}<p class='status-error'>{{error}}</p>{% endif %}
<form method='POST' action='/tailscale/key'>
<input type='text' name='api_key' placeholder='tskey-api-...' required>
<button type='submit'>{{"Update Key" if api_key_configured else "Save Key"}}</button>
</form>
{% if api_key_configured %}
<form method='POST' action='/tailscale/key/remove' style='margin-top:0.5em;'>
<button type='submit' style='background:#ccc;color:#000;'>Remove Key</button>
</form>
{% endif %}
<h4>Tailnet Devices</h4>
{% if not device_entries %}
<p class='status-warn'>No devices found.</p>
{% endif %}
{% for dev in device_entries %}
<div class='device-entry'>
  <div class='device-meta'>
    <div><b>{{dev.name}}</b> — {{dev.ip or 'No IP'}}</div>
    {% if dev.has_key %}
    <div class='device-status badge-ok'>SSH key stored{% if dev.username %} ({{dev.username}}){% endif %}</div>
    {% else %}
    <div class='device-status badge-missing'>SSH key missing</div>
    {% endif %}
  </div>
  {% if dev.has_key %}
  <form method='POST' action='/tailscale/device/key' class='device-form'>
    <input type='hidden' name='device_name' value='{{dev.name}}'>
    <input type='hidden' name='username' value='{{dev.username or "root"}}'>
    <input type='password' name='password' placeholder='Password' required>
    <button type='submit'>Refresh Key</button>
  </form>
  {% else %}
  <form method='POST' action='/tailscale/device/key' class='device-form'>
    <input type='hidden' name='device_name' value='{{dev.name}}'>
    <input type='text' name='username' placeholder='Username' required>
    <input type='password' name='password' placeholder='Password' required>
    <button type='submit'>Fetch SSH key</button>
  </form>
  {% endif %}
</div>
{% endfor %}
</div>

<div class='card'>
<h3>Meta-Data</h3>
<form method='POST' action='/save/meta'>
<textarea name='content'>{{meta}}</textarea><br>
<button type='submit'>Save</button>
</form>
</div>

<div class='card'>
<h3>Velocloud Activation Template</h3>
<form method='POST' action='/template/apply' class='form-grid'>
<div class='field-row'>
<label for='hostname'>Hostname</label>
<input type='text' id='hostname' name='hostname' value='{{template_defaults.hostname}}' required>
</div>
<div class='field-row'>
<label for='password'>Password</label>
<input type='text' id='password' name='password' value='{{template_defaults.password}}' required>
</div>
<div class='field-row'>
<label for='vco_ip'>VCO Address</label>
<input type='text' id='vco_ip' name='vco_ip' value='{{template_defaults.vco_ip}}' placeholder='10.0.0.5'>
</div>
<div class='field-row'>
<label for='activation_code'>Activation Code</label>
<input type='text' id='activation_code' name='activation_code' value='{{template_defaults.activation_code}}' placeholder='xxxx-xxxx-xxxx-xxxx'>
</div>
<div class='field-row checkbox-row'>
<input type='checkbox' id='vco_ignore_cert_errors' name='vco_ignore_cert_errors' {% if template_defaults.ignore_cert_errors %}checked{% endif %}>
<label for='vco_ignore_cert_errors' style='font-weight:400;margin-bottom:0;'>Ignore VCO certificate errors</label>
</div>
<div class='field-row' style='grid-column:1 / -1;'>
<button type='submit'>Apply Template</button>
</div>
</form>
<p class='help-text'>Applying this template overwrites the User-Data section below. Leave the activation code blank to use the basic Cloud-Init config without Velocloud activation. The activation code input auto-formats to XXXX-XXXX-XXXX-XXXX.</p>
</div>

<div class='card'>
<h3>User-Data</h3>
<form method='POST' action='/save/user'>
<textarea name='content'>{{user}}</textarea><br>
<button type='submit'>Save</button>
</form>
</div>

<div class='card'>
<h3>Build ISO</h3>
<form method='POST' action='/build'><button type='submit'>Build Cloud-Init ISO</button></form>
{% if log %}<pre>{{log}}</pre>{% endif %}
</div>

<div class='card'>
<h3>Generated ISOs</h3>
{% if not files %}
<ul><li>No ISO yet.</li></ul>
{% else %}
<ul>
{% for f in files %}
<li>{{f}}
{% if devices %}
<form method='POST' action='/send/{{f}}' style='display:inline;'>
<select name='target_device' required>
{% for dev in devices %}
<option value='{{dev.name}}|{{dev.ip}}'>{{dev.name}} ({{dev.ip}})</option>
{% endfor %}
</select>
<button type='submit'>Send</button>
</form>
{% else %}
<span class='status-warn'>Add a Tailscale API key to enable delivery.</span>
{% endif %}
<form method='POST' action='/delete/{{f}}' style='display:inline; margin-left:0.5em;'>
<button type='submit' class='btn-secondary'>Delete</button>
</form></li>
{% endfor %}
</ul>
{% endif %}
</div>

</body>
<script>
(function(){
  var input = document.getElementById('activation_code');
  if (!input) return;
  input.addEventListener('input', function(){
    var cleaned = this.value.replace(/[^A-Za-z0-9]/g, '').toUpperCase().slice(0, 16);
    var parts = [];
    for (var i = 0; i < cleaned.length; i += 4) {
      parts.push(cleaned.slice(i, i + 4));
    }
    this.value = parts.join('-');
  });
})();
</script>
</html>"""

tailscale_state={'devices':[],'status':'Not configured','error':None,'last_sync':None,'alert':None,'alert_class':'status-ok'}
lock=threading.Lock()
key_lock=threading.Lock()

def read_api_key():
    return open(API_KEY_FILE).read().strip() if os.path.exists(API_KEY_FILE) else ''
def write_api_key(key):
    with open(API_KEY_FILE,'w') as f:
        f.write(key.strip())
    os.chmod(API_KEY_FILE,0o600)
def clear_api_key():
    if os.path.exists(API_KEY_FILE):
        os.remove(API_KEY_FILE)

def ensure_builder_key():
    if os.path.exists(BUILDER_KEY_PATH) and os.path.exists(BUILDER_PUB_PATH):
        return
    os.makedirs(os.path.dirname(BUILDER_KEY_PATH), exist_ok=True)
    subprocess.run(['ssh-keygen', '-t', 'ed25519', '-N', '', '-f', BUILDER_KEY_PATH], check=True)

def load_trusted_keys():
    with key_lock:
        if not os.path.exists(TRUSTED_KEYS_FILE):
            return {}
        try:
            with open(TRUSTED_KEYS_FILE) as fh:
                data=json.load(fh)
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
        return {}

def save_trusted_keys(data):
    with key_lock:
        with open(TRUSTED_KEYS_FILE, 'w') as fh:
            json.dump(data, fh)
        os.chmod(TRUSTED_KEYS_FILE, 0o600)

def load_template_defaults():
    defaults = {
        'hostname': 'vce',
        'password': 'Velocloud123',
        'vco_ip': '',
        'activation_code': '',
        'ignore_cert_errors': True,
    }
    if not os.path.exists(TEMPLATE_DEFAULTS_FILE):
        return defaults
    try:
        with open(TEMPLATE_DEFAULTS_FILE) as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            defaults.update({
                'hostname': data.get('hostname', defaults['hostname']),
                'password': data.get('password', defaults['password']),
                'vco_ip': data.get('vco_ip', defaults['vco_ip']),
                'activation_code': data.get('activation_code', defaults['activation_code']),
                'ignore_cert_errors': bool(data.get('ignore_cert_errors', defaults['ignore_cert_errors'])),
            })
    except Exception:
        pass
    return defaults

def save_template_defaults(values):
    try:
        with open(TEMPLATE_DEFAULTS_FILE, 'w') as fh:
            json.dump(values, fh)
        os.chmod(TEMPLATE_DEFAULTS_FILE, 0o600)
    except OSError:
        pass

def fetch_devices(key):
    req=Request('https://api.tailscale.com/api/v2/tailnet/-/devices')
    auth=base64.b64encode(f'{key}:'.encode()).decode()
    req.add_header('Authorization',f'Basic {auth}')
    with urlopen(req,timeout=15) as resp:
        data=json.loads(resp.read().decode())
    devices=[]
    for dev in data.get('devices',[]):
        for ip in dev.get('addresses',[]):
            if ':' not in ip:
                devices.append({'name':dev.get('displayName') or dev.get('hostname') or 'Unknown','ip':ip})
    return devices

def poll():
    while True:
        key=read_api_key()
        if not key:
            update([], 'Not configured', None)
        else:
            try:
                devices=fetch_devices(key)
                update(devices, 'Connected', None)
            except (URLError, HTTPError, TimeoutError, json.JSONDecodeError) as exc:
                update([], 'Error', str(exc))
            except Exception as exc:
                update([], 'Error', str(exc))
        time.sleep(TAILSCALE_POLL_INTERVAL)

def update(devices, status, error):
    with lock:
        tailscale_state.update({
            'devices': devices,
            'status': status,
            'error': error,
            'last_sync': time.strftime('%H:%M:%S')
        })

def set_alert(message, category='status-ok'):
    with lock:
        tailscale_state['alert'] = message
        tailscale_state['alert_class'] = category

def get_state():
    with lock:
        return dict(tailscale_state)

threading.Thread(target=poll, daemon=True).start()

@app.route('/')
def index():
    state=get_state()
    meta=open(f'{DATA_DIR}/meta-data').read()
    user=open(f'{DATA_DIR}/user-data').read()
    files=sorted(f for f in os.listdir(OUT_DIR) if f.endswith('.iso'))
    defaults=load_template_defaults()
    trusted=load_trusted_keys()
    device_entries=[]
    for dev in sorted(state['devices'], key=lambda d: d.get('name','').lower()):
        info=trusted.get(dev['name'], {})
        device_entries.append({
            'name': dev['name'],
            'ip': dev.get('ip',''),
            'has_key': bool(info),
            'username': info.get('username','')
        })
    if state['status']=='Connected':
        status_class='status-ok'
    elif state['status']=='Not configured':
        status_class='status-warn'
    else:
        status_class='status-error'
    return render_template_string(HTML,
        devices=state['devices'],
        status=state['status'],
        status_class=status_class,
        error=state['error'],
        last_sync=state['last_sync'],
        api_key_configured=bool(read_api_key()),
        meta=meta,
        user=user,
        log='',
        files=files,
        alert=state.get('alert'),
        alert_class=state.get('alert_class','status-ok'),
        velocloud_version=VELOCLOUD_VERSION,
        template_defaults=defaults,
        device_entries=device_entries)

@app.post('/save/<kind>')
def save(kind):
    filename='meta-data' if kind=='meta' else 'user-data'
    open(f'{DATA_DIR}/{filename}','w').write(request.form['content'])
    return redirect('/')

@app.post('/template/apply')
def apply_template():
    defaults=load_template_defaults()
    hostname_input=request.form.get('hostname','').strip()
    password_input=request.form.get('password','')
    vco_ip_input=request.form.get('vco_ip','').strip()
    activation_code_input=request.form.get('activation_code','').strip()
    ignore=request.form.get('vco_ignore_cert_errors') == 'on'

    if not hostname_input:
        set_alert('Hostname is required.', 'status-error')
        return redirect('/')
    if not password_input:
        set_alert('Password is required.', 'status-error')
        return redirect('/')

    raw_code=re.sub(r'[^A-Za-z0-9]', '', activation_code_input).upper()
    formatted_code=''
    if raw_code:
        if len(raw_code) < 16:
            set_alert('Activation code must be 16 characters (format XXXX-XXXX-XXXX-XXXX).', 'status-error')
            return redirect('/')
        raw_code=raw_code[:16]
        parts=[raw_code[i:i+4] for i in range(0, len(raw_code), 4)]
        formatted_code='-'.join(filter(None, parts))
    defaults['hostname']=hostname_input
    defaults['password']=password_input
    defaults['vco_ip']=vco_ip_input
    defaults['activation_code']=formatted_code
    defaults['ignore_cert_errors']=ignore
    save_template_defaults(defaults)

    if formatted_code:
        if not vco_ip_input:
            set_alert('VCO address is required when providing an activation code.', 'status-error')
            return redirect('/')
        user_data = (
            "#cloud-config\n"
            f"hostname: {json.dumps(hostname_input)}\n"
            f"password: {json.dumps(password_input)}\n"
            "chpasswd: {expire: False}\n"
            "ssh_pwauth: True\n"
            "velocloud:\n"
            "  vce:\n"
            f"    vco: {json.dumps(vco_ip_input)}\n"
            f"    activation_code: {json.dumps(formatted_code)}\n"
            f"    vco_ignore_cert_errors: {'true' if ignore else 'false'}\n"
        )
        alert_message='Applied Velocloud activation template to User-Data.'
    else:
        user_data = (
            "#cloud-config\n"
            f"hostname: {json.dumps(hostname_input)}\n"
            f"password: {json.dumps(password_input)}\n"
            "chpasswd: {expire: False}\n"
            "ssh_pwauth: True\n"
        )
        alert_message='Applied basic Cloud-Init config without activation code.'
    try:
        with open(f'{DATA_DIR}/user-data','w') as fh:
            fh.write(user_data)
        meta_content=f'instance-id: {hostname_input}\nlocal-hostname: {hostname_input}\n'
        with open(f'{DATA_DIR}/meta-data','w') as meta_fh:
            meta_fh.write(meta_content)
        set_alert(alert_message, 'status-ok')
    except OSError as exc:
        set_alert(f'Failed to apply template: {exc}', 'status-error')
    return redirect('/')

@app.post('/build')
def build():
    result=subprocess.run(['/bin/bash', BUILD_SCRIPT], capture_output=True, text=True)
    meta=open(f'{DATA_DIR}/meta-data').read()
    user=open(f'{DATA_DIR}/user-data').read()
    files=sorted(f for f in os.listdir(OUT_DIR) if f.endswith('.iso'))
    defaults=load_template_defaults()
    log_output=result.stdout.strip() or result.stderr.strip()
    if result.returncode == 0:
        set_alert("Cloud-Init ISO build completed successfully.", 'status-ok')
    else:
        set_alert("Cloud-Init ISO build encountered an error. Check logs below.", 'status-error')
    state=get_state()
    trusted=load_trusted_keys()
    device_entries=[]
    for dev in sorted(state['devices'], key=lambda d: d.get('name','').lower()):
        info=trusted.get(dev['name'], {})
        device_entries.append({
            'name': dev['name'],
            'ip': dev.get('ip',''),
            'has_key': bool(info),
            'username': info.get('username','')
        })
    if state['status']=='Connected':
        status_class='status-ok'
    elif state['status']=='Not configured':
        status_class='status-warn'
    else:
        status_class='status-error'
    return render_template_string(HTML,
        devices=state['devices'],
        status=state['status'],
        status_class=status_class,
        error=state['error'],
        last_sync=state['last_sync'],
        api_key_configured=bool(read_api_key()),
        meta=meta,
        user=user,
        log=log_output,
        files=files,
        alert=state.get('alert'),
        alert_class=state.get('alert_class','status-ok'),
        velocloud_version=VELOCLOUD_VERSION,
        template_defaults=defaults,
        device_entries=device_entries)

@app.post('/tailscale/key')
def setkey():
    write_api_key(request.form['api_key'])
    return redirect('/')

@app.post('/tailscale/key/remove')
def removekey():
    clear_api_key()
    return redirect('/')

@app.post('/tailscale/device/key')
def fetch_device_key():
    device_name=request.form.get('device_name','').strip()
    username=request.form.get('username','').strip()
    password=request.form.get('password','')
    if not device_name or not username or not password:
        set_alert('Device, username, and password are required to fetch SSH key.', 'status-error')
        return redirect('/')
    ip=request.form.get('device_ip','').strip()
    state=get_state()
    device_map={dev['name']: dev for dev in state['devices']}
    device=device_map.get(device_name)
    if device and not ip:
        ip=device.get('ip','').strip()
    if not ip:
        set_alert(f'Unable to determine IP for {device_name}.', 'status-error')
        return redirect('/')
    try:
        ensure_builder_key()
    except subprocess.CalledProcessError as exc:
        set_alert(f'Failed to ensure local SSH key: {exc}', 'status-error')
        return redirect('/')
    try:
        with open(BUILDER_PUB_PATH) as fh:
            public_key=fh.read().strip()
    except OSError as exc:
        set_alert(f'Unable to read builder public key: {exc}', 'status-error')
        return redirect('/')
    remote_cmd=(
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
        "touch ~/.ssh/authorized_keys && "
        f"(grep -qxF {shlex.quote(public_key)} ~/.ssh/authorized_keys || printf '%s\\n' {shlex.quote(public_key)} >> ~/.ssh/authorized_keys) && "
        "chmod 600 ~/.ssh/authorized_keys"
    )
    result=subprocess.run([
        'sshpass','-p', password,
        'ssh','-o','StrictHostKeyChecking=no',
        '-o','PreferredAuthentications=password',
        f'{username}@{ip}',
        remote_cmd
    ], capture_output=True, text=True)
    if result.returncode != 0:
        error_msg=result.stderr or result.stdout or 'Unknown error'
        set_alert(f'Failed to install SSH key on {device_name or ip}: {error_msg.strip()}', 'status-error')
        return redirect('/')
    verify=subprocess.run([
        'ssh','-i', BUILDER_KEY_PATH,
        '-o','StrictHostKeyChecking=no',
        '-o','IdentitiesOnly=yes',
        '-o','BatchMode=yes',
        f'{username}@{ip}',
        'exit 0'
    ], capture_output=True, text=True)
    trusted=load_trusted_keys()
    trusted[device_name]={
        'username': username,
        'ip': ip,
        'updated': time.time()
    }
    save_trusted_keys(trusted)
    if verify.returncode == 0:
        set_alert(f'SSH key stored for {device_name or ip}.', 'status-ok')
    else:
        error_msg=verify.stderr or verify.stdout or 'Unknown error'
        set_alert(f'SSH key installed but verification failed for {device_name or ip}: {error_msg.strip()}', 'status-warn')
    return redirect('/')

@app.post('/send/<filename>')
def send(filename):
    token=request.form['target_device'].strip()
    if '|' in token:
        device_name, ip = token.split('|', 1)
    else:
        device_name, ip = token, ''
    device_name=device_name.strip()
    ip=ip.strip()
    path=f'{OUT_DIR}/{filename}'
    if '/' in filename or '..' in filename:
        set_alert('Invalid ISO name.', 'status-error')
        return redirect('/')
    if not os.path.isfile(path):
        set_alert(f'ISO {filename} not found.', 'status-error')
        return redirect('/')
    state=get_state()
    device_map={dev['name']: dev for dev in state['devices']}
    device=device_map.get(device_name)
    if device and not ip:
        ip=device.get('ip','').strip()
    trusted=load_trusted_keys()
    info=trusted.get(device_name)
    if info and not ip:
        ip=info.get('ip','').strip()
    if not info:
        set_alert(f'SSH key not configured for {device_name or ip}. Fetch the key first.', 'status-error')
        return redirect('/')
    username=info.get('username') or 'root'
    if not ip:
        set_alert(f'Unable to determine IP for {device_name or username}.', 'status-error')
        return redirect('/')
    ensure_builder_key()
    cmd=[
        'scp',
        '-i', BUILDER_KEY_PATH,
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'IdentitiesOnly=yes',
        path, f"{username}@{ip}:/var/lib/vz/template/iso/"
    ]
    result=subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        info['ip']=ip
        trusted[device_name]=info
        save_trusted_keys(trusted)
        set_alert(f'ISO {filename} sent to {device_name or ip}.', 'status-ok')
    else:
        error_msg = result.stderr or result.stdout or 'Unknown error'
        set_alert(f'Failed to send {filename} to {device_name or ip}: {error_msg.strip()}', 'status-error')
    return redirect('/')

@app.post('/delete/<filename>')
def delete(filename):
    if '/' in filename or '..' in filename:
        set_alert('Invalid ISO name.', 'status-error')
        return redirect('/')
    path=f'{OUT_DIR}/{filename}'
    if not os.path.isfile(path):
        set_alert(f'ISO {filename} not found.', 'status-error')
        return redirect('/')
    try:
        os.remove(path)
        set_alert(f'Removed ISO {filename}.', 'status-warn')
    except OSError as exc:
        set_alert(f'Failed to remove {filename}: {exc}', 'status-error')
    return redirect('/')

if __name__=='__main__':
    app.run(host='0.0.0.0', port=WEBUI_PORT)
PYCODE

python3 - <<'PY'
import os, json
env_path = '/root/webui.env'
root_pass = os.environ.get('CLOUDINIT_ROOT_PASS', 'velocloud123')
poll = os.environ.get('CLOUDINIT_POLL_INTERVAL', '60')
port = os.environ.get('WEBUI_PORT', '8080')
version = os.environ.get('VELOCLOUD_VERSION', '4.5.0')
escaped_pass = json.dumps(root_pass)[1:-1]
with open(env_path, 'w', encoding='utf-8') as fh:
    fh.write(f'CLOUDINIT_SSH_PASSWORD="{escaped_pass}"\n')
    fh.write(f'TAILSCALE_POLL_INTERVAL="{poll}"\n')
    fh.write(f'WEBUI_PORT="{port}"\n')
    fh.write(f'VELOCLOUD_VERSION="{version}"\n')
PY

cat > /etc/systemd/system/webui.service <<UNIT
[Unit]
Description=Cloud-Init Builder WebUI (Velocloud ${VELOCLOUD_VERSION})
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/root/webui.env
ExecStart=/usr/bin/python3 /root/webui.py
WorkingDirectory=/root
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

chmod +x /root/webui.py
systemctl daemon-reload
systemctl enable webui --now
EOF
  log_ok "WebUI deployed and service started"
}

# ========= MAIN EXECUTION =========
main() {
  validate_environment
  validate_parameters
  validate_storage
  log_info "Targeting Velocloud version ${VELOCLOUD_VERSION}"
  ensure_template
  destroy_lxc
  create_lxc
  start_lxc
  setup_cloudinit_structure
  install_dependencies
  setup_tailscale
  deploy_webui
  log_ok "Cloud-Init Builder provisioning finished"
  printf '[%s] Cloud-Init Builder for Velocloud %s setup complete!\n' $'\u2713' "$VELOCLOUD_VERSION"
  local tailscale_ip=""
  if tailscale_ip=$(get_tailscale_ip); then
    echo "Access WebUI: http://${tailscale_ip}:${PORT}"
  else
    echo "Access WebUI: http://<TAILSCALE_IP>:${PORT} (tailscale IP not yet detected)"
  fi
}

# ========= ENTRYPOINT =========
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ctid)
        [[ -n "${2:-}" ]] || die "--ctid requires a value."
        CTID="$2"
        shift 2
        ;;
      --ctname)
        [[ -n "${2:-}" ]] || die "--ctname requires a value."
        CTNAME="$2"
        shift 2
        ;;
      --storage)
        [[ -n "${2:-}" ]] || die "--storage requires a value."
        STORAGE="$2"
        shift 2
        ;;
      --template-storage)
        [[ -n "${2:-}" ]] || die "--template-storage requires a value."
        TEMPLATE_STORAGE="$2"
        shift 2
        ;;
      --bridge)
        [[ -n "${2:-}" ]] || die "--bridge requires a value."
        BRIDGE="$2"
        shift 2
        ;;
      --cpu)
        [[ -n "${2:-}" ]] || die "--cpu requires a value."
        CPU="$2"
        shift 2
        ;;
      --memory)
        [[ -n "${2:-}" ]] || die "--memory requires a value."
        MEMORY="$2"
        shift 2
        ;;
      --root-pass)
        [[ -n "${2:-}" ]] || die "--root-pass requires a value."
        ROOT_PASS="$2"
        shift 2
        ;;
      --port)
        [[ -n "${2:-}" ]] || die "--port requires a value."
        PORT="$2"
        shift 2
        ;;
      --auth-key|--tailscale-auth-key)
        [[ -n "${2:-}" ]] || die "--auth-key requires a value."
        TAILSCALE_KEY="$2"
        shift 2
        ;;
      --tailscale-mode)
        [[ -n "${2:-}" ]] || die "--tailscale-mode requires a value."
        TAILSCALE_MODE="$2"
        shift 2
        ;;
      --velocloud-version)
        [[ -n "${2:-}" ]] || die "--velocloud-version requires a value."
        VELOCLOUD_VERSION="$2"
        shift 2
        ;;
      --prompt)
        PROMPT_MODE="on"
        shift
        ;;
      --no-prompt|--non-interactive)
        PROMPT_MODE="off"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

parse_args "$@"
customize_configuration
main
