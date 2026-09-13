# niri-input-portal

> 中文（简体） · [English](README.md)

面向 [niri](https://github.com/YaLTeR/niri) 合成器的
`org.freedesktop.impl.portal.InputCapture` 后端，让支持 input-capture portal
的 KVM 软件（Deskflow、Synergy 3、Input Leap）能在 niri 下充当 **server**，
把这台机器的键盘、鼠标与剪贴板共享给另一台电脑。跟踪上游 `main` 分支：
`f363e34380b3f8bd9ffc9a167b7b58d3c208574b`（MIT）。

niri 暴露了 `Mutter.ScreenCast`、`Mutter.DisplayConfig` 与
`Mutter.ServiceChannel`，但没有 `Mutter.InputCapture`，因此
`xdg-desktop-portal-gnome` 永远不会发布该接口，KVM 客户端的每次
`CreateSession` 都会以 `failed to initialize input capture session` 失败。
上游在 [niri#823](https://github.com/YaLTeR/niri/issues/823) 跟踪此事
（自 2024-11 起仍 open）；本后端用 niri 确实支持的协议（`wlr-layer-shell`、
`pointer-constraints`、`relative-pointer`、`ext-data-control`）补上这个缺口。

上游没有 tag 也没有 release，本包因此跟随 `main`；升级请运行 `update.sh`。

## 本包安装的内容

| 路径 | 用途 |
|------|------|
| `bin/niri-input-portal` | 门户后端二进制 |
| `share/xdg-desktop-portal/portals/niri-input.portal` | 声明 `InputCapture` 与 `Clipboard` 两个 impl 后端 |
| `share/dbus-1/services/org.freedesktop.impl.portal.desktop.niri-input.service` | D-Bus 激活；`Exec` 已改写为 store 路径 |
| `share/systemd/user/niri-input-portal.service` | 上游的 unit，已改写为 store 路径。nixpkgs 会把它从 `lib/systemd/user` 搬到这里，而该位置在包进入 profile 后就属于 systemd 用户搜索路径。 |

## 接线方式

本包不是开箱即用的应用。`xdg-desktop-portal` 会在客户端首次请求输入捕获时
按需启动后端，因此宿主机上要同时满足三件事。

**1. 注册并路由后端。** 上游的 `install.sh` 会去写
`~/.config/xdg-desktop-portal/<desktop>-portals.conf`；声明式配置改为把包加进
`extraPortals`，并显式路由两个接口：

```nix
xdg.portal = {
  extraPortals = [ pkgs.niri-input-portal ];
  config.niri = {
    "org.freedesktop.impl.portal.InputCapture" = [ "niri-input" ];
    "org.freedesktop.impl.portal.Clipboard" = [ "niri-input" ];
  };
};
```

一旦客户端请求剪贴板共享，`Clipboard` 那行就不再是可选项。剪贴板门户会挂载
到另一个门户创建的会话上，若它落到别的后端，`RequestClipboard` 会失败，
客户端随即丢弃会话并重开一个——形成永远到不了捕获阶段的 create/destroy
循环。

**2. 提供 D-Bus 激活的 unit。** 服务文件引用了
`SystemdService=niri-input-portal.service`，因此必须有同名 unit 存在。本包已经
在 `share/systemd/user/` 下附带了一个，包进入 profile 后 systemd 就会搜索该
目录——但它带 `ConditionEnvironment=WAYLAND_DISPLAY`。若 systemd 用户实例没有
导入该变量，unit 会被静默跳过，D-Bus 会把服务名报告为不可激活。直接声明 unit
可以消除这个失败模式：

```nix
systemd.user.services.niri-input-portal = {
  Unit = {
    Description = "InputCapture portal backend for niri";
    PartOf = [ "graphical-session.target" ];
    After = [ "graphical-session.target" ];
  };
  Service = {
    Type = "dbus";
    BusName = "org.freedesktop.impl.portal.desktop.niri-input";
    ExecStart = "${pkgs.niri-input-portal}/bin/niri-input-portal";
    Restart = "on-failure";
    RestartSec = 1;
    Slice = "session.slice";
  };
};
```

该 unit 由 D-Bus 激活，因此刻意不 enable、也不 `WantedBy` 任何 target：
未使用时不常驻。

**3. 在 niri 配置里加一个逃生键绑定。** 捕获生效期间键盘被独占抓取、指针被
锁定，进程内的任何逻辑都无法自救。niri 会先于客户端处理自己的绑定，这正是
它可靠的原因：

```kdl
Mod+Shift+Escape allow-inhibiting=false { spawn "niri-input-portal" "--release"; }
```

带外逃生手段有 `niri-input-portal --release`、`--disarm` 与 `--status`；
`pkill -f niri-input-portal` 同样有效，因为客户端断开时合成器会销毁表面与
指针锁。

## 前置要求

- niri 25.11 或更新版本（上游在 25.11 与 26.04 上验证过）。
- 剪贴板共享需要 `xdg-desktop-portal` 1.21.1 或更新版本；更早的版本把剪贴板
  访问限定在 *RemoteDesktop* 会话上，会以 `Invalid session type` 拒绝请求。
- 客户端侧必须链接 `libei` 与 `libportal`。nixpkgs 的 `deskflow` 满足这点：
  1.26.0 已包含 `PortalInputCapture.cpp`，而剪贴板支持
  （`PortalClipboard.cpp`、`EiClipboard.cpp`）到上游 PR #9431 才落地，因此
  **不在** 1.26.0 中。

## 已知限制

以下由上游 README 记录，依赖捕获前值得了解：

- 布防期间，边界表面占据输出最外侧的一行或一列像素，因此恰好落在其上的点击
  会被吞掉。
- 输出的缩放与变换会被读取，但不会应用到位移增量上，所以在分数缩放的输出上
  远端指针速度不会完全一致。
- 未实现会话持久化：请求 `persist_mode` 的客户端每次都会拿到新会话。
- 认领剪贴板会丢弃其原有内容，释放时也不会恢复；不共享 primary selection。
- 若指针已停在边界上时重新布防，会立即触发捕获。

## 打包补丁

`fix-eis-device-region.patch` 让后端在 EIS 设备上报告 `ei_device.region`。

上游从不发送 region，而这是 libei 客户端唯一能用来确定"本机屏幕"尺寸的信息。
缺失时 Deskflow 退回 1×1 的屏幕模型：每次捕获激活的光标位置都被压到 `(0, 0)`，
于是只有**上边缘**能被离开——客户端配在下方或右侧时指针永远切不过去。
Deskflow core 的 stderr 会直白印出这个症状：

```
WARNING: on switch, y (11) exceeds the bottom boundary (dy + height = 1)
```

region 必须**随设备一起**、在 `ei_device.done` 之前发出：libei 在构建 device 时读取它，
之后不会再回看（协议里根本没有 region 事件），所以晚发的 region 等同于没发。因此补丁
在 `ConnectToEIS` 时先取一次输出布局，把并集交给 EIS 会话，在创建每个 device 的回调里
下发。

上游补上 region 上报后即可删除此补丁；移除条件与复查方法记在 nixos-config 的
`MAINTENANCE.md`。

## 更新

```sh
./update.sh
```

拉取 `main` 当前提交，改写 revision、version 与源码哈希，重算 vendored
crate 哈希，并验证构建。
