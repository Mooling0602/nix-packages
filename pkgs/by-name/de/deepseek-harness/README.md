# deepseek-harness

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — the `dsh`
agent harness and CLI — packaged from the official npm tarball with a pinned
dependency lockfile.

Current version: 0.1.7-rc.2.

The package is built with `buildNpmPackage`: it pulls the `@deepseek-ai/dsh`
tarball, injects the vendored `package-lock.json`, and produces the `dsh`
launcher. The installed `dsh` entry point wraps `node --expose-internals`.

## Update

```bash
./update.sh
```

To update to a specific version:

```bash
./update.sh 0.1.0-rc.6
```

To update to whatever an npm dist-tag (e.g. `latest`, `next`, `alpha`) points
to:

```bash
./update.sh -t alpha
```

The update script regenerates the vendored `package-lock.json` and prefetches
the new `sourceHash`. No dependency hash has to be probed: `importNpmLock`
derives the dependency set from the lockfile.

## NixOS note: internal module loader access

The runtime profile resolver drives Node's internal module loader through the
prebuilt `node-addon-require-builtin` N-API binary, which locates V8's
`builtin_module_require` getter by pattern-matching the machine code of a known
Node build. nixpkgs compiles Node with GCC, whose codegen for that getter
differs from the upstream release binaries (an extra `xor edi,edi` before
`ret`), so every `requireBuiltin` call fails with `Unsupported/no-getter (x64
sysv getter is not a recognized this->field accessor)` and boot aborts with
`host preparation failed`.

Upstream removed the pure-JS `link` resolution mode in 0.1.7, leaving the
native addon as the only path. The launcher already passes
`--expose-internals`, which exposes the very same internal modules through a
plain `require`, so `postInstall` patches the addon's entry
(`node-addon-require-builtin/lib/index.js`) to try `require(moduleId)` first and
fall back to the native addon — the same order upstream's own vendored Cordis
loader uses (`vendor/loader/src/internal.ts`). Drop that `substituteInPlace`
from `package.nix` once upstream either tolerates the GCC codegen or exposes
the loader without the addon.
