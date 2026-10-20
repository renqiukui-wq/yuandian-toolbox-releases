# 开源范围与外部依赖

本仓库根目录的 LICENSE（MIT）适用于本仓库原创的 C、C#、JavaScript、CSS、HTML、Python 源码和文档。

- acorn.js：Acorn 8.15.0，MIT，原许可证见 LICENSE-ACORN。用于在构建时解析 JavaScript。
- 原始“小映批量助手.exe”及从其提取的 Go/Wails 前端和后端：本仓库没有其完整源码，不纳入本仓库 MIT 授权。构建时由使用者提供兼容原始文件；生成的提取文件保留在被忽略的 .build 目录中。
- 原始安装资源 bravo.exe、f2.exe、ffmpeg.exe、MediaInfo.exe、qcore_ext.dll、uptool.exe：不在源码仓库内分发，依各自权利人的许可使用。不同 FFmpeg / MediaInfo 构建的具体许可取决于其构建配置和发行材料。
- draft_codec.c：本仓库原创的草稿编解码实现，MIT，使用 Windows BCrypt/Crypt32 系统接口。构建输出沿用桥接 C ABI，替代原 jydraft_bridge.dll，不再动态调用 videoeditor.dll 读写草稿。
- 剪映和 videoeditor.dll：运行时外部依赖，不包含在本开源源码中，未获得本仓库 MIT 重新授权。

GitHub Releases 中的 EXE 是包含外部二进制依赖的组合发行包；根目录 MIT 许可证不能解释为对整个 EXE 中所有第三方内容的重新授权。

本项目公开的是可以检查和修改的定制层及其构建工具，不声称已经公开原始主程序的全部源码，也不声称完整应用能仅使用本仓库源码从零构建。
