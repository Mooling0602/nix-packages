# deepseek-harness-git

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — the `dsh`
agent harness and CLI — built **from source** at upstream git release tags.
Unlike [deepseek-harness](../deepseek-harness) (npm tarball), this package
tracks the `dsh-v*` tags, so it can ship pre-releases that never reach npm
(e.g. `0.1.2-alpha.1`).

Current version: 0.1.7-rc.2.

The build mirrors the upstream release workflow: `importPnpmLock` turns the
vendored `pnpm-lock.yaml` into a per-package tarball cache that the pinned pnpm
installs from through a local replay proxy, then `pnpm run build:official`
(tsc + tsdown for the workspace libraries, vite for the web frontend). Because
`dsh` resolves its
~90 workspace packages through pnpm's relative symlinks (and its config trees
reach into `../../packages/...`), the whole repository layout is installed
under `$out/lib/deepseek-harness-git` and `bin/dsh` wraps
`node --expose-internals` against `apps/cli/lib/bin.js`.

The output is large (~1.4 GB) because the dev toolchain stays in `node_modules`;
a pruned production-only install would break pnpm's symlink layout guarantees
and is intentionally not attempted.

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
plain `require`, so the build patches the addon's entry
(`node-addon-require-builtin/lib/index.js`) to try `require(moduleId)` first and
fall back to the native addon — the same order upstream's own vendored Cordis
loader uses (`vendor/loader/src/internal.ts`). Drop that `substituteInPlace`
from `package.nix` once upstream either tolerates the GCC codegen or exposes
the loader without the addon.

## Update

```bash
./update.sh
```

To update to a specific tagged version:

```bash
./update.sh 0.1.2-alpha.1
```

The script resolves the tag (and its commit), prefetches `srcHash`, refreshes
the pinned pnpm when upstream bumps `packageManager`, and syncs
`pnpm-lock.yaml` from upstream. No dependency-store hash has to be probed:
`importPnpmLock` derives the cache from the lockfile's integrity hashes.
