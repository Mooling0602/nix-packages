# axolotl-launcher-bin

> 中文（简体） · [English](README.md)

[Axolotl Launcher](https://github.com/Mystic-Stars/Axolotl)（美西螈启动器），一款基于 Modrinth 生态构建的自由跨平台 Minecraft 启动器，打包自官方 Linux `.deb`。

当前版本：1.8.7。

与官方 AppImage（内建自包含的 GTK/WebKit 运行时，因此无法读取宿主会话的光标主题配置）不同，`.deb` 载荷是动态链接的二进制，使用系统共享的 GTK3/WebKit 库（webkitgtk_4_1、gtk3、libsoup_3、glib 等）。这意味着在 X11 和原生 Wayland 下，光标主题都能正确跟随桌面会话。

本包解包 `.deb` 的 `data.tar`，将主二进制安装为 `axolotl-launcher`，并通过 `autoPatchelfHook` + `buildInputs` 满足所有动态依赖。

## 显示后端

- **X11（默认）**：在 Wayland 会话下通过 XWayland 渲染。
- **原生 Wayland**：前置 `GDK_BACKEND=wayland`：

  ```bash
  GDK_BACKEND=wayland axolotl-launcher
  ```

两种后端都使用系统 GTK/WebKit，因此两种模式下窗口内指针光标都跟随会话主题（`XDG_CURSOR_THEME` / GSettings）。

## 更新

```bash
./update.sh
```

更新到指定版本：

```bash
./update.sh 1.8.6
```
