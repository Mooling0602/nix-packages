# openfic

> English · [中文（简体）](README_zh_CN.md)

[OpenFic](https://github.com/syrizelink/OpenFic) — a cross-platform,
user-friendly, AI-native, all-in-one writing tool designed for novel writing.
Open source (Apache-2.0), packaged from the upstream `x86_64-linux` prebuilt
release.

## Why an FHS wrapper?

The Linux desktop build is an electron-builder distribution, but the Python
backend is **not** bundled: on first launch the app downloads a
[python-build-standalone](https://github.com/astral-sh/python-build-standalone)
CPython from GitHub and installs the `openfic` backend from PyPI into a venv
under its data directory. Those runtime-downloaded ELF binaries expect an FHS
layout (`/lib64/ld-linux-x86-64.so.2`), which does not exist on NixOS, so this
package wraps the app in a bubblewrap FHS environment (`buildFHSEnv`) to make
the whole runtime work out of the box.

Side effects of the FHS approach:

- Chromium's setuid sandbox is unavailable, so the app is launched with
  `--no-sandbox`.
- The first launch needs network access (GitHub + PyPI) to provision the
  backend runtime.

## Maintenance notes

Current version: 0.11.0. Upstream releases use the `v<version>` tag, and the
Linux x86_64 asset is named:

```sh
OpenFic-<version>-linux-x86_64.tar.gz
```

When upstream releases a new version, update the `version` and `hash` in
`package.nix`. The direct download URL is:

```sh
https://github.com/syrizelink/OpenFic/releases/download/v<version>/OpenFic-<version>-linux-x86_64.tar.gz
```

To get the SRI-format hash:

```sh
nix store prefetch-file https://github.com/syrizelink/OpenFic/releases/download/v<version>/OpenFic-<version>-linux-x86_64.tar.gz
```

Alternatively, run the update script. With no argument it auto-detects the
latest version from the GitHub API; you can also specify a version manually:

```sh
./update.sh
./update.sh <version>
./update.sh -f <version>
```

If the target version matches the current version in `package.nix`, the script
exits without recomputing the hash. Using `-f` or `--force` requires a version
and forces the hash to be recomputed.
