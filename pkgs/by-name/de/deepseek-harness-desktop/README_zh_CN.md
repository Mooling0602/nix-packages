# deepseek-harness-desktop

> [English](README.md) · 中文（简体）

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的**桌面应用**形态——
即上游
[`apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/desktop)
的 Electron 外壳，重新打包以适配 Linux。上游只发布 Windows 与 macOS 安装包，
本包为 `x86_64-linux` 产出等价的运行时目录树。

当前版本：0.2.1-rc.2（跟随 [`deepseek-harness-git`](../deepseek-harness-git)）。

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
主进程 `resources/app/lib/main.js`，安装阶段给它打上几处最小的 Linux 补丁：
四处 shell 行为由 `desktop-shell-patch.mjs` 应用，两处窗口毛玻璃由
`desktop-window-glass.mjs` 应用，三处菜单本地化由 `desktop-menu-locale.mjs`
应用（见下文）。

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

### 窗口毛玻璃

上游只为 macOS 窗口提供半透明、背景模糊的材质（`vibrancy: "sidebar"` 加一个
全透明的 `backgroundColor`），并配上前端在 `html[data-platform=darwin]` 下
清除文档背景的规则，以及 preload 用 `process.platform` 标记文档根。Linux 通过
`desktop-window-glass.mjs` 获得同样的两半，这正是让合成器的模糊得以透出来的
条件：

- 主窗口以 `transparent: true` 加全透明 `backgroundColor` 创建，是紧邻其后的
  darwin 分支在 Linux 上的对应物。Electron 在 Linux 上没有 vibrancy，也没有
  `backgroundMaterial`；而缺少 `transparent` 时它交给合成器的是不透明表面，
  页面再怎么调样式也透不出来。
- bundle 自己 `serveWebDocument()` 送出的文档会被注入一段样式表，承载前端为
  darwin 发布的那批规则在 Linux 上的对应物。要让背景透出来，得先请五个表面
  让开：`html` 与 `body` 的背景、frame 元素（换成它自身 `--dsw-alias-bg-base`
  的 72% 着色，好让文字在模糊壁纸上依旧清晰）、侧边栏列以及其内层表面消费的
  `--dsw-specific-sidebar-fill` 令牌、对话根节点，以及输入框座位。少清任何一个
  都足以把模糊盖住，因为一层不透明表面就能挡住其余全部。内容自身的背景保持
  不变，卡片与面板仍然清晰可读，毛玻璃从界面四周显现。

  输入框座位是唯一一个「清掉」而非「换色」的表面，值得单独说明。上游为了让滚动
  中的正文在输入卡片下方淡出，用固定的 36px 渐隐到实心 `--dsw-alias-bg-base`；
  在 darwin 上这层填充不可见，因为底下那一列本来就是同色，但在被清空的列上它就
  成了卡片周围的一块不透明底。换成半透明着色只是把黑带变成灰带；改用带遮罩的
  `backdrop-filter` 更糟：在透明窗口上 Chromium 会把窗口自身的透明当作不透明黑
  来采样，于是那条带渲染成一片糊开的黑色晕影。因此这里直接把座位清空。原本靠
  填充挡住的正文，改由卡片自己挡住：卡片比正文列更宽
  （`--dsh-composer-card-max-width` 等于 `--dsh-chat-content-width` 加上两侧留白），
  且自带不透明的 `--dsw-specific-input-major` 背景。

  这些规则全靠特异度生效，全程没有一处 `!important`，并避开构建产生的哈希
  类名：写死哈希经不起上游升级。运行中的窗口上，仍然完全不透明的像素只出现在
  内容卡片和输入卡片自身。`prefers-reduced-transparency: reduce` 会把 frame 与
  座位一并恢复为不透明，与上游自带的回退一致。

前端 dist 中的文件一律不改写。它们是上游构建产物、文件名带内容哈希，改它们比
注入更脆；而注入点（外壳自己的文档处理器，上游已经用同一手法往同一个
`<head>` 里注入启动脚本）无论前端从哪里加载都会被走到。注入的规则在构造上对
其他页面无效：只有应用窗口的 preload 会调用 `markDocumentPlatform()`，因此
`dsh-app://shell/*` 提供的渲染页（欢迎页、更新对话框、强制更新页）永远不会命中
该选择器，继续保留各自的不透明背景。

模糊本身由合成器负责，因此需要在合成器侧有一条窗口规则，且 niri 默认不开
`blur`，必须有规则显式打开。是否还需要做什么，取决于**会话实际加载的**那份配置：
只要其中已有针对所有窗口（或针对本应用 app id）开启该效果的规则即可，这种情况下
本包无需任何额外配置。

动手改之前，先确认运行中的会话到底读的是哪个文件。niri 从环境变量 `NIRI_CONFIG`
取值，它不一定是 `~/.config/niri/config.kdl`：

```console
$ tr '\0' '\n' < /proc/$(pgrep -x niri)/environ | grep NIRI_CONFIG
NIRI_CONFIG=/home/user/.config/niri-some-flavour/config.kdl
```

若该文件（或它 include 进来的文件）已有带 `blur true` 且**不带 `match`**（即匹配
所有窗口）的 `background-effect` 块，窗口就已经是毛玻璃，无需再配置。否则向该文件
添加下面这条规则；本包针对 [niri](https://github.com/YaLTeR/niri) 26.04 及更新版本
编写（即它的 `ext-background-effect` 支持与 `background-effect` 窗口规则）：

```kdl
window-rule {
    match app-id=r#"^deepseek-ai-dsh-desktop$"#
    background-effect {
        blur true
    }
}
```

其中的 app id 就是 Electron 从上游应用清单推导出的那个，也正是
`desktop-identity.mjs` 所校验、安装的 `.desktop` 条目里 `StartupWMClass` 所携带
的值（见下节「桌面身份」）。若合成器没有该规则，窗口就只是透明：壁纸未经模糊
直接透过页面底色，其上的文字可能损失对比度。要彻底关掉该效果，去掉规则即可，
或者构建时跳过第 2b 步。

窗口本身保持 `frame: true`：niri 以服务端装饰接管圆角、边框与焦点环
（`prefer-no-csd`、`clip-to-geometry`、`draw-border-with-background false`），
客户端不需要也不应该绘制装饰或自备拖拽区域。

### 菜单本地化

外壳自带 `en` 与 `zh` 两套消息表，并把多数菜单项都建在
`currentDesktopLocale().messages` 之上；但有三种菜单项交给了 Electron 自己填，
在 Linux 上它们一律显示英文。`desktop-menu-locale.mjs` 负责把它们本地化，且
补丁里从头到尾没有写死任何中文字符串：

- **编辑菜单。** 非 macOS 平台用 `{ role: "editMenu" }` 让 Electron 填充
  撤销/重做/剪切/复制/粘贴/删除/全选。Linux 上 Electron 无论系统语言是什么都
  用英文渲染这些 role 的标签——`zh-CN` 桌面上的菜单就从「应用」旁边冒出
  `Edit`/`Undo`/`Cut`/`Select All`。补丁把这一项逐条列出，**保留 role**、只把
  `label` 换成消息表里的值；保留 role 正是为了不改变行为与默认快捷键，变的只有
  文字。
- **右键菜单。** 上下文菜单模板本来就会把 `role` 映射成
  `messages[item.role]`，但开启该分支的条件写的是 `win32`。现在条件覆盖所有
  非 macOS 平台，Linux 上的 `复制`/`粘贴`/`全选` 也随之跟随外壳语言。
- **退出项。** 应用菜单的退出项在 macOS 上取 `quitApplication`、Windows 上取
  `exitApplication`，Linux 则是空的 `{}`。现在 Linux 拿到 `quitApplication`
  ——「退出 DeepSeek Harness」，与 macOS 的同一项一致，而不是裸露的 `quit`
  （「退出」）。

英文会话解析到 `en` 表，因此显示的必然是 `Edit`/`Undo`/`Copy`/
`Quit DeepSeek Harness`，不存在显示中文的可能。标签在构建模板的函数内部读取，
而 `platformMenus()` 每次调用都会重建模板、`refreshApplicationMenu()` 会在启动、
已存语言偏好加载完成以及收到 `localeChanged` IPC 时运行——所以切换语言会重新
贴标签，而不是把上一种语言留在原地。macOS 不做改动：原生菜单由 AppKit 自己
本地化，补丁只动非 macOS 分支。

启动器条目是唯一在消息表之外的部分，因此在 `.desktop` 文件里单独本地化：
`Comment[zh_CN]` 提供中文简介，其它语言的桌面回落到 `Comment=`。`Name=` 无需
变体——外壳自己的消息表里产品名同样不翻译。

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

```plaintext
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

构建期会做九项检查，而不是留到用户的启动阶段才发现问题：

- `desktop-coverage.mjs` 校验打包后外壳里的每一个裸导入都能在
  `resources/app/node_modules` 中解析，并校验上游
  `apps/desktop-host/package.json` 中的每个依赖都已链接进内置运行时。
  上游新增而本包遗漏的依赖，如今会在构建期点名报错，而不是等到启动时报
  `ERR_MODULE_NOT_FOUND`。
- `desktop-shell-patch.mjs` 只接受与锚点完全一致的替换，并对改写后的 bundle
  做语法检查；上游升级若挪动了被打补丁的代码，构建会点名是哪一处补丁失败。
- `desktop-window-glass.mjs` 让两处窗口毛玻璃补丁遵守同一套纪律：锚点不再恰好
  出现一次就点名失败，改写后的 bundle 会再被语法检查一次。
- `desktop-menu-locale.mjs` 对三处菜单本地化补丁做同样的检查。这里的锚点校验
  同时也是「英文用户不会看到中文」的保障：标签只从外壳自带的消息表里读取，
  所以锚点一旦挪位就是构建失败，而不会留下一句话写死的字符串。
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
该脚本同时会同步本文件顶部那行 `当前版本：`，除此之外不再动本包的任何文件。

本包中有一些版本号是**记录下来的证据**而非 pin，更新脚本故意不碰它们：

- 每个补丁最后一次人工核对时所在的 bundle 版本，位于
  `desktop-shell-patch.mjs`（当前为 `0.2.1-rc.2`）、
  `desktop-window-glass.mjs`（当前为 `0.2.1-alpha.4`）与
  `desktop-menu-locale.mjs`（当前为 `0.2.1-rc.2`）的文件头。它们是**证据**
  而非 pin：锚点是否仍然有效，由构建针对每一棵新目录树重新检查，所以停在那儿
  的数字是诚实的——它说明补丁最后一次被肉眼审视是在哪个 bundle 上。自动改写它
  等于声称做过一次并未发生的复核。
- `desktop.nix` 第 5 条注释里的 Electron、Node 与 libvips 版本。sharp 的崩溃是在
  那几个确切构建上测出来的；正是这些数字让这段注释可以被核对，而版本升级不会
  改变其中任何一项测量结果。

需要改动时请手动修改，并且只在真的重新核对过锚点、或在新版本上重跑过 sharp
探针之后。

## 用法

```console
nix build .#deepseek-harness-desktop
./result/bin/deepseek-harness
```

或在 NixOS 配置中：

```nix
environment.systemPackages = [
  inputs.nix-packages.packages.${pkgs.system}.deepseek-harness-desktop
];
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
