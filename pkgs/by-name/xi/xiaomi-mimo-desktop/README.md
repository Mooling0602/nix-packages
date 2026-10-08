# xiaomi-mimo-desktop

> English · [中文（简体）](README_zh_CN.md)

[Xiaomi MiMo Desktop](https://mimo.xiaomimimo.com/desktop/) (小米 MiMo 桌面客户端) —
Xiaomi's official AI desktop agent for office work, design, coding and
multimodal creation, with the Xiaomi MiMo models built in. It's a closed-source
commercial software (`unfree`), and currently only supported on `x86_64-linux`.

This package is built from the official Linux `.deb`. Upstream only links the
Windows and macOS installers on its download page; the Linux artifact is
published on the same download CDN and is also tracked by the AUR package
[`mimo-desktop`](https://aur.archlinux.org/packages/mimo-desktop). An Internet
connection and a Xiaomi MiMo account are required to use the app.

## Maintenance notes

Current version: 26.909.91205. When a newer version is available upstream, you
may wait for this package to be updated, or open an Issue to request it.

When upstream releases a new version, update the `version` and `hash` in
`package.nix`. The direct download URL is:

```sh
https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-<version>-x64.deb
```

To get the SRI-format hash:

```sh
nix store prefetch-file https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-<version>-x64.deb
```

Alternatively, run the update script. With no argument it auto-detects the
latest version; you can also specify a version manually:

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

If the target version matches the current version in `package.nix`, the script
exits without recomputing the hash. Using `-f` or `--force` requires a version
and forces the hash to be recomputed.

Upstream publishes no `latest` alias and no update feed for the Linux build, so
the update script discovers new versions through the AUR `mimo-desktop` package
metadata and then verifies that the versioned CDN URL responds. If the AUR
package lags behind or disappears, pass the version explicitly.

## Packaging notes

- The upstream installer puts the app in `/opt/Xiaomi MiMo/`; this package
  relocates it to `$out/share/xiaomi-mimo-desktop` and runs it inside a
  bubblewrap FHS sandbox (`buildFHSEnv`) launched as `xiaomi-mimo-desktop`.
  The upstream desktop entry is kept (Exec rewritten to the launcher),
  including the `xiaomi-mimo://` scheme handler.
- The FHS sandbox is a requirement, not a nicety: the app bundles its own
  CPython 3.12 runtime and native Node modules, and its agent installs
  third-party Python wheels at runtime. autoPatchelf breaks the bundled
  runtime's glibc symbol versioning, and runtime-installed wheels cannot be
  patched after the fact, so the whole app runs unpatched against the standard
  `/usr/lib` layout inside the sandbox. The sandbox needs unprivileged user
  namespaces (bubblewrap), which NixOS provides out of the box.
- Like other Electron apps on NixOS, the upstream setuid `chrome-sandbox`
  cannot be honoured from the Nix store; the launcher passes `--no-sandbox`.
- The computer-control and self-evolution features use the bundled Python
  runtime (`resources/runtimes/linux-x64/python/`, driven by
  `resources/computer-use-linux/runtime.py` and `resources/evolve-seed/`), so
  no system Python is required; any Python dependencies those features need
  are installed by the app itself at runtime.
- The only known gap: Python's `crypt` stdlib module in the bundled runtime
  needs `libcrypt.so.1`, which neither Nixpkgs nor the sandbox provides
  (Nixpkgs' libxcrypt ships `libcrypt.so.2` with XCRYPT symbol versions). Only
  that stdlib module is affected.
- Upstream's Linux build forgets to bundle the `node-machine-id` package that
  its Xiaomi passport login requires: `require("node-machine-id")` from
  `app.asar/out/main` always fails, so every login attempt dies with "参数错误"
  (passport 20014). This package drops a small shim module at
  `resources/node_modules/node-machine-id`, where Node's resolver finds it
  without repacking the asar. The shim prefers a real system machine id
  (`/var/lib/dbus/machine-id`, `/etc/machine-id`) and otherwise generates a
  random one, persisted in `~/.config/Xiaomi MiMo/machine-id` so it stays
  stable across runs.
