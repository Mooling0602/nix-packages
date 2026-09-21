# deepseek-harness

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 `dsh`
agent 框架与 CLI，以官方 npm tarball 打包，并使用固定的依赖锁文件。

当前版本：0.1.6-alpha.2。

本包通过 `buildNpmPackage` 构建：拉取 `@deepseek-ai/dsh` tarball，注入随附的
`package-lock.json`，最终生成 `dsh` 启动器。安装后的 `dsh` 入口包装了
`node --expose-internals`。

## 更新

```bash
./update.sh
```

更新到指定版本：

```bash
./update.sh 0.1.0-rc.6
```

更新到某个 npm dist-tag（如 `latest`、`next`、`alpha`）指向的版本：

```bash
./update.sh -t alpha
```

更新脚本会重新生成随附的 `package-lock.json`、预取新的 `sourceHash`。
无需探测依赖哈希：`importNpmLock` 直接从 lockfile 推导依赖集合。
