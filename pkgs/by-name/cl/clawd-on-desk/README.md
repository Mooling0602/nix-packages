# clawd-on-desk

> English · [中文（简体）](README_zh_CN.md)

[Clawd on Desk](https://github.com/rullerzhou-afk/clawd-on-desk) — a desktop companion pet that reacts to AI coding assistant
sessions in real time.

## Maintenance notes

Current version: 0.16.0. When upstream releases a new version, update the
`version` and `hash` in `package.nix`. The Linux asset is named:

```sh
Clawd-on-Desk-<version>-amd64.deb
```

The direct download URL is:

```sh
https://github.com/rullerzhou-afk/clawd-on-desk/releases/download/v<version>/Clawd-on-Desk-<version>-amd64.deb
```

To get the SRI-format hash:

```sh
nix store prefetch-file https://github.com/rullerzhou-afk/clawd-on-desk/releases/download/v<version>/Clawd-on-Desk-<version>-amd64.deb
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

This package uses the upstream-published `x86_64-linux` prebuilt Debian package.
