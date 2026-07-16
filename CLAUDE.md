# CLAUDE.md — surfshark-toggle

Context for any Claude session opening this repo.

## What this is

A small macOS tool to turn a **Surfshark** (or any on-demand WireGuard/OpenVPN)
VPN off and keep it off, plus a documented explanation of *why that's hard*.
Extracted from the `~/dev/music/stream-deck` live-rig tooling, where a VPN
silently stalled Google Drive sync mid-set.

- Repo: https://github.com/Beennnn/surfshark-toggle (public, MIT)
- Origin scripts still live in `~/dev/music/stream-deck/surfshark-{on,off}.sh`
  (machine-specific, hardcoded UUID). This repo is the generalized, portable
  version — don't re-hardcode the UUID here.

## The core fact (don't re-derive it every session)

`scutil --nc stop` **cannot** turn Surfshark off: the VPN profile carries an
unconditional on-demand rule (`OnDemandRules: [{ Action: Connect }]`) enforced
by the privileged `nesessionmanager` daemon, so the tunnel recomposes on the
next packet. The only reliable, least-privilege parade is to **disable the
network service itself**:

```bash
sudo networksetup -setnetworkserviceenabled "Surfshark. WireGuard®" off
```

On-demand can't connect a disabled service. Full evidence + why every
user-space alternative fails: [`docs/how-it-works.md`](docs/how-it-works.md).

## Layout

| File | Role |
|---|---|
| `lib.sh` | Config + resolves the VPN connection UUID from the service **name** (never hardcode the UUID). |
| `surfshark-off.sh` / `surfshark-on.sh` | The toggle. |
| `surfshark-status.sh` | Report tunnel + service-enabled state (read-only, no sudo). |
| `install.sh` / `uninstall.sh` | Manage the scoped NOPASSWD sudoers rule at `/etc/sudoers.d/surfshark-toggle`. |
| `sudoers.d/surfshark-toggle.example` | Reference rule — never hand-copy; `install.sh` validates with `visudo -cf`. |
| `docs/how-it-works.md` | The deep-dive. |

## Conventions / gotchas

- **Never hardcode the connection UUID** — it's per-install. Always resolve
  from the name via `vpn_id()` in `lib.sh`.
- **Service name has a space and a `®`** (`Surfshark. WireGuard®`) → sudoers
  arg-matching can't pin it cleanly, so the rule is scoped to the
  `-setnetworkserviceenabled` subcommand instead. This is intentional; don't
  "fix" it by trying to embed the exact string in sudoers.
- **Never write an unvalidated sudoers file** — always `visudo -cf` on a temp
  file first (a malformed sudoers file locks the user out of `sudo`).
- Keep the scripts dependency-free (pure bash + `scutil` + `networksetup`).
- Verified on macOS 26.5.2. If tested on other versions, note them in
  `docs/how-it-works.md` § Verified environment.
