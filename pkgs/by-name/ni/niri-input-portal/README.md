# niri-input-portal

> English · [中文（简体）](README_zh_CN.md)

An `org.freedesktop.impl.portal.InputCapture` backend for the
[niri](https://github.com/YaLTeR/niri) compositor, so KVM software that speaks
the input-capture portal (Deskflow, Synergy 3, Input Leap) can act as a
**server** under niri — sharing this machine's keyboard, mouse and clipboard
with another computer. Tracked from upstream `main` at
`f363e34380b3f8bd9ffc9a167b7b58d3c208574b` (MIT).

niri exposes `Mutter.ScreenCast`, `Mutter.DisplayConfig` and
`Mutter.ServiceChannel`, but not `Mutter.InputCapture`, so
`xdg-desktop-portal-gnome` never publishes the interface and every
`CreateSession` from a KVM client fails with
`failed to initialize input capture session`. Upstream tracks this in
[niri#823](https://github.com/YaLTeR/niri/issues/823) (open since 2024-11);
this backend fills the gap through protocols niri does support
(`wlr-layer-shell`, `pointer-constraints`, `relative-pointer`,
`ext-data-control`).

Upstream publishes no tags and no releases, so this package follows `main`.
Run `update.sh` to move to the latest commit.

## What the package installs

| Path | Purpose |
|------|---------|
| `bin/niri-input-portal` | the portal backend binary |
| `share/xdg-desktop-portal/portals/niri-input.portal` | declares the `InputCapture` and `Clipboard` impl backends |
| `share/dbus-1/services/org.freedesktop.impl.portal.desktop.niri-input.service` | D-Bus activation; `Exec` rewritten to the store path |
| `share/systemd/user/niri-input-portal.service` | upstream's unit, rewritten to the store path. nixpkgs relocates it here from `lib/systemd/user`, and the location is on the systemd user search path once the package sits in a profile. |

## Wiring it up

The package is not a drop-in application. `xdg-desktop-portal` starts the
backend on demand, the first time a client asks for input capture, so three
things have to line up on the host.

**1. Register and route the backend.** `install.sh` upstream would write
`~/.config/xdg-desktop-portal/<desktop>-portals.conf`; a declarative setup
adds the package to `extraPortals` and routes both interfaces instead:

```nix
xdg.portal = {
  extraPortals = [ pkgs.niri-input-portal ];
  config.niri = {
    "org.freedesktop.impl.portal.InputCapture" = [ "niri-input" ];
    "org.freedesktop.impl.portal.Clipboard" = [ "niri-input" ];
  };
};
```

The `Clipboard` line is not optional once the client asks for clipboard
sharing. The clipboard portal attaches to a session another portal created,
so if it falls through to a different backend, `RequestClipboard` fails and
the client reacts by discarding the session and opening a new one — a
create/destroy loop that never reaches capture.

**2. Provide the D-Bus activated unit.** The service file references
`SystemdService=niri-input-portal.service`, so a unit of that name has to
exist. The package ships one under `share/systemd/user/`, and systemd already
searches that directory once the package is in a profile — but it carries
`ConditionEnvironment=WAYLAND_DISPLAY`. When the systemd user instance has not
imported that variable, the unit is skipped silently and D-Bus reports the
service name as not activatable. Declaring the unit yourself drops that
failure mode:

```nix
systemd.user.services.niri-input-portal = {
  Unit = {
    Description = "InputCapture portal backend for niri";
    PartOf = [ "graphical-session.target" ];
    After = [ "graphical-session.target" ];
  };
  Service = {
    Type = "dbus";
    BusName = "org.freedesktop.impl.portal.desktop.niri-input";
    ExecStart = "${pkgs.niri-input-portal}/bin/niri-input-portal";
    Restart = "on-failure";
    RestartSec = 1;
    Slice = "session.slice";
  };
};
```

The unit is D-Bus activated, so it is deliberately not enabled and not
`WantedBy` anything: it is not resident when unused.

**3. Add an escape binding to the niri config.** While a capture is active
the keyboard is grabbed exclusively and the pointer is locked, so nothing
inside the process can free it. niri resolves its own bindings before
clients see them, which is exactly why this works:

```kdl
Mod+Shift+Escape allow-inhibiting=false { spawn "niri-input-portal" "--release"; }
```

Out-of-band escapes are `niri-input-portal --release`, `--disarm` and
`--status`; `pkill -f niri-input-portal` always works too, because the
compositor destroys the surface and the pointer lock when the client
disconnects.

## Requirements

- niri 25.11 or newer (verified upstream against 25.11 and 26.04).
- `xdg-desktop-portal` 1.21.1 or newer for clipboard sharing; older versions
  gate clipboard access on the session being a *RemoteDesktop* session and
  reject the request with `Invalid session type`.
- The client side must link `libei` and `libportal`. The `deskflow` package
  in nixpkgs does: `PortalInputCapture.cpp` is present in 1.26.0, while
  clipboard support (`PortalClipboard.cpp`, `EiClipboard.cpp`) only landed in
  upstream PR #9431 and is therefore *not* in 1.26.0.

## Known limits

Upstream's README documents these; they are worth knowing before relying on
the capture:

- Barrier surfaces occupy the outermost pixel row or column of an output
  while armed, so a click landing exactly there is swallowed.
- Output scale and transform are read but not applied to motion deltas, so on
  a fractionally scaled output the remote pointer speed will not match.
- Session persistence is not implemented: a client asking for `persist_mode`
  gets a fresh session every time.
- Claiming the clipboard discards whatever was on it, and releasing it does
  not restore the previous content. The primary selection is not shared.
- Rearming while the pointer already rests on a barrier captures immediately.

## Package patches

`fix-eis-device-region.patch` makes the backend report an `ei_device.region`.

Upstream never sends one, and it is the only thing a libei client has to size
"this screen" with. Without it Deskflow falls back to a 1×1 screen: the cursor
position of every activation collapses onto `(0, 0)`, which leaves the **top
edge** as the only one it can ever release the pointer towards. A client placed
below or to the right of this machine is then unreachable. Deskflow core prints
the symptom outright on stderr:

```
WARNING: on switch, y (11) exceeds the bottom boundary (dy + height = 1)
```

The region has to go out **with the device**, before `ei_device.done`: libei reads
it while building the device and never looks again — the protocol has no region
event at all — so a region sent later is the same as none. The patch therefore
reads the output layout once on `ConnectToEIS`, hands the union to the EIS
session, and reports it from the callback that builds each device.

Drop the patch once upstream reports a region; the removal condition and the
way to recheck it live in `MAINTENANCE.md` in nixos-config.

## Update

```sh
./update.sh
```

Fetches the current `main` commit, rewrites the revision, version and source
hash, recomputes the vendored crate hash, and verifies the build.
