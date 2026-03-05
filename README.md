# CliproxyStatusBar

一个基于 macOS 状态栏（Menu Bar）的 CLIProxyAPI 使用监控工具。

当前版本采用 macOS 原生设计语言（状态栏 + Popover）：

- 系统材质（`regular/ultraThinMaterial`）与语义色
- 标准控件样式（`bordered/borderedProminent` 按钮、Form、ProgressView）
- 原生 Charts 趋势图（24h Requests / Tokens）
- SF Symbols + 系统排版 + 单色/低饱和视觉层级
- 内置设置弹窗（无需手改文件）

## 依赖接口

- `GET /v0/management/usage`
- Header: `Authorization: Bearer <management-key>`

## 运行要求

- macOS
- Swift 6+
- CLIProxyAPI 已启动，且可访问管理接口

## 启动

```bash
cd /Users/das/SourceCode/CLIProxyAPI/cliproxy-statusbar
swift run CliproxyStatusBar
```

如果你的环境对 `~/Library` 写入受限，可把 Swift 缓存改到项目目录：

```bash
mkdir -p .swift-cache/.swiftpm .swift-cache/clang
SWIFTPM_CONFIG_PATH=$(pwd)/.swift-cache/.swiftpm \
SWIFTPM_SECURITY_PATH=$(pwd)/.swift-cache/.swiftpm \
CLANG_MODULE_CACHE_PATH=$(pwd)/.swift-cache/clang \
swift run CliproxyStatusBar
```

## 使用

1. 启动后点击菜单栏心电图图标。
2. 在弹出面板查看实时监控。
3. 点击 `Settings` 配置：
- Base URL（默认 `http://127.0.0.1:8317`）
- Management Key
- 刷新秒数（3~300）
- 界面语言（自动 / 简体中文 / English）

配置会保存到：

`~/Library/Application Support/CliproxyStatusBar/config.json`

## 环境变量（首次启动可选）

- `CLIPROXY_BASE_URL`
- `CLIPROXY_MANAGEMENT_KEY`
- `CLIPROXY_REFRESH_SECONDS`
- `CLIPROXY_LANGUAGE`（支持：`auto` / `zh` / `en`）
- `MANAGEMENT_PASSWORD`（`CLIPROXY_MANAGEMENT_KEY` 缺省时回退）

## 常见问题

- `HTTP 401/403`：管理密钥不对，或管理接口未开放。
- 一直显示 `Error`：先在终端用 `curl` 验证 `/v0/management/usage` 是否可达。
- 没有趋势/排行：CLIProxyAPI 当前流量太少或 usage 统计未启用。

## License

MIT
