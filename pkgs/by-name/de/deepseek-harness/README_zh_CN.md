# deepseek-harness

> English · [中文（简体）](README_zh_CN.md)

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 `dsh`
agent 框架与 CLI，以官方 npm tarball 打包，并使用固定的依赖锁文件。

当前版本：0.1.7-rc.2。

本包通过 `buildNpmPackage` 构建：拉取 `@deepseek-ai/dsh` tarball，注入随附的
`package-lock.json`，最终生成 `dsh` 启动器。安装后的 `dsh` 入口包装了
`node --expose-internals`。

## 更新

```bash
./update.sh
```

更新到指定版本：

```bash
./update.sh 0.1.0-rc.6
```

更新到某个 npm dist-tag（如 `latest`、`next`、`alpha`）指向的版本：

```bash
./update.sh -t alpha
```

更新脚本会重新生成随附的 `package-lock.json`、预取新的 `sourceHash`。
无需探测依赖哈希：`importNpmLock` 直接从 lockfile 推导依赖集合。

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
`require` 获取，因此 `postInstall` 会补丁 addon 入口
（`node-addon-require-builtin/lib/index.js`），先尝试 `require(moduleId)`，
失败再回退到原生 addon——与上游自带的 vendored Cordis 加载器
（`vendor/loader/src/internal.ts`）顺序一致。等到上游兼容 GCC 的代码生成，
或无需 addon 即可暴露该加载器后，即可从 `package.nix` 移除该
`substituteInPlace`。
