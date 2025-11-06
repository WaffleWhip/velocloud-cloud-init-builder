# ============================================================
# Module : cloudinit.sh
# Purpose: Prepare cloud-init assets and container dependencies
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================
#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Function : setup_cloudinit_structure
# Purpose  : Install the base cloud-init workspace and helper scripts in the CT
# Params   : None
# Behavior : Creates metadata/user-data files and the ISO build helper script
# Example  : setup_cloudinit_structure
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : install_dependencies
# Purpose  : Install required packages inside the container for builder tooling
# Params   : None
# Behavior : Installs Python, Flask, SSH utilities, and support packages
# Example  : install_dependencies
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : generate_cloudinit
# Purpose  : Execute the combined steps to configure cloud-init assets
# Params   : None
# Behavior : Prepares workspace and installs dependencies sequentially
# Example  : generate_cloudinit
# -----------------------------------------------------------------------------
generate_cloudinit() {
  setup_cloudinit_structure
  install_dependencies
}
