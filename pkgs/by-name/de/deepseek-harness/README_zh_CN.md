# deepseek-harness

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 `dsh`
agent 框架与 CLI，以官方 npm tarball 打包，并使用固定的依赖锁文件。

当前版本：0.1.0-rc.8。

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

更新脚本会重新生成 `package-lock.json`、预取新的 `sourceHash`，并重新计算
`npmDepsHash`（首次重建会下载全部依赖，因此可能需要较长时间）。
