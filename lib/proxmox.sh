# ============================================================
# Module : proxmox.sh
# Purpose: Manage LXC lifecycle and Proxmox validations
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================
#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Function : validate_environment
# Purpose  : Verify host prerequisites and required commands
# Params   : None
# Behavior : Ensures script runs as root and Proxmox utilities are available
# Example  : validate_environment
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : validate_parameters
# Purpose  : Check high-level configuration before provisioning
# Params   : None
# Behavior : Validates numeric ranges and required variable values
# Example  : validate_parameters
# -----------------------------------------------------------------------------
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
  [[ -n "$VELOCLOUD_VERSION" ]] || die "Velocloud version cannot be empty."
}

# -----------------------------------------------------------------------------
# Function : validate_storage
# Purpose  : Ensure Proxmox storage pools referenced by the build exist
# Params   : None
# Behavior : Confirms storage identifiers via pvesm status output
# Example  : validate_storage
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : ensure_template
# Purpose  : Locate or download the Debian template required for the LXC
# Params   : None
# Behavior : Reuses existing cached template or triggers a download via pveam
# Example  : ensure_template
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : container_exists
# Purpose  : Determine if a container with the target CTID already exists
# Params   : None
# Behavior : Checks pct status output and returns success on presence
# Example  : if container_exists; then ...
# -----------------------------------------------------------------------------
container_exists() {
  pct status "$CTID" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Function : container_running
# Purpose  : Test whether the target container is currently running
# Params   : None
# Behavior : Inspects pct status output for a running state
# Example  : if container_running; then stop_lxc; fi
# -----------------------------------------------------------------------------
container_running() {
  pct status "$CTID" 2>/dev/null | grep -q "status: running"
}

# -----------------------------------------------------------------------------
# Function : wait_for_stop
# Purpose  : Poll container status until it stops or timeout occurs
# Params   : None
# Behavior : Waits up to ~30 seconds before aborting the workflow
# Example  : wait_for_stop
# -----------------------------------------------------------------------------
wait_for_stop() {
  for _ in $(seq 1 30); do
    if ! container_running; then
      return 0
    fi
    sleep 1
  done
  die "Timed out waiting for container $CTID to stop."
}

# -----------------------------------------------------------------------------
# Function : stop_lxc
# Purpose  : Gracefully stop the container when it is running
# Params   : None
# Behavior : Issues pct stop followed by a wait for shutdown
# Example  : stop_lxc
# -----------------------------------------------------------------------------
stop_lxc() {
  if container_exists && container_running; then
    log_info "Stopping container $CTID"
    pct stop "$CTID" >/dev/null 2>&1 || true
    log_info "Waiting for container $CTID to stop..."
    wait_for_stop
  fi
}

# -----------------------------------------------------------------------------
# Function : destroy_lxc
# Purpose  : Remove an existing container so a clean instance can be created
# Params   : None
# Behavior : Disables protection, destroys the CT, and reports status
# Example  : destroy_lxc
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : proxmox_create_container
# Purpose  : Instantiate the LXC container from the prepared template
# Params   : None
# Behavior : Invokes pct create and appends required configuration lines
# Example  : proxmox_create_container
# -----------------------------------------------------------------------------
proxmox_create_container() {
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

# -----------------------------------------------------------------------------
# Function : start_lxc
# Purpose  : Boot the freshly created container to make it available for setup
# Params   : None
# Behavior : Calls pct start and waits briefly to ensure services settle
# Example  : start_lxc
# -----------------------------------------------------------------------------
start_lxc() {
  log_info "Starting container $CTID"
  pct start "$CTID"
  sleep 5
  log_ok "Container $CTID started"
}

# -----------------------------------------------------------------------------
# Function : create_lxc
# Purpose  : High-level wrapper combining destroy, create, and start steps
# Params   : None
# Behavior : Recreates the container to guarantee a clean environment
# Example  : create_lxc
# -----------------------------------------------------------------------------
create_lxc() {
  destroy_lxc
  proxmox_create_container
  start_lxc
}

# -----------------------------------------------------------------------------
# Function : validate_prerequisites
# Purpose  : Run all validation routines required before provisioning
# Params   : None
# Behavior : Validates host, params, storage, and template availability
# Example  : validate_prerequisites
# -----------------------------------------------------------------------------
validate_prerequisites() {
  validate_environment
  validate_parameters
  validate_storage
  log_info "Targeting Velocloud version ${VELOCLOUD_VERSION}"
  ensure_template
}
