# Velocloud Single-File Builder

This repo ships a single installer script that builds a Velocloud-ready Proxmox LXC, complete with cloud-init tooling, the Flask management WebUI, and optional tunneling via Tailscale.

## Quick install on Proxmox

Run the installer directly from GitHub on any Proxmox host (run as root or with PrivSep disabled):

```bash
curl -fsSL https://raw.githubusercontent.com/WaffleWhip/velocloud-cloud-init-builder/master/cloud-init-builder-velocloud.sh | bash
```

## Environment guards

Export these before the `curl -fsSL ... | bash` line to skip prompts or override defaults:

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

The installer logs the Tailscale IP and WebUI port when it finishes; visit `http://<TAILSCALE_IP>:<PORT>` to continue building cloud-init payloads.

## Tailscale options

Choose how the builder joins your tailnet:

1. **Use an auth key** - export `TAILSCALE_KEY=tskey-auth-...` before running the script so it can call `tailscale up --auth-key=...` inside the container.
2. **Use a login link** - leave the key unset; after the installer completes run `pct exec <CTID> -- tailscale up --ssh --accept-routes --qr`. That command prints a short-lived login URL/QR (and the CLI waits until you visit it), so open or scan it to finish the tailnet join manually.

The installer logs the second command automatically if it detects no auth key was supplied.

## Networking

Proof-of-concept deployments in this repository have been performed with **Tailscale** so you can quickly expose the WebUI and builder container across hosts without configuring complex VPNs. If you prefer a standalone VPN, WireGuard is another compatible option since the script only relies on Linux networking primitives.

## Velocloud compatibility

The installer has been tested with **Velocloud 4.5.0** only. Other versions may work, but incompatibilities are possible because newer packages or CLI changes were not validated yet.

## Verification

Download the script manually (`curl -fsSL https://raw.githubusercontent.com/WaffleWhip/velocloud-cloud-init-builder/master/cloud-init-builder-velocloud.sh -o cloud-init-builder-velocloud.sh`) if you must review it before execution.

## License

MIT License (see `LICENSE`).
