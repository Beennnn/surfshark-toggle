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

## Wire it to a button (optional)

Point a Stream Deck **System → Open** / multi-action, or an Automator/Shortcuts *Run Shell Script*, at `surfshark-off.sh` and `surfshark-on.sh`. Because of the sudoers rule, the button fires with no password prompt.

## Origin

Extracted from a live-performance Stream Deck rig where a VPN silently stalled Google Drive sync mid-set. The generic, reusable half — *reliably killing an on-demand VPN* — is this repo.

## License

MIT — see [LICENSE](LICENSE).
