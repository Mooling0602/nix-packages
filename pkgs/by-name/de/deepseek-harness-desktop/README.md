# deepseek-harness-desktop

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) as a
**desktop application** — the Electron shell from upstream
[`apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/desktop),
repacked for Linux. Upstream ships installers for Windows and macOS only; this
package produces the equivalent runtime tree for `x86_64-linux`.

Current version: 0.1.7-rc.2 (follows [`deepseek-harness-git`](../deepseek-harness-git)).

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
patched.

The result behaves like the official desktop build: it starts a local dsh
server, opens the desktop window, and reads the same skill, pnpm and
primary-runtime payloads from `resources/runtime/`.

## Layout

```
deepseek-harness                            the Electron binary
resources/app/                              app.getAppPath()
resources/app/dsh/                          the bundled dsh runtime
resources/app/dsh/desktop-runtime.json      runtime descriptor
resources/runtime/office-skills/            boot-required skill assets
resources/runtime/bin/node                  standalone Node for skill-office
resources/runtime/pnpm/                     pnpm CLI
resources/runtime/primary-runtime/          interpreters + Python libraries
resources/icon.png                          window/taskbar icon
```

`desktop.nix` documents the four load-bearing details of this layout, each
verified experimentally against the unmodified upstream application. In short:
the Electron binary must not be named `electron` (that name makes Electron
report `app.isPackaged === false`); the runtime belongs at
`resources/app/dsh`, not `resources/dsh`; the descriptor is checked by the
application; and `CHROME_DEVEL_SANDBOX` plus a `LD_LIBRARY_PATH` carrying
libstdc++ are required at launch.

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

Two build-time guards fail the build rather than the user's launch:

- `desktop-coverage.mjs` checks that every bare import in the packaged shell
  resolves inside `resources/app/node_modules`, and that every dependency in
  upstream's `apps/desktop-host/package.json` is linked into the bundled
  runtime. A dependency upstream adds and this package forgets is a launch-time
  `ERR_MODULE_NOT_FOUND` today; here it names the package at build time.
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
