# 元点剪辑批量工具箱

多草稿、多时间线批量处理工具的开源定制工程。Windows 应用版本：**v1.0.4**；另提供独立的 **macOS 0.1.0 预览版**。

**开源范围：** 本仓库公开我们编写的界面扩展、预览服务、素材整理、更新器、单文件启动器及补丁/构建脚本，采用 MIT 许可证。原始 Go/Wails 主程序的完整源码不在本仓库中，完整应用仍依赖使用者自行提供的兼容原始程序及第三方文件。详见 [开源范围与外部依赖](THIRD_PARTY.md)。

## 选择你的系统

| 系统 | 下载 | 范围 |
| --- | --- | --- |
| Windows x64 | [Windows 最新版](https://github.com/renqiukui-wq/yuandian-toolbox-releases/releases/latest) · YuandianToolbox.exe | 原有批量导出与定制功能 |
| macOS 13+，Apple 芯片或 Intel | [Mac 0.1.0 通用版](https://github.com/renqiukui-wq/yuandian-toolbox-releases/releases/tag/macos-v0.1.0) · Universal DMG / ZIP | 草稿预览、可解析草稿素材打包、已导出视频的尺寸与首帧处理 |

Mac 应用完整源码位于 [macos](macos)，使用原生 SwiftUI / AVFoundation，不依赖 Windows 原程序。**Mac 首版尚不支持直接渲染剪映复杂草稿、多时间线或原 Windows 全套混剪功能**；请先在 Mac 剪映导出视频。安装包未使用 Apple Developer ID 公证，首次启动可能需要在系统“隐私与安全性”中允许打开。详见 [Mac 安装、功能范围与构建说明](macos/README.md)。两套更新通道独立，Mac 预发布不会替换 Windows latest。

下文关于原始程序依赖及 EXE 的说明针对 Windows 定制工程。

## 源码导览

| 文件 | 用途 |
| --- | --- |
| LocalLauncher.cs | 本地服务与视频尺寸、随机封面处理 |
| DraftPreview.cs / draft_preview.js | 草稿预览、放大、按需加载和自动刷新 |
| MaterialCollector.cs | 草稿素材整理与读写桥接 |
| UpdateService.cs / UpdateInstaller.cs / AutoUpdateWorker.cs | 版本检查、下载校验、替换和重启 |
| SingleFileBootstrap.cs | 单文件打包程序的解包校验与启动 |
| local_runtime.js / studio_design.js / studio_theme.css / update_ui.js | 界面、交互与本地服务接入 |
| patch_frontend.cjs / extract_assets.py / build_binary.py | 原始程序前端提取与补丁 |
| build.py | 可复现构建入口与源码测试 |

## 获取源码

点击仓库 **Code → Download ZIP**，或使用 Git：

```powershell
git clone https://github.com/renqiukui-wq/yuandian-toolbox-releases.git
cd yuandian-toolbox-releases
```

当前源码位于 main 分支。早期 v1.0.1–v1.0.4 的发布标签是在公开源码之前创建的；要获取这次公开的代码，请下载 main，或克隆后使用 main 分支。

## 构建与验证

环境要求：Windows x64、Python 3.9+、Node.js 18+、.NET Framework 4.x 的 64 位 C# 编译器（csc.exe）。构建脚本只使用 Python 标准库；Acorn 8.15.0 已连同其许可证放入仓库。

不需要原始 EXE 即可检查公开的辅助程序和测试：

```powershell
python build.py --check
```

此命令编译公开的 C# 辅助程序，验证草稿封面缓存更新/删除/恢复、导出参数和更新安装等待逻辑；它不会启动剪映，也不会访问个人草稿。

完整打包需要自行提供：

- 原始安装目录，包含“小映批量助手.exe”和 Resources 下的 bravo.exe、f2.exe、ffmpeg.exe、MediaInfo.exe、qcore_ext.dll、uptool.exe。
- 与原始程序兼容的 jydraft_bridge.dll。
- 支持的原始 EXE SHA-256：`016012b4a179f428cc90e2b2520c761606bb773c572803abd0fb6f64485785ee`。脚本会拒绝其他二进制版本，避免错误补丁。

```powershell
python build.py --original-dir "D:\BuildInputs\original" --bridge-dll "D:\BuildInputs\jydraft_bridge.dll"
```

Node 不在 PATH 时添加 `--node "C:\path\to\node.exe"`。构建中间文件在 `.build`，最终单文件程序在 `outputs\元点剪辑批量工具箱.exe`。输入文件只读；脚本不会替换正在使用的已安装程序。

构建包含前端语法/补丁检查、原始文件哈希及指定修改区验证、打包文件完整性检查。Windows 编译器可能写入不同的构建时间，因此不承诺不同机器生成的 EXE 逐字节一致。

Fork 后请修改 `release_config.json` 中的版本、GitHub 发布仓库和附件名称，避免你的派生版本从本项目更新通道下载更新。

## 贡献与许可证

欢迎通过 Issues 报告问题、通过 Pull Requests 提交改进。提交前运行 `python build.py --check`；涉及原始程序补丁时再执行完整构建。请勿提交个人草稿、素材、凭据或不属于本仓库授权范围的二进制文件。

原创源码采用 [MIT](LICENSE)；Acorn 保留 [自身许可证](LICENSE-ACORN)。MIT 不扩展到原始主程序、剪映及其他外部二进制依赖，也不代表 Releases 中的所有组合内容均采用 MIT。

## 下载

[打开最新版本下载页](https://github.com/renqiukui-wq/yuandian-toolbox-releases/releases/latest)

在 **Assets** 中下载 **YuandianToolbox.exe**，双击运行即可。可以改名为“元点剪辑批量工具箱.exe”，无需另带 Resources 文件夹。剪映导出需要本机剪映环境。

## 软件内自动更新（v1.0.3 起）

1. 打开工具箱，启动后自动检查新版；也可以进入“检查更新”手动检查。
2. 查看更新说明，点击“下载并更新”。
3. 下载完成并校验通过后，等待当前导出或素材处理结束。
4. 程序自动退出旧版、替换原 EXE 并重新启动，无需手动覆盖文件。

下载慢时，可点击“去网站下载”打开最新版本页。打开网页不会取消软件内下载；需要切换时请先取消当前下载。网站下载是备用方式。

**首次从 v1.0.1 / v1.0.2 升级：** 旧版可以检查并下载 v1.0.3，但旧客户端尚无自动安装代码，这一次仍需退出旧版并替换 EXE。升级后，后续软件内更新可自动替换并重启。

## 草稿预览（v1.0.4 起）

所有草稿选择列表显示缩略图，点击“放大”可查看封面。优先读取剪映保存的草稿封面；缺少封面时尝试从素材生成识别图，并标注“素材画面”。素材画面不代表完整时间线效果。

可见列表每 15 秒检查封面，切回工具箱或刷新列表时也会检查。封面内容改变后自动更新，不需要重启。请先在剪映保存修改；尚未保存的编辑、剪映尚未生成的新封面无法显示。素材缺失或无法读取时显示提示，可点击重试。预览只读取草稿，不改写草稿内容，不在导出目录生成图片。

## 导出与封面

- 多草稿、多时间线批量导出，文件名沿用时间线名称。
- 支持保持原尺寸、自动 720P、固定横屏与固定竖屏；自动 720P 按每条视频的比例处理。
- 720P 处理成功后，只在所选目录中保留最终视频，不生成原尺寸备份。
- 多时间线封面支持默认首帧、随机画面帧及自选图片。随机帧写入视频首帧并内嵌封面，保持时长和音频，不另存图片。
- 使用 720P 或随机封面时，请选择自定义保存路径；遇到已有同名视频会提示，避免覆盖。
- 支持草稿素材整理、深色与浅色主题。

GitHub 下载速度取决于网络连接。本仓库用于发布程序与更新说明。
