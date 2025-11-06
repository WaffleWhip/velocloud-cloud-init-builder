# ============================================================
# Module : tailscale.sh
# Purpose: Automate Tailscale installation and authentication
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================
#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Function : setup_tailscale
# Purpose  : Install and optionally authenticate Tailscale inside the container
# Params   : None
# Behavior : Installs via official script, enables service, and joins tailnet
# Example  : setup_tailscale
# -----------------------------------------------------------------------------
setup_tailscale() {
  log_info "Installing Tailscale inside container"
  pct exec "$CTID" -- bash -lc "set -e; curl -fsSL https://tailscale.com/install.sh | sh"
  pct exec "$CTID" -- bash -lc "set -e; systemctl enable --now tailscaled"
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
    log_warn "TAILSCALE_KEY not provided. Skipping automatic tailscale up."
  fi
}
