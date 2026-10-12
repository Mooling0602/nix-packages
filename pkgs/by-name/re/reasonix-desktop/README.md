# reasonix-desktop

> English · [中文（简体）](README_zh_CN.md)

[Reasonix](https://github.com/esengine/DeepSeek-Reasonix) Desktop — the Electron
desktop app for DeepSeek-Reasonix.

## Maintenance notes

Current version: 1.39.8. Linux assets are published under the
`desktop-v<version>` tag, and the Linux asset is named:

```sh
Reasonix-linux-amd64.tar.gz
```

### Upstream publishes several independent release lines

DeepSeek-Reasonix ships more than one product from the same repository, each
with its own tag namespace:

| Tag namespace | Product |
| --- | --- |
| `desktop-v*` | this package (1.x Electron desktop) |
| `studio-v*` | Reasonix Studio |
| `v*` | 2.x CLI |
| `npm-v*`, `dsnix-v*` | other packaging lines |

Because of this, GitHub's "latest release" (`/releases/latest`, and the
`latest` redirect on the releases page) does **not** identify the newest desktop
release — it just returns whichever line published most recently. `update.sh`
therefore discovers versions from the tag namespace instead, and never asks the
API for the latest release.

This package tracks `desktop-v*` only. Studio is a separate upstream product,
so it belongs in a separate package rather than here — even once the desktop
line stops being the most active one.

### Updating

```sh
./update.sh          # auto-detect the newest desktop version that has an asset
./update.sh <version>   # use a specific version
./update.sh -f <version>  # force, recompute the hash even if unchanged
```

With no argument the script lists `refs/tags/desktop-v*` via `git ls-remote`,
sorts them by version, and walks from newest to oldest until it finds a tag that
actually publishes `Reasonix-linux-amd64.tar.gz`, skipping at most 10 candidates.
This matters because some `desktop-v*` tags are pushed without a matching
release (for example `1.38.4`). If the target version equals the current one in
`package.nix`, the script exits without recomputing anything.

Doing it by hand instead:

```sh
nix store prefetch-file https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v<version>/Reasonix-linux-amd64.tar.gz
```

The `appIcon` hash may also need updating:

```sh
nix store prefetch-file https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v<version>/desktop/build/appicon.png
```

### Package layout

Up to `desktop-v1.38.3` the tarball was a single self-contained Wails/WebKit
binary, so installing one file was enough. Since `desktop-v1.39.0` it is an
Electron payload: `reasonix-desktop` is a small launcher that loads the shell in
the sibling `app/` directory, alongside `reasonix`, `reasonix-guard` and
`reasonix-launcher`. The whole tree is therefore installed together under
`$out/lib/reasonix-desktop` and `$out/bin/reasonix-desktop` links into it —
copying the launcher alone would produce an app that refuses to start.

The desktop build still needs pnpm and a full Electron/WebKit toolchain to
compile from source, so this package uses the upstream-published
`x86_64-linux` prebuilt tarball.
