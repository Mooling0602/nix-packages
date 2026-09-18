# qoder-ide

> English · [中文（简体）](README_zh_CN.md)

[Qoder IDE](https://qoder.com/en/ide) — Agentic IDE for Real Software. It's a closed-source commercial
software (`unfree`), and currently only supported on `x86_64-linux`.

Upstream split Qoder into separate products: this package installs **Qoder IDE**
only. The standalone Qoder app and the standalone `qoder` CLI are not included;
the IDE's own CLI bridge is available as `$out/share/qoder-ide/bin/qoder`.

## Maintenance notes

Current version: 1.30.1. When a newer version is available upstream, you may
wait for this package to be updated, or open an Issue to request it.

When upstream releases a new version, update the `version` and `hash` in
`package.nix`. The direct download URL is:

```
https://download.qoder.com/release/<version>/qoder-ide_amd64.deb
```

Before 1.25.1 the IDE was published as `qoder_amd64.deb` under the same
`release/<version>/` path. That filename changed with the product rename and is
no longer published, also no longer supported by this packaging repository; the old `release/latest/qoder_amd64.deb` URL still responds
but is frozen at the pre-rename 1.24.2 build.

To get the SRI-format hash:

```sh
nix store prefetch-file https://download.qoder.com/release/<version>/qoder-ide_amd64.deb

# or use nix-prefetch-url and convert
nix-prefetch-url https://download.qoder.com/release/<version>/qoder-ide_amd64.deb | xargs nix hash to-sri --type sha256
```

Alternatively, run the update script. With no argument it auto-detects the
latest version from the `control` metadata of the official
`release/latest/qoder-ide_amd64.deb`; you can also specify a version manually:

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

If the target version matches the current version in `package.nix`, the script
exits without recomputing the hash. Using `-f` or `--force` requires a version
and forces the hash to be recomputed.

## References

This package is based on the unofficial packaging from
[boheastill/qoder-nix](https://github.com/boheastill/qoder-nix).
