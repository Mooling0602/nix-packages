# deepseek-harness-desktop

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) as a
**desktop application** — the Electron shell from upstream
[`apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/desktop),
repacked for Linux. Upstream ships installers for Windows and macOS only; this
package produces the equivalent runtime tree for `x86_64-linux`.

Current version: 0.2.0-rc.2 (follows [`deepseek-harness-git`](../deepseek-harness-git)).

## What this is

Upstream's Desktop target is an Electron application whose packaging pipeline
(`apps/desktop/scripts/`, `electron-builder`) supports `win-x64`,
`mac-arm64` and `mac-x64`. The restriction is entirely in that packaging
layer: `resolveDesktopBuildTarget` rejects any other target, and the
surrounding scripts download Windows/macOS-specific signing and installer
tooling. The application's runtime code contains no platform assumption for
Linux beyond what Electron itself provides.

This package therefore **rebuilds only the assembly step**. It takes the
already-built application from `deepseek-harness-git` (the same `lib/`,
`renderer/` and workspace packages upstream's build produces), pairs it with
nixpkgs' Electron, and writes the resource tree that
`app.getAppPath()`/`process.resourcesPath` expect. No upstream source file is
touched and nothing is recompiled: the only file rewritten is the bundled main
process `resources/app/lib/main.js`, which receives four minimal Linux patches
at install time (see below).

The result behaves like the official desktop build: it starts a local dsh
server, opens the desktop window, and reads the same skill, pnpm and
primary-runtime payloads from `resources/runtime/`.

## Desktop integration (Linux)

Upstream gates several desktop behaviours on `win32`, and one Linux gap is
borrowed from a downstream fix. All four are small patches applied to the
bundled `lib/main.js` by `desktop-shell-patch.mjs` — each anchored on text
verified to occur exactly once in the bundle, so an upstream bump that moves
the code fails the build instead of shipping a half-patched shell:

- **Tray icon.** Closing the window already hides it (page and Host keep
  running) on every platform, but upstream creates the tray — the way back to
  that window — on Windows only. Linux now gets the same `DesktopTray`: click
  reopens the window, the context menu offers Open/Quit, and the first close
  shows the one-time "you can reopen the window from the system tray" notice
  (upstream's own Windows copy) before hiding. The icon registers over
  StatusNotifierItem like every Electron tray on Linux; no extra library is
  involved. On GNOME the AppIndicator extension is needed for the icon to
  appear, as for any SNI application.
- **Desktop notifications.** Electron sends Linux notifications through
  `libnotify`, which it dlopens by soname at first use; when the library is
  missing it only logs `Unable to find libnotify; notifications disabled`. The
  launcher therefore puts `libnotify` on `LD_LIBRARY_PATH`, and the build
  probes exactly that resolution path from inside the shipped binary, so
  notifications cannot degrade silently. Delivery follows the FreeDesktop
  Desktop Notifications specification and needs a notification daemon (any
  mainstream desktop provides one).
- **Hidden menu bar.** On Linux the application menu appears as a menu bar in
  every window. `DSH_DESKTOP_HIDE_MENUBAR=1` (the default) hides it without
  removing the menu, so its accelerators (Edit menu, F12 dev tools) keep
  working; `DSH_DESKTOP_HIDE_MENUBAR=0` shows the bar again. Upstream ships no
  control for this, hence the environment variable.
- **Graceful signal shutdown.** `SIGINT`/`SIGTERM` now quit through the
  shell's own teardown, and the Host spawns in its own process group so
  terminal signals belong to the shell alone — adapted from
  [Moraxyc/deepseek-harness.nix `desktop-signal-shutdown.patch`](https://github.com/Moraxyc/deepseek-harness.nix/commit/c9999f47789aa77f21366571c8f05449cd671f49),
  to be dropped once upstream handles Linux terminal signals.

### Desktop identity

A window finds its icon in a task bar by name, and the name has four spellings
that all have to agree: the Wayland `app_id`, the X11 `WM_CLASS`, the
`.desktop` file name, and the entry's `StartupWMClass`. The first two are not
this package's to choose — Electron derives them from the application manifest
(`packageJson.desktopName`, else a slug of `app.name`), and the window reports
what it likes regardless of what the package installs. Those two were
`deepseek-ai-dsh-desktop` (from the private package name
`@deepseek-ai/dsh-desktop`) while the entry was installed as
`deepseek-harness.desktop`, so no shell could match the pair and a Wayland task
bar fell back to its generic icon.

The entry is therefore named after the id Electron actually reports, and
`StartupWMClass` carries the same value instead of the product name.
`desktop-identity.mjs` re-derives the id from the shipped manifest with
Electron's own algorithm and checks the file name, `StartupWMClass` and `Icon=`
against it at build time, so an upstream rename of that private package fails
the build and names both sides rather than silently un-matching every window.

The icon is installed under the same identity, in both the raster form the
window and tray use and the vector original upstream ships.

## Layout

```
deepseek-harness                            the Electron binary
resources/app/                              app.getAppPath()
resources/app/dsh/                          the bundled dsh runtime
resources/app/dsh/desktop-runtime.json      runtime descriptor
resources/runtime/office-skills/            boot-required skill assets
resources/runtime/bin/node                  standalone Node for skill-office
resources/runtime/primary-runtime/          interpreters + Python libraries
resources/runtime/primary-runtime/dependencies/pnpm/
                                            pnpm CLI
resources/icon.png                          window/taskbar icon
```

`desktop.nix` documents the six load-bearing details of this layout, each
verified experimentally against the unmodified upstream application. In short:
the Electron binary must not be named `electron` (that name makes Electron
report `app.isPackaged === false`); the runtime belongs at
`resources/app/dsh`, not `resources/dsh`; the descriptor is checked by the
application; `CHROME_DEVEL_SANDBOX` plus a `LD_LIBRARY_PATH` carrying
libstdc++ are required at launch; sharp's native addon needs a dynamically
linked libvips, which the package substitutes under the name the addon asks for
because the prebuilt one statically embeds its own glib and segfaults the Host;
and pnpm belongs inside the primary-runtime payload, because three readers
resolve it by absolute path and none searches.

## Versions are derived, not restated

Nothing in this package hardcodes an upstream version. `version` and
`pnpmVersion` come from
[`../deepseek-harness-git/hashes.json`](../deepseek-harness-git/hashes.json),
and two further release facts are **read out of the tree the build assembled**:

- `release.nodeVersion` — what the bundled Electron reports as
  `process.versions.node`.
- `release.hostProtocolVersion` — the lifecycle generation declared in
  upstream's `apps/desktop/src/host-protocol.ts`.

Both matter because the shipped reader (`readDesktopRuntime`, inlined into
`lib/main.js`) type-checks them without comparing either to anything. A stale
value would therefore be accepted silently, so the build refuses to guess.

Seven things are checked at build time rather than discovered at launch:

- `desktop-coverage.mjs` checks that every bare import in the packaged shell
  resolves inside `resources/app/node_modules`, and that every dependency in
  upstream's `apps/desktop-host/package.json` is linked into the bundled
  runtime. A dependency upstream adds and this package forgets is a launch-time
  `ERR_MODULE_NOT_FOUND` today; here it names the package at build time.
- `desktop-shell-patch.mjs` refuses to patch anything but an exact match of
  each anchor, and syntax-checks the rewritten bundle, so an upstream bump that
  moves the patched code names the patch instead of shipping half of it.
- `desktop-identity.mjs` re-derives the desktop id from the shipped manifest
  and refuses a tree whose entry name, `StartupWMClass` or icons disagree with
  it, so a Wayland window cannot quietly stop matching its icon.
- `desktop-inspector-worker.mjs` reads the experimental Inspector's Worker spawn
  site out of the shipped runtime, requires it to carry `--expose-internals`,
  and then spawns one real Worker with exactly that `execArgv` under this
  build's Electron. The Worker's first import reaches Node's internal module
  loader through the prebuilt `node-addon-require-builtin` addon, whose Electron
  runtime fingerprint nixpkgs' Electron never carries, so a regression here is
  developer mode opening onto a plugin that fails to activate, with nothing else
  in the build noticing.
- `desktop-runtime-pnpm.mjs` reads the pnpm entry point back out of the two
  shipped bundles that resolve it, pins the Host's support directory to the
  shell's Node launcher directory, ties it to the primary-runtime payload root,
  and runs the entry through the packaged launcher. pnpm is reached only when a
  plugin is installed, updated or removed, so a move of this path surfaces as a
  `MODULE_NOT_FOUND` naming the plugin.
- The notification probe dlopens `libnotify` through the shipped binary's own
  search path — the resolution the Electron notification backend uses — so a
  silently disabled notification stack fails the build.
- The primary-runtime manifest's `node` field is checked against the binary
  that is actually linked.

Because of this, bumping the version is
`pkgs/by-name/de/deepseek-harness-git/update.sh` alone — this package has no
pin of its own and needs no separate update step. Its lists are checked against
the new upstream tree during the build.

## Usage

```console
nix build .#deepseek-harness-desktop
./result/bin/deepseek-harness
```

Or, from a NixOS configuration:

```nix
environment.systemPackages = [ inputs.nix-packages.packages.${pkgs.system}.deepseek-harness-desktop ];
```

## Notes and limitations

- **`x86_64-linux` only.** The package inherits the desktop layout from
  upstream's Electron build; other systems are not declared because the
  assembly has not been verified there.
- **Closure size.** The output itself is ~384 MB (the Electron binary is
  ~258 MB of it). At runtime it reuses the `deepseek-harness-git` store tree
  for the bundled dsh payload, so the two packages share one copy of the
  application rather than duplicating it.
- **Auto-update is inert.** Upstream's Desktop build ships
  `electron-updater`, but no Nix-managed installation is ever updated by it —
  upgrades go through `nix`. The updater is present because the application
  imports it unconditionally.
- **Not affiliated with DeepSeek.** This is a downstream repackaging.
