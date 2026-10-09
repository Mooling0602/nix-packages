# deepseek-harness-desktop

> [English](README.md) · 中文（简体）

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的**桌面应用**形态——
即上游
[`apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/desktop)
的 Electron 外壳，重新打包以适配 Linux。上游只发布 Windows 与 macOS 安装包，
本包为 `x86_64-linux` 产出等价的运行时目录树。

当前版本：0.2.0-rc.2（跟随 [`deepseek-harness-git`](../deepseek-harness-git)）。

## 这是什么

上游的桌面端是一个 Electron 应用，其打包流水线
（`apps/desktop/scripts/`、`electron-builder`）只支持 `win-x64`、
`mac-arm64`、`mac-x64`。这个限制完全位于打包层：
`resolveDesktopBuildTarget` 会拒绝其他目标，且周边脚本会下载 Windows/macOS
专用的签名与安装器工具。应用自身的运行时代码并不含 Linux 无法满足的平台假设。

因此本包**只重做装配这一步**。它取用 `deepseek-harness-git` 已经构建好的应用
（与上游构建产出的 `lib/`、`renderer/` 及 workspace 包同一份），配上
nixpkgs 的 Electron，写出 `app.getAppPath()`/`process.resourcesPath` 期望的
资源目录树。上游源码文件完全不动、也不重新编译；唯一被改写的文件是打包后的
主进程 `resources/app/lib/main.js`，安装阶段给它打上四处最小的 Linux 补丁
（见下节）。

产物行为与官方桌面版一致：启动本地 dsh 服务、打开桌面窗口，并从
`resources/runtime/` 读取同一套 skill、pnpm 与 primary-runtime 负载。

## 桌面集成（Linux）

上游把若干桌面行为限定在 `win32`，另有一处 Linux 缺口借鉴了下游修复。
四者都是由 `desktop-shell-patch.mjs` 打进 `lib/main.js` 的小补丁——每个锚点
都验证过在 bundle 中恰好出现一次，上游升级若挪动了这些代码，构建会直接失败，
而不是发出一个半成品外壳：

- **托盘图标。** 关闭窗口本来就只是隐藏（页面与 Host 继续运行），但上游只在
  Windows 创建托盘——那正是把窗口叫回来的入口。现在 Linux 获得同一个
  `DesktopTray`：单击重新打开窗口，右键菜单提供「打开/退出」，首次关闭时弹
  一次性提示「正在运行的任务不会中断，可在系统托盘中重新打开窗口」（上游为
  Windows 写的原话）再隐藏。图标走 StatusNotifierItem 注册，与 Linux 上所有
  Electron 托盘一样，不涉及额外系统库。GNOME 下需要 AppIndicator 扩展才显示
  图标（所有 SNI 应用皆然）。
- **桌面通知。** Electron 在 Linux 上通过 `libnotify` 发通知，运行时按 soname
  dlopen；找不到库时只打一行
  `Unable to find libnotify; notifications disabled` 就把通知静默关掉。
  因此启动器把 `libnotify` 放进 `LD_LIBRARY_PATH`，构建期还会以内置二进制
  自身的解析路径探测同样的 dlopen——通知链路不会无声退化。通知遵循
  FreeDesktop 桌面通知规范，需要桌面通知守护进程（主流桌面环境均自带）。
- **隐藏菜单栏。** Linux 下应用菜单会以菜单栏形式出现在每个窗口。
  `DSH_DESKTOP_HIDE_MENUBAR=1`（默认）把它隐藏但不移除菜单，快捷键
  （编辑菜单、F12 开发者工具）照常可用；`DSH_DESKTOP_HIDE_MENUBAR=0` 恢复
  显示。上游没有提供任何控制方式，故采用该环境变量。
- **信号优雅退出。** `SIGINT`/`SIGTERM` 现在走外壳自身的清理流程退出，且
  Host 以独立进程组启动，终端信号只作用于外壳——改编自
  [Moraxyc/deepseek-harness.nix 的 `desktop-signal-shutdown.patch`](https://github.com/Moraxyc/deepseek-harness.nix/commit/c9999f47789aa77f21366571c8f05449cd671f49)，
  待上游处理 Linux 终端信号后即可移除。

### 桌面身份

任务栏靠**名字**把窗口和它的图标对上，而这个名字有四种写法必须一致：
Wayland 的 `app_id`、X11 的 `WM_CLASS`、`.desktop` 文件名以及该条目里的
`StartupWMClass`。前两者不由本包决定——Electron 从应用清单推导
（`packageJson.desktopName`，没有则把 `app.name` 转成短横线小写 slug），
窗口照它自己的结果上报，与本包装了什么无关。此前窗口报的是
`deepseek-ai-dsh-desktop`（源自私有包名 `@deepseek-ai/dsh-desktop`），而条目
却装成 `deepseek-harness.desktop`，两者对不上，Wayland 任务栏于是退回通用图标。

现在条目按 Electron 实际上报的 id 命名，`StartupWMClass` 也改用同一个值，而不是
产品名。`desktop-identity.mjs` 会在构建期用 Electron 自身的算法从随包的应用清单
重新推导该 id，并比对文件名、`StartupWMClass` 与 `Icon=`；上游若改了那个私有包名，
构建会直接失败并同时列出两侧的值，而不是让每个窗口静默失配。

图标也按同一身份安装，既包含窗口与托盘使用的位图，也包含上游提供的矢量原件。

## 目录结构

```
deepseek-harness                            Electron 可执行文件
resources/app/                              app.getAppPath()
resources/app/dsh/                          内置 dsh 运行时
resources/app/dsh/desktop-runtime.json      运行时描述符
resources/runtime/office-skills/            启动必需的 skill 资源
resources/runtime/bin/node                  skill-office 用的独立 Node
resources/runtime/primary-runtime/          解释器与 Python 库
resources/runtime/primary-runtime/dependencies/pnpm/
                                            pnpm CLI
resources/icon.png                          窗口/任务栏图标
```

`desktop.nix` 记录了该结构的六个关键点，每一点都针对未修改的上游应用做过实测。
简要来说：Electron 可执行文件不能命名为 `electron`（该名称会让 Electron 报告
`app.isPackaged === false`）；运行时必须位于 `resources/app/dsh` 而非
`resources/dsh`；描述符会被应用校验；启动时需要 `CHROME_DEVEL_SANDBOX`，且
`LD_LIBRARY_PATH` 必须带上 libstdc++；sharp 的原生插件需要动态链接的 libvips，
本包按插件指定的名字替换了一份——预编译的那份静态内嵌了自己的 glib，会让 Host
发生段错误；pnpm 必须位于 primary-runtime 负载**内部**，因为三个读取方都按绝对
路径解析它，且都不做查找。

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

构建期会做七项检查，而不是留到用户的启动阶段才发现问题：

- `desktop-coverage.mjs` 校验打包后外壳里的每一个裸导入都能在
  `resources/app/node_modules` 中解析，并校验上游
  `apps/desktop-host/package.json` 中的每个依赖都已链接进内置运行时。
  上游新增而本包遗漏的依赖，如今会在构建期点名报错，而不是等到启动时报
  `ERR_MODULE_NOT_FOUND`。
- `desktop-shell-patch.mjs` 只接受与锚点完全一致的替换，并对改写后的 bundle
  做语法检查；上游升级若挪动了被打补丁的代码，构建会点名是哪一处补丁失败。
- `desktop-identity.mjs` 从随包的应用清单重新推导桌面 id，条目文件名、
  `StartupWMClass` 或图标与之不符就拒绝该产物，Wayland 窗口不会无声地失去图标。
- `desktop-inspector-worker.mjs` 从随包的运行时中读出实验性 Inspector 的 Worker
  创建点，要求它带上 `--expose-internals`，然后用这个 `execArgv` 在当前构建的
  Electron 里真拉起一个 Worker。该 Worker 的首个导入会经预编译的
  `node-addon-require-builtin` 抵达 Node 的内部模块加载器，而这个二进制的
  Electron 运行时指纹是 nixpkgs 的 Electron 永不具备的——所以这里一旦回归，
  表现就是开发者模式下插件激活失败，构建期之外没有任何地方会发现。
- `desktop-runtime-pnpm.mjs` 从两个随包 bundle 中读出 pnpm 入口路径，把 Host 的
  supportDir 钉在外壳自己的 Node 启动器目录上，并关联到 primary-runtime 负载根，
  再用打包好的 launcher 真正执行该入口。pnpm 只在安装、更新或卸载插件时才被触达，
  因此这条路径一旦被挪动，表现就是点名插件的 `MODULE_NOT_FOUND`。
- 通知探针以内置二进制自身的搜索路径 dlopen `libnotify`（即 Electron 通知
  后端使用的解析方式），通知栈被静默禁用会让构建失败。
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
