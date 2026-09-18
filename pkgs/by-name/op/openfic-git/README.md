# openfic-git

> English · [中文（简体）](README_zh_CN.md)

OpenFic desktop app built from source (upstream `main` branch), packaged with
nixpkgs Electron instead of the prebuilt electron-builder tarball. Following
upstream main at `afb02649081140fb70e80dca2fe7b1fc108f95b4`.

The sibling `openfic` package wraps the upstream release tarball in a bubblewrap
FHS environment; this one is a plain source build with no FHS sandbox. Do not
install both at once — they share the same Electron app name and desktop
identity.

## Requirements

- **nix-ld** must be enabled on the host (`programs.nix-ld.enable = true`).
  At first launch the app downloads its Python backend (python-build-standalone
  CPython + `openfic` PyPI wheels, ~1.2 GB) into
  `~/.config/openfic-desktop/runtime`. Those are unpatched FHS binaries; nix-ld
  runs them without an FHS sandbox. Without nix-ld the local backend cannot
  start (remote instance mode still works).

## Build notes

- `frontend/` and `desktop/` are separate pnpm projects; their lockfiles are
  vendored and parsed by `importPnpmLock`, which turns the integrity hashes
  into a per-package tarball cache. `pnpm install` fetches through a local
  replay proxy, so the build is reproducible without an aggregate
  dependency-store hash.
- The vendored lockfiles are synced from the pinned upstream revision by
  `update.sh`; `--frozen-lockfile` fails the build if they ever drift.
- The exact pnpm version pinned by upstream's `packageManager` field is
  embedded as an npm tarball because nixpkgs' pnpm is too new to accept the
  upstream lockfiles.
- The app runs in Electron's non-packaged mode: the desktop entry is executed
  through `electron <share/openfic/desktop>` and the frontend is resolved from
  the sibling `../frontend/dist` directory, matching upstream's dev layout.
- Auto-update is disabled automatically in non-packaged mode; update by
  re-running `update.sh`.

## Update

```sh
./update.sh
```

Fetches the latest `main` commit, syncs both pnpm lockfiles, refreshes the
source and embedded-pnpm hashes, and verifies the flake still evaluates.
