# qoder

> English · [中文（简体）](README_zh_CN.md)

[Qoder IDE](https://qoder.com/en/ide) — Alibaba's agentic AI coding platform. Closed-source commercial
software (`unfree`), currently only supported on `x86_64-linux`.

## Maintenance notes

Current version: 1.24.2. When a newer version is available upstream, you may
wait for this package to be updated, or open an Issue to request it.

When upstream releases a new version, update the `version` and `hash` in
`package.nix`. The direct download URL is:

```
https://download.qoder.com/release/<version>/qoder_amd64.deb
```

To get the SRI-format hash:

```sh
nix store prefetch-file https://download.qoder.com/release/<version>/qoder_amd64.deb

# or use nix-prefetch-url and convert
nix-prefetch-url https://download.qoder.com/release/<version>/qoder_amd64.deb | xargs nix hash to-sri --type sha256
```

Alternatively, run the update script. With no argument it auto-detects the
latest version from the `control` metadata of the official `latest` Debian
package; you can also specify a version manually:

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
