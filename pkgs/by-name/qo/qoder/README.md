# qoder

> English · [中文（简体）](README_zh_CN.md)

[Qoder](https://qoder.com/en/qoder) — Agent workbench for human and AI software teams. It's a
closed-source commercial software (`unfree`), and currently only supported on `x86_64-linux`.

Upstream split Qoder into separate products: this package installs the standalone **Qoder app**
only. The IDE is packaged separately as
[`qoder-ide`](../qoder-ide/README.md); the standalone `qoder` CLI is not included either.

## Notes

The app is launched with `--no-sandbox`. Its bundled Chromium sandbox helper
(`chrome-sandbox`) requires setuid root, which the Nix store cannot provide, and
user namespaces alone are not enough for it to work as shipped.

The app self-updates through `electron-updater`. That will not work from the
Nix store, so updates go through this package instead.

The app ignores Electron's Wayland-mode related settings and falls back to X11.
To avoid this, set the `QODER_OZONE_PLATFORM=wayland` environment variable to run
the app in native Wayland mode.

## Maintenance notes

Current version: 0.4.2. When a newer version is available upstream, you may
wait for this package to be updated, or open an Issue to request it.

When upstream releases a new version, update the `version` and `hash` in
`package.nix`. The direct download URL is:

```
https://download.qoder.com/qoder-app/releases/<version>/Qoder-linux-amd64.deb
```

Note that the Debian `control` metadata carries a Debian epoch
(`Version: 1:0.2.5`), while the release path and `package.nix` use the bare
`0.2.5` without it.

To get the SRI-format hash:

```sh
nix store prefetch-file https://download.qoder.com/qoder-app/releases/<version>/Qoder-linux-amd64.deb

# or use nix-prefetch-url and convert
nix-prefetch-url https://download.qoder.com/qoder-app/releases/<version>/Qoder-linux-amd64.deb | nix hash to-sri --type sha256
```

Alternatively, run the update script. With no argument it auto-detects the
latest version by cross-checking two sources and taking the newer one: the
changelog page ([qoder.com/zh/changelog?type=app](https://qoder.com/zh/changelog?type=app),
whose embedded JSON lists every release) and the `control` metadata of the
official `qoder-app/releases/latest/Qoder-linux-amd64.deb`. Both are checked
because the `latest` download alias can lag behind and would otherwise make the
script report "already up to date" for an outdated package. You can also specify
a version manually:

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

If the target version matches the current version in `package.nix`, the script
exits without recomputing the hash. Using `-f` or `--force` requires a version
and forces the hash to be recomputed.
