# Cloud-Init Builder for Velocloud

Automate the provisioning of a Velocloud-ready Proxmox LXC that bundles cloud-init ISO generation, a management WebUI, and optional Tailscale connectivity. This project modularises the original monolithic installer into reusable shell libraries suitable for production automation.

## Architecture Overview

```mermaid
flowchart TD
  A[main.sh] --> B[core.sh]
  A --> C[proxmox.sh]
  A --> D[cloudinit.sh]
  A --> E[tailscale.sh]
  A --> F[webui.sh]
  A --> G[cleanup.sh]
  B -->|Prompts & Logging| A
  C -->|pct create/start| LXC[(Proxmox Host)]
  D -->|bootstrap| LXC
  E -->|tailscale up| LXC
  F -->|Flask WebUI| LXC
  G -->|Status Output| Operator
```

## Features

- Automated detection and download of the latest Debian LXC template.
- Proxmox LXC lifecycle orchestration with safe recreation semantics.
- Cloud-init workspace bootstrap and ISO builder helper inside the container.
- Flask-based Velocloud Builder WebUI deployed as a managed systemd service.
- Optional Tailscale installation and authenticated tailnet join sequence.
- Interactive or non-interactive configuration via prompts, flags, or env vars.

## Requirements

- Proxmox VE 8 or 9 (root access on the host node).
- Internet connectivity to reach Proxmox template repos, Tailscale, and Python packages.
- Bash 5.x with standard GNU userland (tested on Proxmox host shell).
- Optional: Tailscale auth key (`tskey-auth-*`) for automatic join and API key for WebUI device sync.

## Usage

1. Clone or copy this repository onto your Proxmox host.
2. Adjust environment variables or call with flags to suit your environment:

   ```bash
   cd velocloud-cloud-init-builder
   CTID=2025 STORAGE=fast-lvm ./main.sh --port 9090 --prompt
   ```

3. Follow the interactive prompts to confirm container settings or supply overrides.
4. Wait for the workflow to finish provisioning. A success message provides the WebUI URL.
5. Access the Velocloud Builder WebUI via Tailscale IP (if joined) or the container's LAN address:

   ```
   http://<TAILSCALE_IP>:<PORT>
   ```

6. Use the WebUI to craft cloud-init payloads, build ISOs, push SSH keys, and manage device templates.

### Running Non-Interactively

Supply all required values via CLI or environment variables to skip prompts:

```bash
PROMPT_MODE=off ./main.sh \
  --ctid 2100 \
  --ctname velocloud-prod \
  --storage local-lvm \
  --template-storage local \
  --bridge vmbr1 \
  --cpu 4 \
  --memory 4096 \
  --port 8443 \
  --root-pass 'Velocloud!23' \
  --velocloud-version 4.6.1 \
  --auth-key tskey-auth-XXXXXXXXXXXXXXXXXXXXXX
```

## Directory Structure

```
velocloud-cloud-init-builder/
|-- main.sh
|-- config/
|   `-- defaults.sh
|-- lib/
|   |-- cleanup.sh
|   |-- cloudinit.sh
|   |-- core.sh
|   |-- proxmox.sh
|   |-- tailscale.sh
|   `-- webui.sh
|-- README.md
`-- LICENSE
```

## Troubleshooting

- **Template download fails**: Ensure the Proxmox host has outbound access to `pveam`. Re-run with `pveam update` manually.
- **Tailscale join issues**: Regenerate a reusable auth key in the Tailscale admin console. Check `pct exec <CTID> -- systemctl status tailscaled`.
- **WebUI not reachable**: Verify the service with `journalctl -u webui -n 50`. Confirm the container network has DHCP/IP connectivity.
- **Build script errors**: Inspect `/root/.build.log` and `/root/webui.log` inside the container via `pct enter <CTID>`.
- **Interactive prompts missing**: Run with `--prompt` to force TTY interaction or ensure the session provides a terminal (e.g., SSH not via cron).

## Author & License

Maintained by Wahyu Athief (Waf). Released under the MIT License. See [LICENSE](LICENSE) for full terms.
