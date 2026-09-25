# deepseek-harness-git

> [English](README.md) · 中文（简体）

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 `dsh`
agent 框架与 CLI，从上游 git 发布标签**源码构建**。与
[deepseek-harness](../deepseek-harness)（npm tarball）不同，本包追踪 `dsh-v*`
标签，因此可以提供未发布到 npm 的预发布版（如 `0.1.2-alpha.1`）。

当前版本：0.1.7-rc.2。

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

## NixOS 说明：访问 Node 内部模块加载器

运行时 profile 解析器通过预编译的 `node-addon-require-builtin` N-API 二
进制访问 Node 内部模块加载器，该二进制通过匹配已知 Node 构建的机器码来定
位 V8 的 `builtin_module_require` getter。nixpkgs 使用 GCC 编译 Node，该
getter 的代码生成与上游官方二进制不同（`ret` 前多一条 `xor edi,edi`），因
此每次 `requireBuiltin` 调用都会失败并报 `Unsupported/no-getter (x64 sysv
getter is not a recognized this->field accessor)`，启动以
`host preparation failed` 中止。

上游在 0.1.7 中移除了纯 JS 的 `link` 解析模式，原生 addon 成为唯一路径。
启动器本就传入 `--expose-internals`，该参数让同样的内部模块可直接通过普通
`require` 获取，因此构建会补丁 addon 入口
（`node-addon-require-builtin/lib/index.js`），先尝试 `require(moduleId)`，
失败再回退到原生 addon——与上游自带的 vendored Cordis 加载器
（`vendor/loader/src/internal.ts`）顺序一致。等到上游兼容 GCC 的代码生成，
或无需 addon 即可暴露该加载器后，即可从 `package.nix` 移除该
`substituteInPlace`。

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
