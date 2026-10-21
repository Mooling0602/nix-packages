# niri-input-portal

> English · [中文（简体）](README_zh_CN.md)

This package builds
[niri-input-portal](https://github.com/Qingswe/niri-input-portal), an
`org.freedesktop.impl.portal.InputCapture` backend for the
[niri](https://github.com/YaLTeR/niri) compositor, so keyboard and mouse
sharing software that speaks the input-capture portal (Deskflow, Synergy 3,
Input Leap) can act as a **server** under niri — sharing this machine's
keyboard, mouse and clipboard with another computer. Pinned to upstream `main`
at `49f82a63ca53b0137ad4eea08f4cd9d72642a22b` and built from source; see
[Upstream and licensing](#upstream-and-licensing).

niri exposes `Mutter.ScreenCast`, `Mutter.DisplayConfig` and
`Mutter.ServiceChannel`, but not `Mutter.InputCapture`, so
`xdg-desktop-portal-gnome` never publishes the interface and every
`CreateSession` from such a client fails with
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

## Upstream and licensing

This package is a third-party rebuild, not an upstream release, and it is not
affiliated with the upstream author. Source:
[Qingswe/niri-input-portal](https://github.com/Qingswe/niri-input-portal), MIT,
Copyright © 2026 Qingswe.

Upstream publishes neither tags nor binaries, so nothing here repackages a
project-provided artifact — `package.nix` fetches the pinned commit and builds
it from source. Upstream's `LICENSE` file is part of that source and its
copyright notice is left untouched; nothing is copied to `share/licenses`,
matching the rest of this repository.

No source patches are applied: the packaging only rewrites the hardcoded `/usr`
paths in upstream's unit and D-Bus service files.

## Update

```sh
./update.sh
```

Fetches the current `main` commit, rewrites the revision, version and source
hash, recomputes the vendored crate hash, and verifies the build.
