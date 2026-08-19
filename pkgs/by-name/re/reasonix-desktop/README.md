# reasonix-desktop

> English · [中文（简体）](README_zh_CN.md)

[Reasonix](https://github.com/esengine/DeepSeek-Reasonix) Desktop — a Wails/WebKit desktop app for DeepSeek-Reasonix.

## Maintenance notes

Current version: 1.29.0. Desktop releases use the `desktop-v<version>` tag,
and the Linux asset is named:

```sh
Reasonix-linux-amd64.tar.gz
```

When upstream releases a new version, update the `version` and `hash` in
`package.nix`. The direct download URL is:

```sh
https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v<version>/Reasonix-linux-amd64.tar.gz
```

To get the SRI-format hash:

```sh
nix store prefetch-file https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v<version>/Reasonix-linux-amd64.tar.gz
```

The hash for the `appIcon` icon may also need to be updated:

```sh
nix store prefetch-file https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v<version>/desktop/build/appicon.png
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

The desktop build depends on Wails, pnpm and WebKit/GTK to compile from source,
so this package uses the upstream-published `x86_64-linux` prebuilt binary.
