<<<<<<< HEAD
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

## Single-File Installer

For quick deployment you can expose only the `cloud-init-builder-velocloud.sh` script via a public Git remote and have a Proxmox host fetch it directly with `curl`.

1. Push this repository (or at least the installer script) to `https://github.com/WaffleWhip/velocloud-cloud-init-builder`.
2. On the Proxmox shell run:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/WaffleWhip/velocloud-cloud-init-builder/master/cloud-init-builder-velocloud.sh | sudo bash
   ```

3. Export any overrides before the `curl` if you want to bypass prompts or customize defaults, e.g.:

   ```bash
   CTID=2100 TAILSCALE_KEY=tskey-auth-XXXXXXXX PROMPT_MODE=off \
     curl -fsSL … | sudo bash
   ```

| Env var | Purpose |
|---------|---------|
| `CTID`, `CTNAME`, `STORAGE`, `TEMPLATE_STORAGE`, `BRIDGE` | LXC placement and networking |
| `CPU`, `MEMORY`, `ROOT_PASS`, `PORT` | Builder resource and WebUI credentials |
| `TAILSCALE_KEY`, `VELOCLOUD_VERSION` | Networking/auth and Velocloud release |

Read the script from the GitHub UI or download it manually before executing it if you need to verify it meets your policies.

## Verification

Once the container finishes provisioning, visit `http://<TAILSCALE_IP>:<PORT>` (the script will log the address) to access the WebUI and continue building cloud-init ISOs.
=======
# Velocloud Cloud-Init Builder

This repository only needs to expose `cloud-init-builder-velocloud.sh` on a public Git remote so Proxmox CLI nodes can fetch-run it via `curl`.

## Publish the repo
1. Initialize Git (if you haven't already):
   ```bash
   git init
   git add cloud-init-builder-velocloud.sh
   git commit -m "Add Velocloud cloud-init builder script"
   git branch -M main
   git remote add origin https://github.com/<your-user>/velocloud-cloud-init-builder.git
   git push -u origin main
   ```
2. Every time you update the script, commit and push the change so `curl` can grab the latest.

## Run on Proxmox CLI
Use the raw view of the script so you can pipe it into `sudo bash`. Example:
```bash
curl -fsSL https://raw.githubusercontent.com/<your-user>/velocloud-cloud-init-builder/main/cloud-init-builder-velocloud.sh | sudo bash
```
The script respects the following environment variables if you want to customize defaults without prompts (set them before running, e.g. `CTID=2100 TAILSCALE_KEY=tskey curl …`):

| Variable | Purpose |
|----------|---------|
| `CTID` | Container ID (default 2000) |
| `CTNAME` | Container hostname (default `velocloud-builder`) |
| `STORAGE`/`TEMPLATE_STORAGE` | Storage pools for container disk and template |
| `BRIDGE` | Network bridge for the container |
| `CPU`, `MEMORY` | Resources for the builder |
| `ROOT_PASS`, `PORT`, `TAILSCALE_KEY`, `VELOCLOUD_VERSION` | Credentials and service settings |

Set `PROMPT_MODE=off` if you want a fully non-interactive run.

## Verify before running
Read through the script directly from GitHub (via the web UI) or download it manually (`curl -fsSL … -o cloud-init-builder-velocloud.sh`) if you need to inspect it before executing.

## Next steps
Once the container is created and the WebUI starts, connect via Tailscale and open `http://<TAILSCALE_IP>:${PORT}` to finish configuration.
>>>>>>> 3e7aafa (Add README and installer script)
