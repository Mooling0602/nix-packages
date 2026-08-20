# deepseek-harness

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — the `dsh`
agent harness and CLI — packaged from the official npm tarball with a pinned
dependency lockfile.

Current version: 0.1.0-rc.8.

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

The update script regenerates `package-lock.json`, prefetches the new
`sourceHash`, and recomputes `npmDepsHash` (the first rebuild downloads all
dependencies, so it can take a while).
