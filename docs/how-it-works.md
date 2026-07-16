# How it works — the macOS on-demand VPN mechanism

This is the long-form version of the README's *"why we couldn't do better"* section, with the actual evidence from a running Surfshark install (macOS 26.5.2).

## The two layers you're fighting

A macOS VPN has **two independent switches**, and turning off the one you can see doesn't touch the one that reconnects you:

1. **The tunnel** — the live connection. `scutil --nc start/stop <id>` controls this. This is what the app's *Connect/Disconnect* button does.
2. **On-demand** — a rule set stored in the VPN *configuration profile* and enforced by `nesessionmanager`, a privileged system daemon. When enabled, it re-establishes the tunnel automatically based on network traffic. This is the layer that ignores your *Disconnect*.

Stopping the tunnel while on-demand is active is like switching off a light that has a motion sensor: it comes back on the moment you move.

## The evidence

Ask macOS to describe the Surfshark WireGuard configuration:

```console
$ scutil --nc show "025B5EA8-806D-40FB-AE3A-B9639BCCEB25"
* (Disconnected)   025B5EA8-... VPN (com.surfshark.vpnclient.macos) "Surfshark. WireGuard®"
  ...
  OnDemandEnabled : FALSE
  OnDemandRules : <array> {
    0 : <dictionary> {
      Action : Connect
    }
  }
  RemoteAddress : Multiple endpoints
```

Two things to read here:

- **`OnDemandRules` is a single dictionary containing only `Action : Connect`** — no `URLStringProbe`, no `SSIDMatch`, no `InterfaceTypeMatch`, no `DNSDomainMatch`. A rule with an action and **no match conditions is unconditional**: it fires for *all* traffic. So whenever on-demand is on, *any* packet triggers a reconnect.
- **`OnDemandEnabled` is the master switch, toggled by the Surfshark app.** In the capture above it reads `FALSE` because auto-connect happened to be off at that moment. During the incident that motivated this tool it was `TRUE` — and with an unconditional `Connect` rule, that means "reconnect on literally any traffic". You do not control this field; the app rewrites it.

That combination — a system-owned profile + an unconditional connect rule + a privileged enforcement daemon — is why the tunnel refuses to stay down.

## Why each user-space fix fails

### `scutil --nc stop <id>`
Stops the tunnel. `nesessionmanager` sees the next packet match the unconditional rule and starts it again within ~0.5 s. Net effect: nothing.

### Turning off "Auto-connect" in the Surfshark app
Auto-connect and on-demand are related but not identical, and toggling the app setting does not reliably clear `OnDemandEnabled` / the `Connect` rule from the profile in a way that survives. The tunnel can still recompose.

### Editing the profile to set `OnDemandEnabled = FALSE`
The profile lives in system-owned storage (`/Library/Preferences/com.apple.networkextension*.plist`, root:wheel). It is not a user file you can safely hand-edit — it's a binary managed store, changes require admin, and Surfshark rewrites its configuration on launch. Even if you flip it, it doesn't stay flipped.

### Deleting the VPN configuration
Works, but it's destructive, not a toggle: you'd re-add and re-authenticate the VPN every single time you wanted it back. Unusable as an on/off button.

### `pfctl` firewall rules
You can block the tunnel's traffic with a packet filter, but that blocks *traffic* rather than *disabling the VPN* — it's easy to leave the machine in a half-broken network state, it still needs root, and it's far more fragile than flipping one service switch.

### A pure no-sudo solution
Not possible by design. Enabling/disabling a network service is an admin-gated operation, and on-demand reconnection runs in a privileged daemon. macOS exposes **no public API** for a non-admin process to tell a third-party, app-managed VPN profile "stay off". Cooperation would have to come from the vendor app or from admin rights. There is no cleverer trick hiding here — this is the ceiling.

## The fix: disable the network *service*

On-demand can (re)connect a service. It **cannot connect a service that is administratively disabled**:

```console
$ sudo networksetup -setnetworkserviceenabled "Surfshark. WireGuard®" off
```

This removes the *target* of the on-demand rule instead of racing against it. Verify:

```console
$ networksetup -getnetworkserviceenabled "Surfshark. WireGuard®"
Disabled          # on-demand now has nothing to connect
```

Reversible at any time:

```console
$ sudo networksetup -setnetworkserviceenabled "Surfshark. WireGuard®" on
```

It's the *least-privileged thing that actually works*: no firewall surgery, no profile hacking, no deletion — one admin-gated switch, cleanly reversible.

## Why the tool resolves the UUID at runtime

The connection ID (`025B5EA8-…` above) is **per-install** — it's regenerated if you remove and re-add the VPN, and it differs on every machine. Hardcoding it makes the scripts break silently on anyone else's setup. So `lib.sh` looks the ID up from the stable human name (`scutil --nc list | grep "Surfshark. WireGuard®"`) each time. Change only the *name* (via `SURFSHARK_SERVICE`) and everything else follows.

## Verified environment

- macOS **26.5.2** (build 25F84)
- Surfshark macOS app, WireGuard® protocol (service `com.surfshark.vpnclient.macos`)
- Also present and toggleable the same way: `Surfshark. OpenVPN (TCP)`
