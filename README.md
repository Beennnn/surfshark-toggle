# surfshark-toggle

Turn a **Surfshark** (or any on-demand WireGuard/OpenVPN) VPN **off — and keep it off** — on macOS, from a single command or a hardware button.

`scutil --nc stop` does not work on Surfshark. This repo explains why, and ships the one thing that does.

```bash
./surfshark-off.sh    # VPN off, stays off
./surfshark-on.sh     # VPN back on
./surfshark-status.sh # is it up? is the service enabled?
```

---

## The problem: a VPN that refuses to stay off

You click *Disconnect*, or run `scutil --nc stop <id>`, and the tunnel drops… for about half a second. Then it's back. Every time. You can't turn it off.

This is **on-demand**. Surfshark installs a macOS VPN configuration profile with:

- `OnDemandEnabled = TRUE`, and
- an **unconditional** on-demand rule: `Action: Connect`.

macOS's on-demand engine (inside `nesessionmanager`, a privileged system process) watches for network traffic and **re-establishes the tunnel the instant any traffic matches the rule**. Since the rule is unconditional, *everything* matches. So your `stop` succeeds, the on-demand engine immediately notices traffic, and reconnects. You are fighting the kernel, and the kernel wins.

## Why we couldn't "just" do the obvious things

We tried the clean, user-space options first. None of them hold:

| Approach | Why it fails |
|---|---|
| `scutil --nc stop <id>` | Tunnel drops for ~0.5 s, on-demand reconnects on the next packet. |
| Toggle **Auto-connect** off in the Surfshark app | Auto-connect ≠ on-demand. The profile still ships `OnDemandEnabled=TRUE` with a `Connect` rule; the tunnel still recomposes. |
| Edit the VPN profile to set `OnDemandEnabled=FALSE` | The profile is a **system-managed** configuration owned by the Surfshark app / macOS. It isn't a plain file you can safely rewrite, it requires admin, and Surfshark rewrites it on next launch. Not stable. |
| Delete the VPN configuration | Nukes your setup — you'd have to re-add and re-auth the VPN every time. Not a toggle. |
| `pfctl` firewall rule to block the tunnel | Heavy-handed: blocks *traffic* rather than cleanly disabling the VPN, easy to leave your machine in a half-broken network state, and needs root anyway. |
| A pure no-sudo, user-space solution | **Impossible by design.** macOS deliberately gates network-service enable/disable behind admin rights, and on-demand VPN reconnection is a privileged system behavior a non-admin process cannot override. There is no public API to tell a third-party managed VPN profile "stay off" without either the vendor app cooperating or admin rights. |

That last row is the honest answer to *"why couldn't you do better?"*: **you can't**, not without admin. The reconnection lives in a privileged daemon and the profile is system-owned. The best achievable solution is therefore the **least-privileged** one that still works.

> Want the full evidence — the actual `scutil --nc show` output proving the unconditional `Action: Connect` rule, and a point-by-point teardown of every failed approach? See **[docs/how-it-works.md](docs/how-it-works.md)**.

## The parade that works: disable the network service

On-demand can reconnect a VPN. It **cannot connect a network service that is administratively disabled.**

```bash
sudo networksetup -setnetworkserviceenabled "Surfshark. WireGuard®" off
```

Flip that switch and the on-demand engine has nothing to connect — the service is off at the system level. It's clean (no firewall hacks, no profile surgery), fully reversible (`… on` brings it right back), and it survives traffic because it removes the *target* of on-demand rather than trying to out-race it.

The only cost is that it needs `sudo` (network-service state is admin-only). So we grant exactly one scoped, password-less sudoers rule — nothing more — so a Stream Deck button or a Shortcut can flip it instantly. See [`install.sh`](install.sh).

### Why the sudoers rule is scoped the way it is

The rule grants NOPASSWD for a **single subcommand**:

```
youruser ALL=(root) NOPASSWD: /usr/sbin/networksetup -setnetworkserviceenabled *
```

- We scope to `-setnetworkserviceenabled`, which can **only enable/disable** services — it cannot create/delete services, change DNS, routes, or proxies.
- We *don't* pin the exact service string in the rule because the name contains a space and a `®` (`Surfshark. WireGuard®`), which sudoers argument matching can't express cleanly. Scoping to the subcommand is the tightest bound that's actually robust.
- `install.sh` writes the file to `/etc/sudoers.d/surfshark-toggle` **only after** `visudo -cf` validates it — a malformed sudoers file can lock you out of `sudo`, so it never installs an unvalidated one.

## Requirements

