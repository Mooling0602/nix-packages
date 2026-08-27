# axolotl-launcher-bin

> 中文（简体） · [English](README.md)

[Axolotl Launcher](https://github.com/Mystic-Stars/Axolotl)（美西螈启动器），一款基于 Modrinth 生态构建的自由跨平台 Minecraft 启动器，打包自官方 Linux `.deb`。

当前版本：1.9.0。

## FHS 环境

启动器被包装在 bubblewrap FHS 沙箱（`buildFHSEnv`）中。Minecraft 启动器会下载
假定标准 Linux 文件系统布局的预编译 Java 运行时和本地库，而 Mod 也经常自带
链接发行版 soname 的本地库。在沙箱内，这些二进制——启动器本身、自动下载的
JRE、LWJGL natives 以及 Mod 提供的 `.so` 文件——都能通过 `/usr/lib` 和
ldconfig 缓存解析依赖，因此在 NixOS 上依赖繁重的 Mod 也能正常启动。

沙箱内置了完整的 Minecraft 运行时栈（对齐
[prismlauncher](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/pr/prismlauncher/package.nix)
的清单）：音频服务（alsa、pulseaudio、pipewire、jack）、X11/Wayland 客户端
库、GL/Vulkan 加载器、udev（oshi）、flite（朗读）、gamemode、libusb（手柄），
以及 Minecraft 会调用的 `pciutils`/`xrandr` 辅助工具。另有一个 `jdk21` 兜底，
暴露为 `/usr/bin/java`；启动器仍会为每个实例自动下载所需的 JRE（已在沙箱内
验证可用）。GPU 驱动来自宿主机的 `/run/opengl-driver`，它被 bind-mount 进
沙箱并在库路径中享有最高优先级。

GUI 继续使用沙箱 `/usr/lib` 中的 GTK3/WebKitGTK，dconf、GIO 模块（TLS、
GSettings）与 GStreamer 插件均已接好，主题与媒体播放行为与之前一致。

## 显示后端

包装脚本会自动检测显示协议（Wayland 会话下设 `GDK_BACKEND=wayland`，否则
`x11`）。可在启动前导出 `GDK_BACKEND` 覆盖：

```bash
GDK_BACKEND=wayland axolotl-launcher
```

两种模式下窗口内指针光标均跟随会话主题（`XDG_CURSOR_THEME` / GSettings）。

## 更新

```bash
./update.sh
```

更新到指定版本：

```bash
./update.sh 1.8.6
```
