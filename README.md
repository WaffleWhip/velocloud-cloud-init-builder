# Velocloud Single-File Builder

This repo ships a single installer script that builds a Velocloud-ready Proxmox LXC, complete with cloud-init tooling, the Flask management WebUI, and optional tunneling via Tailscale.

## Quick install on Proxmox

Run the installer directly from GitHub on any Proxmox host:

```bash
curl -fsSL https://raw.githubusercontent.com/WaffleWhip/velocloud-cloud-init-builder/master/cloud-init-builder-velocloud.sh | sudo bash
```

### Environment guards

Export these before the `curl … | sudo bash` line to skip prompts or override defaults:

| Variable | Purpose |
|----------|---------|
| `CTID` | Proxmox container ID (default `2000`) |
| `CTNAME` | Container hostname (default `velocloud-builder`) |
| `STORAGE`, `TEMPLATE_STORAGE` | Disk/template storage pools |
| `BRIDGE` | Network bridge (default `vmbr0`) |
| `CPU`, `MEMORY` | Container resources |
| `ROOT_PASS`, `PORT` | Root password and WebUI port |
| `TAILSCALE_KEY`, `VELOCLOUD_VERSION` | Tailscale auth key and Velocloud release |
| `PROMPT_MODE=off` | Run non-interactively |

The installer echoes the Tailscale IP + WebUI port when it finishes; visit `http://<TAILSCALE_IP>:<PORT>` to continue building cloud-init payloads.

## Networking

Proof‑of‑concept deployments in this repository have been performed with **Tailscale** so you can quickly expose the WebUI and builder container across hosts without configuring complex VPNs. If you prefer a standalone VPN, WireGuard is another compatible option since the script only relies on Linux networking primitives.

## Velocloud compatibility

The installer has been tested with **Velocloud 4.5.0** only. Other versions may work, but incompatibilities are possible because newer packages or CLI changes were not validated yet.

## Verification

Download the script manually (`curl -fsSL … -o cloud-init-builder-velocloud.sh`) if you must review it before execution.

## License

MIT License (see `LICENSE`).
