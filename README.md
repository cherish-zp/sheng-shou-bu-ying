# 圣手捕影（ShengShouBuYing）

一个面向 Mac(Apple Silicon)的可扩展小工具集合。通过 **Finder 右键菜单** 和 **菜单栏**
提供各类小工具,工具以统一 `Tool` 协议接入,便于持续新增。

## 当前工具

- **复制路径**:右键文件/文件夹,复制 POSIX 绝对路径到剪贴板;多选时换行分隔。

## 运行效果

- 菜单栏出现一个工具图标,点击可开关各工具。
- 在 Finder 里右键文件/文件夹,菜单中出现「复制路径」。

## 环境要求

- macOS 13.0+,Apple Silicon(arm64)
- Swift 命令行工具(Command Line Tools)。**不需要完整 Xcode**--`build.sh` 直接用 `swiftc`
  构建。若已安装 xcodegen + 完整 Xcode,也可用 `project.yml` 生成 `.xcodeproj`(见下文)。

## 构建

```bash
./build.sh
```

产物:`build/圣手捕影.app`(已内嵌 Finder 扩展并完成 ad-hoc 签名)。

> 关于 SDK:`build.sh` 默认使用 `MacOSX15.4.sdk`。本机的默认 `MacOSX.sdk`(26.5)与
> 命令行工具自带的 swiftc 版本不匹配会报错,故显式指定 15.4。若你的环境没有该 SDK,用环境
> 变量覆盖:`MAC_TOOL_PRO_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ./build.sh`。

## 启用 Finder 扩展

1. 双击运行 `build/圣手捕影.app`(首次运行需在「系统设置 > 隐私与安全」允许打开)。
2. 打开「系统设置 > 隐私与安全性 > 扩展 > 访达扩展」,勾选 `圣手捕影 Finder 扩展`。
3. 在 Finder 中右键文件/文件夹,即可看到「复制路径」。

> 若右键菜单不出现:Finder Sync 扩展通常需要一个有效的签名身份才能被系统注册。本仓库为
> 本地 ad-hoc 签名,多数情况下可用;如不可用,请用 Xcode 或 `codesign` 改用你的开发者
> 证书(或免费 Personal Team)重新签名后再运行。

## 项目结构

```
Sources/
  Shared/          共享层,编译进主程序与扩展两个 target
    Tool.swift         工具协议
    ToolRegistry.swift 工具注册中心
    CopyPathTool.swift 复制路径工具
    ToolConfig.swift   启用状态持久化(共享 JSON)
    Clipboard.swift    剪贴板写入
  App/             菜单栏主程序(LSUIElement)
    main.swift         入口
    AppDelegate.swift  状态栏菜单与开关
  FinderSyncExt/   Finder Sync 扩展
    main.swift         入口(调用 NSExtensionMain)
    FinderSyncExt.swift FIFinderSync 子类,构建右键菜单
Resources/         Info.plist 与 entitlements
build.sh           swiftc 构建(无需 Xcode)
project.yml        xcodegen 工程描述(可选,用于生成 .xcodeproj)
docs/design.md     设计文档
```

## 如何新增一个小工具

1. 在 `Sources/Shared/` 新建一个实现 `Tool` 协议的类型:

   ```swift
   public final class CopyFilenameTool: Tool {
       public let id = "copy-filename"
       public let title = "复制文件名"
       public func perform(on urls: [URL]) {
           Clipboard.copy(urls.map(\.lastPathComponent).joined(separator: "\n"))
       }
   }
   ```

2. 在 `ToolRegistry.init` 中注册:`tools = [CopyPathTool(), CopyFilenameTool()]`。

3. 重新 `./build.sh`。菜单栏开关与 Finder 右键菜单会自动包含新工具(多工具时自动收纳到
   「mac_tool_pro」子菜单)。

## 用 Xcode 打开(可选)

```bash
brew install xcodegen
xcodegen generate        # 依据 project.yml 生成 mac_tool_pro.xcodeproj
open mac_tool_pro.xcodeproj
```

生成后可在 Xcode 中设置签名团队、调试扩展。注意:`project.yml` 仅为起点,可能需按实际微调。

## 分发(后续)

直接分发路线:Developer ID 签名 + `notarytool` 公证,可配合 Sparkle 做自动更新。详见
`docs/design.md`。

## 许可

开源项目,按需自取。
