# local-ai-kit 彻底卸载工具

一键、干净地卸载 [local-ai-kit（本地 AI 部署包）](https://github.com/regdiliKUN/local-ai-kit) 在本机留下的所有产物。

适合两种场景：

- 把项目下载/解压到本地后，想连项目带它安装出来的东西一起删干净；
- 已经用向导或命令行装过，现在想完整卸载。

## 特点

- **不依赖 Node.js**：纯 Windows 自带命令（PowerShell），即使你把 Node 也一起卸了照样能跑；
- **删除前逐项确认**：先列出「要删什么 / 不删什么」，看清再回车；
- **模型目录单独确认**：可能十几 GB，且只在路径确实是 `...\ollama\models` 结构时才允许删除；
- **通用软件默认不动**：Ollama、Node.js、dsh 需你明确同意才会卸载；
- **取消即不删**：任何一步不确认都不会动文件。

## 使用方法

1. 把本仓库的两个文件放在同一个文件夹里：
   - `彻底卸载本地AI.cmd`（双击这个）
   - `彻底卸载本地AI.ps1`
2. **双击 `彻底卸载本地AI.cmd`**，按提示操作即可。
3. 也可以把 local-ai-kit 文件夹直接拖到 `.cmd` 上，或在命令行传入路径：

   ```bat
   彻底卸载本地AI.cmd "D:\local-ai-kit"
   ```

## 会清理哪些东西

| 项目 | 说明 |
| --- | --- |
| 后台服务 | 停止 Ollama(11434)、dsh 工作台(3080)、控制台(7790) 相关进程 |
| 桌面快捷方式 | 启动本地AI / 停止本地AI / 本地AI控制台 / 本地AI卸载 四个 `.lnk` |
| 项目目录 | 下载源目录 + 安装目录（自动探测，也可手动指定） |
| 用户环境变量 | `OLLAMA_MODELS`、`OLLAMA_CONTEXT_LENGTH`、`OLLAMA_FLASH_ATTENTION`、`OLLAMA_KV_CACHE_TYPE`、`OLLAMA_KEEP_ALIVE`、`OLLAMA_HOST` |
| 安装日志 | `%TEMP%\localai-setup.log` |
| 模型目录（可选） | `<盘>:\ollama\models` 或 `用户\.ollama\models`，删除前单独确认 |
| Ollama / Node.js / dsh / 开机自启（可选） | 默认不动，逐项询问 |

## 说明

- 与项目自带的 `scripts/uninstall.mjs` 相比，本工具**不需要 Node 环境**，也不要求必须从安装目录内部运行，覆盖范围更广。
- 删除安装目录时，若文件被占用会尝试延迟删除；仍失败时会提示手动删除路径。
- 本工具只处理 local-ai-kit 相关痕迹，不触碰其它软件与个人文件。

## 许可

MIT