- macOS (verified on **26.5.2**, build 25F84; the mechanism is unchanged across recent macOS versions).
- A VPN that shows up in `scutil --nc list` — Surfshark WireGuard/OpenVPN, or any other on-demand WireGuard/OpenVPN service.
- An admin account (needed once, to install the sudoers rule).
- No dependencies beyond stock macOS tools (`bash`, `scutil`, `networksetup`).

## Install

```bash
git clone https://github.com/Beennnn/surfshark-toggle.git
cd surfshark-toggle
chmod +x *.sh
./install.sh          # installs the scoped NOPASSWD sudoers rule (asks for your password once)
./surfshark-off.sh    # should now run with no password prompt
```

If your VPN service isn't named `Surfshark. WireGuard®`, check the exact name with `scutil --nc list` and set it:

```bash
export SURFSHARK_SERVICE="Surfshark. OpenVPN (TCP)"
```

The scripts resolve the connection UUID from the service name at runtime, so nothing is hardcoded to one machine.

## Uninstall

```bash
./surfshark-on.sh     # optional: put the VPN back on first
./uninstall.sh        # removes /etc/sudoers.d/surfshark-toggle
```

After uninstalling, off/on still work — they'll just prompt for your password again.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `service not found in scutil --nc list` | The name doesn't match. Run `scutil --nc list`, copy the quoted name exactly (mind the `.` and `®`), and set `SURFSHARK_SERVICE`. |
| `surfshark-off.sh` still prompts for a password | `install.sh` didn't run, or your username changed. Re-run `./install.sh` and check `sudo cat /etc/sudoers.d/surfshark-toggle`. |
| VPN reconnects a moment after `off` | Confirm the service is actually disabled: `networksetup -getnetworkserviceenabled "Surfshark. WireGuard®"` must say `Disabled`. If it says `Enabled`, the `off` command didn't run with privileges. |
| `off` works but `on` doesn't reconnect | The service is re-enabled but on-demand hasn't fired yet; the script calls `scutil --nc start` for you — check `surfshark-status.sh`. Some setups need a few seconds. |
| You want to see current state | `./surfshark-status.sh` — shows tunnel + whether the service is enabled. Read-only, no sudo. |

## Security notes

- The sudoers rule grants **NOPASSWD for one subcommand only**: `networksetup -setnetworkserviceenabled`. That subcommand can enable/disable network services and nothing else — no service creation/deletion, no DNS, routes, or proxy changes.
- The rule is installed to `/etc/sudoers.d/surfshark-toggle`, mode `0440`, owner `root:wheel`, and is **validated with `visudo -cf` before installation** — a malformed sudoers file can lock you out of `sudo`, so it never installs an unvalidated one.
- Nothing here touches your VPN credentials or the VPN profile itself. It only flips the OS-level enabled/disabled state of the network service.
- Review [`install.sh`](install.sh) before running it — it's ~30 lines and does exactly what's described above.

## Wire it to a button (optional)

Because of the sudoers rule, both scripts fire with no password prompt — ideal for a physical button:

- **Stream Deck** — add a *System → Open* action (or the *BarRaider Advanced Launcher* plugin) pointing at the absolute path of `surfshark-off.sh`, and a second one at `surfshark-on.sh`. Use `surfshark-status.sh` output on a *Text* button if you want a live indicator.
- **Shortcuts / Automator** — a *Run Shell Script* action with `/absolute/path/to/surfshark-off.sh`. Assign a global hotkey via *Shortcuts → Settings → keyboard shortcut*.
- **Raycast / Alfred** — a Script Command that calls the absolute path.

Use absolute paths (the scripts `cd` to their own directory to source `lib.sh`, so they're safe to call from anywhere).

## Repository layout

```
surfshark-toggle/
├── README.md                        this file
├── CLAUDE.md                        context for AI/dev sessions
├── LICENSE                          MIT
├── lib.sh                           shared config + UUID resolution
├── surfshark-off.sh                 VPN off (and stays off)
├── surfshark-on.sh                  VPN on
├── surfshark-status.sh              report state (read-only)
├── install.sh                       install the scoped sudoers rule
├── uninstall.sh                     remove it
├── sudoers.d/
│   └── surfshark-toggle.example     reference rule (do not hand-copy)
└── docs/
    └── how-it-works.md              the full technical writeup + evidence
```

## Origin

Extracted from a live-performance Stream Deck rig where a VPN silently stalled Google Drive sync mid-set. The generic, reusable half — *reliably killing an on-demand VPN* — is this repo.

## License

MIT — see [LICENSE](LICENSE).
