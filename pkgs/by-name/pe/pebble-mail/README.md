# pebble-mail

> English · [中文（简体）](README_zh_CN.md)

[Pebble](https://github.com/QingJ01/Pebble), a local-first desktop email client built with Rust, Tauri,
and React, packaged from the official Linux `.deb`.

Current version: 0.1.4.

The Nix attribute is named `pebble-mail` to avoid clashing with nixpkgs'
existing `pebble` (Let's Encrypt's ACME test server). The installed payload is
verbatim from the upstream `.deb`: the binary stays `pebble`, and the desktop
entry (`Pebble.desktop`, `Exec=pebble`, `Icon=pebble`) and hicolor icons keep
their upstream names. The desktop entry registers the `mailto:` scheme handler.

The package extracts the `.deb`'s `data.tar`, installs it as-is, and uses
`autoPatchelfHook` + `buildInputs` to satisfy all dynamic dependencies
(webkitgtk_4_1, gtk3, libsoup_3, openssl for the native-tls fallback, …).

## Supported accounts

Gmail, IMAP, POP3, and experimental Outlook accounts. Mail data, the search
index, attachments, rules, and settings stay on your device by default.

## Update

```bash
./update.sh
```

To update to a specific version:

```bash
./update.sh 0.1.3
```
