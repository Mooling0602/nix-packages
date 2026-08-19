# axolotl-launcher-bin

> English · [中文（简体）](README_zh_CN.md)

[Axolotl Launcher](https://github.com/Mystic-Stars/Axolotl), a free cross-platform Minecraft launcher built on the Modrinth
ecosystem, packaged from the official Linux `.deb`.

Current version: 1.8.7.

Unlike the official AppImage (which bundles its own self-contained GTK/WebKit
runtime and therefore cannot read the host session's cursor-theme config), the
`.deb` payload is a dynamically linked binary that uses the system GTK3/WebKit
libraries (webkitgtk_4_1, gtk3, libsoup_3, glib, …). This means the cursor
theme follows the desktop session correctly under both X11 and native Wayland.

The package extracts the `.deb`'s `data.tar`, installs the main binary as
`axolotl-launcher`, and uses `autoPatchelfHook` + `buildInputs` to satisfy all
dynamic dependencies.

## Display backends

- **X11 (default)**: rendered through XWayland on Wayland sessions.
- **Native Wayland**: prepend `GDK_BACKEND=wayland`:

  ```bash
  GDK_BACKEND=wayland axolotl-launcher
  ```

Both backends use the system GTK/WebKit, so the in-window pointer cursor
follows the session theme (`XDG_CURSOR_THEME` / GSettings) in both modes.

## Update

```bash
./update.sh
```

To update to a specific version:

```bash
./update.sh 1.8.6
```
