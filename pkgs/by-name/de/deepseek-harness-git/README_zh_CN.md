# deepseek-harness-git

> [English](README.md) · 中文（简体）

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 `dsh`
agent 框架与 CLI，从上游 git 发布标签**源码构建**。与
[deepseek-harness](../deepseek-harness)（npm tarball）不同，本包追踪 `dsh-v*`
标签，因此可以提供未发布到 npm 的预发布版（如 `0.1.2-alpha.1`）。

当前版本：0.1.6-alpha.1。

构建流程与上游发布工作流一致：由 `importPnpmLock` 把 vendored 的
`pnpm-lock.yaml` 转换为逐包 tarball 缓存，固定版本的 pnpm 通过本地重放
代理从该缓存安装，再执行 `pnpm run build:official`（工作区库走 tsc +
tsdown，Web 前端走 vite）。由于 `dsh` 依赖 pnpm 的相对符号链接解析约 90
个工作区包
（且配置树会引用 `../../packages/...`），整个仓库布局原样安装到
`$out/lib/deepseek-harness-git`，`bin/dsh` 以 `node --expose-internals` 包装
`apps/cli/lib/bin.js`。

产物较大（约 1.4 GB），因为 `node_modules` 中保留了开发工具链；裁剪为仅
生产依赖会破坏 pnpm 的符号链接布局保证，这里刻意不做。

## 更新

```bash
./update.sh
```

更新到指定标签版本：

```bash
./update.sh 0.1.2-alpha.1
```

脚本会解析标签（及其 commit）、预取 `srcHash`、在上游升级 `packageManager`
时刷新固定的 pnpm 版本，并从上游同步 `pnpm-lock.yaml`。不再需要探测依赖
store 的哈希：`importPnpmLock` 直接从 lockfile 的 integrity 字段推导缓存。
