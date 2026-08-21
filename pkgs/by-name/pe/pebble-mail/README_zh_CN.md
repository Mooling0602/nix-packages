# pebble-mail

> 中文（简体） · [English](README.md)

[Pebble](https://github.com/QingJ01/Pebble)，一款基于 Rust、Tauri 与 React 构建的本地优先桌面邮件客户端，打包自官方 Linux `.deb`。

当前版本：0.1.4。

Nix 属性名使用 `pebble-mail`，以避免与 nixpkgs 中已有的 `pebble`（Let's Encrypt 的 ACME 测试服务器）冲突。安装内容与上游 `.deb` 完全一致：二进制保留 `pebble` 名称，desktop 文件（`Pebble.desktop`，`Exec=pebble`、`Icon=pebble`）与 hicolor 图标均保持上游原名。desktop 文件会注册 `mailto:` 协议处理器。

本包解包 `.deb` 的 `data.tar`，原样安装，并通过 `autoPatchelfHook` + `buildInputs` 满足所有动态依赖（webkitgtk_4_1、gtk3、libsoup_3、用于 native-tls 回退的 openssl 等）。

## 支持的账户

Gmail、IMAP、POP3 以及实验性的 Outlook 账户。邮件数据、搜索索引、附件、规则与设置默认全部保存在本地设备上。

## 更新

```bash
./update.sh
```

更新到指定版本：

```bash
./update.sh 0.1.3
```
