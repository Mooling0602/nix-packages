# deepseek-harness-git

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — the `dsh`
agent harness and CLI — built **from source** at upstream git release tags.
Unlike [deepseek-harness](../deepseek-harness) (npm tarball), this package
tracks the `dsh-v*` tags, so it can ship pre-releases that never reach npm
(e.g. `0.1.2-alpha.1`).

Current version: 0.1.2-alpha.1.

The build mirrors the upstream release workflow: the pinned-pnpm offline store
from `fetchPnpmDeps`, then `pnpm run build:official` (tsc + tsdown for the
workspace libraries, vite for the web frontend). Because `dsh` resolves its
~90 workspace packages through pnpm's relative symlinks (and its config trees
reach into `../../packages/...`), the whole repository layout is installed
under `$out/lib/deepseek-harness-git` and `bin/dsh` wraps
`node --expose-internals` against `apps/cli/lib/bin.js`.

The output is large (~1.4 GB) because the dev toolchain stays in `node_modules`;
a pruned production-only install would break pnpm's symlink layout guarantees
and is intentionally not attempted.

## Update

```bash
./update.sh
```

To update to a specific tagged version:

```bash
./update.sh 0.1.2-alpha.1
```

The script resolves the tag (and its commit), prefetches `srcHash`, refreshes
the pinned pnpm when upstream bumps `packageManager`, and recomputes
`pnpmDepsHash` from a sacrificial build (the first rebuild downloads all
dependencies, so it can take a while).
