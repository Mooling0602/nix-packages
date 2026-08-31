# openfic-git

OpenFic desktop app built from source (upstream `main` branch), packaged with
nixpkgs Electron instead of the prebuilt electron-builder tarball. Following
upstream main at `dcccb8390007564fe55189ed40653b9f24ccd798`.

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

- `frontend/` and `desktop/` are separate pnpm projects; dependencies are
  prefetched into a fixed-output store derivation, and the build reproduces it
  offline (`--offline`, `--ignore-scripts`).
- The exact pnpm version pinned by upstream's `packageManager` field is
  embedded as an npm tarball because nixpkgs' pnpm is too new to consume the
  lockfiles offline.
- The app runs in Electron's non-packaged mode: the desktop entry is executed
  through `electron <share/openfic/desktop>` and the frontend is resolved from
  the sibling `../frontend/dist` directory, matching upstream's dev layout.
- Auto-update is disabled automatically in non-packaged mode; update by
  re-running `update.sh`.

## Update

```sh
./update.sh
```

Fetches the latest `main` commit, refreshes all three hashes (source, embedded
pnpm, dependency store) and verifies the build.
