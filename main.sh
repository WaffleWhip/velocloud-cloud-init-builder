#!/usr/bin/env bash
# ============================================================
# Entry point orchestrating the Velocloud Cloud-Init Builder
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config/defaults.sh"

# Source all library modules
for lib in "${SCRIPT_DIR}"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "$lib"
done

# -----------------------------------------------------------------------------
# Function : parse_args
# Purpose  : Process command-line arguments to override default configuration
# Params   : $@ - CLI arguments passed to the script
# Behavior : Updates global variables or exits after displaying usage help
# Example  : parse_args "$@"
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Function : main
# Purpose  : Execute the full provisioning workflow in ordered stages
# Params   : $@ - retained for future compatibility (unused)
# Behavior : Calls all modularised routines to build the environment
# Example  : main "$@"
# -----------------------------------------------------------------------------
main() {
  init_environment
  validate_prerequisites
  create_lxc
  generate_cloudinit
  setup_tailscale
  install_webui
  finalize_build
}

parse_args "$@"
main "$@"
