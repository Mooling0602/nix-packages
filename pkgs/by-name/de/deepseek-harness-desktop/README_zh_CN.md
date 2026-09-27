# deepseek-harness-desktop

> [English](README.md) · 中文（简体）

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的**桌面应用**形态——
即上游
[`apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/desktop)
的 Electron 外壳，重新打包以适配 Linux。上游只发布 Windows 与 macOS 安装包，
本包为 `x86_64-linux` 产出等价的运行时目录树。

当前版本：0.1.7-rc.2（跟随 [`deepseek-harness-git`](../deepseek-harness-git)）。

## 这是什么

上游的桌面端是一个 Electron 应用，其打包流水线
（`apps/desktop/scripts/`、`electron-builder`）只支持 `win-x64`、
`mac-arm64`、`mac-x64`。这个限制完全位于打包层：
`resolveDesktopBuildTarget` 会拒绝其他目标，且周边脚本会下载 Windows/macOS
专用的签名与安装器工具。应用自身的运行时代码并不含 Linux 无法满足的平台假设。

因此本包**只重做装配这一步**。它取用 `deepseek-harness-git` 已经构建好的应用
（与上游构建产出的 `lib/`、`renderer/` 及 workspace 包同一份），配上
nixpkgs 的 Electron，写出 `app.getAppPath()`/`process.resourcesPath` 期望的
资源目录树。**上游源码文件未作任何修改。**

产物行为与官方桌面版一致：启动本地 dsh 服务、打开桌面窗口，并从
`resources/runtime/` 读取同一套 skill、pnpm 与 primary-runtime 负载。

## 目录结构

```
deepseek-harness                            Electron 可执行文件
resources/app/                              app.getAppPath()
resources/app/dsh/                          内置 dsh 运行时
resources/app/dsh/desktop-runtime.json      运行时描述符
resources/runtime/office-skills/            启动必需的 skill 资源
resources/runtime/bin/node                  skill-office 用的独立 Node
resources/runtime/pnpm/                     pnpm CLI
resources/runtime/primary-runtime/          解释器与 Python 库
resources/icon.png                          窗口/任务栏图标
```

`desktop.nix` 记录了该结构的四个关键点，每一点都针对未修改的上游应用做过实测。
简要来说：Electron 可执行文件不能命名为 `electron`（该名称会让 Electron 报告
`app.isPackaged === false`）；运行时必须位于 `resources/app/dsh` 而非
`resources/dsh`；描述符会被应用校验；启动时需要 `CHROME_DEVEL_SANDBOX`，且
`LD_LIBRARY_PATH` 必须带上 libstdc++。

## 版本靠推导，而非复述

本包不硬编码任何上游版本。`version` 与 `pnpmVersion` 来自
[`../deepseek-harness-git/hashes.json`](../deepseek-harness-git/hashes.json)，
另外两项发布信息则**从本次构建装配出的目录树中读出**：

- `release.nodeVersion`——内置 Electron 报告的 `process.versions.node`。
- `release.hostProtocolVersion`——上游
  `apps/desktop/src/host-protocol.ts` 声明的生活周期协议代次。

这两项之所以重要，是因为实际随包发布的读取器（`readDesktopRuntime`，内联进
`lib/main.js`）只做类型检查，**不与任何值比对**。陈旧的值会被静默接受，因此
构建阶段拒绝猜测。

两道构建期守卫会让构建失败，而不是让用户的启动失败：

- `desktop-coverage.mjs` 校验打包后外壳里的每一个裸导入都能在
  `resources/app/node_modules` 中解析，并校验上游
  `apps/desktop-host/package.json` 中的每个依赖都已链接进内置运行时。
  上游新增而本包遗漏的依赖，如今会在构建期点名报错，而不是等到启动时报
  `ERR_MODULE_NOT_FOUND`。
- primary-runtime 清单中的 `node` 字段会与实际链接的二进制比对。

正因如此，升级版本只需运行
`pkgs/by-name/de/deepseek-harness-git/update.sh`——本包没有自己的 pin，
也不存在单独的更新步骤；它的模块清单会在构建时针对新的上游目录树被校验。

## 用法

```console
nix build .#deepseek-harness-desktop
./result/bin/deepseek-harness
```

或在 NixOS 配置中：

```nix
environment.systemPackages = [ inputs.nix-packages.packages.${pkgs.system}.deepseek-harness-desktop ];
```

## 说明与限制

- **仅 `x86_64-linux`。** 本包沿用上游 Electron 构建的桌面布局；尚未在其他系统
  上验证过装配，因此不作声明。
- **闭包体积。** 产物自身约 384 MB（其中 Electron 二进制约 258 MB）。运行时它会复用
  `deepseek-harness-git` 的 store 目录树来承载内置 dsh 负载，因此两个包共享同一份
  应用，而非各自复制。
- **自动更新不生效。** 上游桌面构建包含 `electron-updater`，但由 Nix 管理的安装
  永远不会被它更新——升级一律走 `nix`。该 updater 存在仅因为应用会无条件导入它。
- **与 DeepSeek 无隶属关系。** 这是下游的重新打包。
