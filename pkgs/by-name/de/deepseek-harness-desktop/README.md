# deepseek-harness-desktop

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) as a
**desktop application** — the Electron shell from upstream
[`apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/desktop),
repacked for Linux. Upstream ships installers for Windows and macOS only; this
package produces the equivalent runtime tree for `x86_64-linux`.

Current version: 0.2.1-rc.1 (follows [`deepseek-harness-git`](../deepseek-harness-git)).

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
process `resources/app/lib/main.js`, which receives the minimal Linux patches
applied at install time: four shell behaviours from `desktop-shell-patch.mjs`
and two window-glass patches from `desktop-window-glass.mjs` (see below).

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

### Window glass

Upstream gives the macOS window a translucent, backdrop-blurred material
(`vibrancy: "sidebar"` and a transparent `backgroundColor`), pairs it with a
packaged Web UI rule that clears the document background under
`html[data-platform=darwin]`, and has the preload mark the document root with
`process.platform`. Linux gets the same two halves from
`desktop-window-glass.mjs`, because that is what lets a compositor's blur show
through:

- The main window is created with `transparent: true` and a fully transparent
  `backgroundColor`, the counterpart of the darwin spread directly below it.
  Electron offers no vibrancy or `backgroundMaterial` on Linux, and without
  `transparent` it hands the compositor an opaque surface that no page styling
  can reveal.
- The document the bundle serves from its own `serveWebDocument()` gets one
  injected style sheet holding the Linux counterpart of the rules the packaged
  Web UI ships for darwin. Five surfaces have to step aside before the backdrop
  is visible: the `html` and `body` background, the frame element (replaced by a
  72% tint of its own `--dsw-alias-bg-base`, which keeps text legible over the
  blurred wallpaper), the sidebar column together with the
  `--dsw-specific-sidebar-fill` token its inner surface consumes, the
  conversation root, and the composer seat. Missing any one of them is enough to
  hide the blur, since a single opaque layer covers the rest. Content keeps the
  backgrounds it sets for itself, so cards and panels stay legible and the glass
  shows around the interface.

  The composer seat is the one surface that is cleared rather than retinted, and
  it is worth a note. Upstream hides the transcript scrolling under the input
  card by fading to solid `--dsw-alias-bg-base` over a fixed 36px band; on darwin
  that fill is invisible because the column beneath paints the same colour, but
  over a cleared column it becomes an opaque frame around the card. Replacing it
  with a translucent scrim only trades a black band for a grey one, and a masked
  `backdrop-filter` is worse: on a transparent window Chromium samples the
  window's own transparency as opaque black, so the band renders as a smeared
  black halo. Clearing the fill leaves the seat transparent, which is the only
  treatment that matches the cleared column around it. What the fill used to mask
  stays masked by the card itself, which is wider than the transcript column
  (`--dsh-composer-card-max-width` is `--dsh-chat-content-width` plus the side
  clearance) and paints its own opaque `--dsw-specific-input-major`.

  The selectors carry every rule on specificity alone, with no `!important`
  anywhere, and avoid the build's hashed class names: a hardcoded hash would not
  survive an upstream bump. On the running window the only pixels left fully
  opaque belong to content cards and to the input card itself.
  `prefers-reduced-transparency: reduce` restores an opaque frame and an opaque
  seat, the same fallback upstream ships.

Nothing in the packaged Web dist is rewritten. Those files are upstream build
output whose names carry content hashes, so patching them would be the more
fragile of the two options, and the injection point (the shell's own document
handler, which already injects its boot script into the same `<head>`) is
reached wherever the frontend is served from. The injected rule is inert
elsewhere by construction: only the application window's preload calls
`markDocumentPlatform()`, so the renderer pages served from `dsh-app://shell/*`
(welcome, update dialog, mandatory update) never match the selector and keep
their own opaque background.

The blur itself belongs to the compositor, so it needs a window rule there, and
niri leaves `blur` off unless a rule turns it on. Whether anything is left to do
depends on the configuration the session actually loads: a rule that enables the
effect for every window, or for this app id, is enough, and then this package
needs no configuration at all.

Check the file the running session reads before editing anything. niri takes it
from the `NIRI_CONFIG` environment variable, which is not necessarily
`~/.config/niri/config.kdl`:

```console
$ tr '\0' '\n' < /proc/$(pgrep -x niri)/environ | grep NIRI_CONFIG
NIRI_CONFIG=/home/user/.config/niri-some-flavour/config.kdl
```

If that file, or anything it includes, already carries a `background-effect`
block with `blur true` and no `match` (which matches every window), the window is
already frosted and nothing more is required. Otherwise add a rule to that file,
on [niri](https://github.com/YaLTeR/niri) 26.04 or newer, whose
`ext-background-effect` support and `background-effect` window rule this was
written against:

```kdl
window-rule {
    match app-id=r#"^deepseek-ai-dsh-desktop$"#
    background-effect {
        blur true
    }
}
```

The app id is the one Electron derives from upstream's application manifest,
which is exactly what `desktop-identity.mjs` enforces and what the installed
`.desktop` file carries as `StartupWMClass` (see Desktop identity below). Under
a compositor without such a rule the window is simply transparent: the
wallpaper shows through the page backdrop unblurred, and text over it can lose
contrast. To turn the effect off entirely, drop the rule, or build this package
without step 2b.

The window itself keeps `frame: true`: niri draws the decorations server side
(rounded corners, border and focus ring, through `prefer-no-csd`,
`clip-to-geometry` and `draw-border-with-background false`), so the client
neither draws decorations nor needs drag regions of its own. The patch adds no
frame option and no `-webkit-app-region` rule.

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

Eight things are checked at build time rather than discovered at launch:

- `desktop-coverage.mjs` checks that every bare import in the packaged shell
  resolves inside `resources/app/node_modules`, and that every dependency in
  upstream's `apps/desktop-host/package.json` is linked into the bundled
  runtime. A dependency upstream adds and this package forgets is a launch-time
  `ERR_MODULE_NOT_FOUND` today; here it names the package at build time.
- `desktop-shell-patch.mjs` refuses to patch anything but an exact match of
  each anchor, and syntax-checks the rewritten bundle, so an upstream bump that
  moves the patched code names the patch instead of shipping half of it.
- `desktop-window-glass.mjs` holds the two window-glass patches to the same
  rule: an anchor that no longer occurs exactly once fails the build by name,
  and the rewritten bundle is syntax-checked again afterwards.
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
the new upstream tree during the build. That script also keeps the
`Current version:` line at the top of this file in sync, and nothing else here.

Some version numbers in this package are recorded evidence rather than pins,
and the update script deliberately leaves them alone:

- The bundle version each patch was last verified against, in the header of
  `desktop-shell-patch.mjs` (currently `0.2.0-rc.2`) and of
  `desktop-window-glass.mjs` (currently `0.2.1-alpha.4`). Those are evidence,
  not pins: the anchors are re-checked against every new tree by the build
  itself, so a stale number is honest — it says which bundle the patch was last
  inspected by eye on. Rewriting it automatically would claim a re-verification
  that never happened.
- The Electron, Node and libvips versions in note 5 of `desktop.nix`. The sharp
  crash was measured on those exact builds; the numbers are what makes the
  note checkable, and a bump here changes none of the measurements.

Update them by hand, and only after actually re-checking the anchors or
re-running the sharp probe on the new versions.

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
