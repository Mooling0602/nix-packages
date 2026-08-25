# axolotl-launcher-bin

> English · [中文（简体）](README_zh_CN.md)

[Axolotl Launcher](https://github.com/Mystic-Stars/Axolotl), a free cross-platform Minecraft launcher built on the Modrinth
ecosystem, packaged from the official Linux `.deb`.

Current version: 1.8.14.

## FHS environment

The launcher is wrapped in a bubblewrap FHS sandbox (`buildFHSEnv`). Minecraft
launchers download prebuilt Java runtimes and native libraries that assume a
standard Linux filesystem, and mods frequently ship their own native libraries
linking against distro sonames. Inside the sandbox all of those binaries — the
launcher itself, the auto-downloaded JREs, LWJGL natives and mod-provided
`.so` files — resolve their dependencies through `/usr/lib` and the ldconfig
cache, so dependency-heavy mods launch normally on NixOS.

The environment ships the full Minecraft runtime stack (mirroring
[prismlauncher](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/pr/prismlauncher/package.nix)):
audio servers (alsa, pulseaudio, pipewire, jack), X11/Wayland client libraries,
GL/Vulkan loaders, udev (oshi), flite (narrator), gamemode, libusb
(controllers), plus `pciutils`/`xrandr` for the helpers Minecraft shells out
to. A `jdk21` fallback is exposed as `/usr/bin/java`; the launcher still
auto-downloads the exact JRE each instance needs (verified working inside the
sandbox). GPU drivers come from the host's `/run/opengl-driver`, which is
bind-mounted into the sandbox and takes priority on the library path.

The GUI continues to use GTK3/WebKitGTK from the sandbox's `/usr/lib`, with
dconf, GIO modules (TLS, GSettings) and GStreamer plugins all wired up, so
theming and media playback keep working as before.

## Display backends

The wrapper auto-detects the display protocol (`GDK_BACKEND=wayland` under
Wayland, `x11` otherwise). Override by exporting `GDK_BACKEND` before
launching:

```bash
GDK_BACKEND=wayland axolotl-launcher
```

The in-window pointer cursor follows the session theme (`XDG_CURSOR_THEME` /
GSettings) in both modes.

## Update

```bash
./update.sh
```

To update to a specific version:

```bash
./update.sh 1.8.6
```
