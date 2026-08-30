# openfic-git

从源码（上游 `main` 分支）构建的 OpenFic 桌面端，使用 nixpkgs 的 Electron，
而非上游 electron-builder 预编译产物。跟踪上游 main 分支：`b5c2e0bbc38e08b7d525997a47797165d40648e4`。

姊妹包 `openfic` 用 bubblewrap FHS 环境包装上游发行 tarball；本包是纯源码
构建，不提供 FHS 沙箱。**两者不要同时安装**——它们共用同一个 Electron 应用
名称和桌面身份。

## 前置要求

- 宿主机需启用 **nix-ld**（`programs.nix-ld.enable = true`）。
  应用首次启动时会下载 Python 后端（python-build-standalone CPython 与
  `openfic` PyPI wheel，约 1.2 GB）到 `~/.config/openfic-desktop/runtime`。
  这些是未打补丁的 FHS 二进制，由 nix-ld 直接运行而无需 FHS 沙箱。
  未启用 nix-ld 时本地后端无法启动（远程实例模式仍可用）。

## 构建说明

- `frontend/` 与 `desktop/` 是两个独立的 pnpm 工程；依赖预取进一个
  fixed-output store 派生，正式构建完全离线复现（`--offline`、
  `--ignore-scripts`）。
- 上游 `packageManager` 字段 pin 的 pnpm 精确版本以 npm tarball 形式内嵌
  （nixpkgs 的 pnpm 版本过新，无法离线消费上游 lockfile）。
- 应用以 Electron 非打包模式运行：桌面条目通过
  `electron <share/openfic/desktop>` 启动，前端资源从相邻的
  `../frontend/dist` 目录解析，与上游开发布局一致。
- 非打包模式下自动更新自动禁用；升级请重新运行 `update.sh`。

## 更新

```sh
./update.sh
```

拉取 `main` 最新提交，刷新全部三个哈希（源码、内嵌 pnpm、依赖 store）并
验证构建。
