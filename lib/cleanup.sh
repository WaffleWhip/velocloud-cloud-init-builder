# ============================================================
# Module : cleanup.sh
# Purpose: Handle final status reporting and post-build messaging
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================
#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Function : finalize_build
# Purpose  : Present completion messages and next-step guidance
# Params   : None
# Behavior : Mirrors original script's completion output for the operator
# Example  : finalize_build
# -----------------------------------------------------------------------------
finalize_build() {
  log_ok "Cloud-Init Builder provisioning finished"
  printf '[%s] Cloud-Init Builder for Velocloud %s setup complete!\n' $'\u2713' "$VELOCLOUD_VERSION"
  echo "Access WebUI: http://<TAILSCALE_IP>:${PORT}"
}
