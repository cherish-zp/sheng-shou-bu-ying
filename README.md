# 圣手捕影（ShengShouBuYing）

一个面向 Mac(Apple Silicon)的可扩展小工具集合。通过 **Finder 右键菜单** 和 **菜单栏**
提供各类小工具,工具以统一 `Tool` 协议接入,便于持续新增。

## 主要功能

- **菜单栏**:截图(区域/延时/序号标注)、贴图(滚轮缩放/呼吸灯)、长截图(滚动拼接)、
  录屏、取色、OCR、快速片段、中转站(文件/文本暂存拖拽)。
- **Finder 右键**:复制路径、新建文件等,以统一 `Tool` 协议接入,便于持续新增。

## 运行效果

- 菜单栏图标呼出各功能;全局热键 F1 触发截图(可在设置中查看/调整)。
- 在 Finder 里右键文件/文件夹,菜单中出现本应用的工具子菜单。

## 环境要求

- macOS 13.0+,Apple Silicon(arm64)
- 主路线:完整 Xcode + xcodegen(`brew install xcodegen`),用于 `package.sh` 正式构建与开发;
- 快速路线:`build.sh` 仅需 Swift 命令行工具(Command Line Tools)。

## 构建

```bash
brew install xcodegen
xcodegen generate          # 依据 project.yml 生成 mac_tool_pro.xcodeproj
./package.sh               # Release 构建 + 自动签名 + 打包 DMG 到 dist/
```

产物:`dist/圣手捕影-<版本>.dmg`(可拖拽安装);CI 上用 `SIGN_MODE=ci ./package.sh`
走 ad-hoc 签名(见「发布」)。

> `./build.sh` 为 swiftc 快速直编路线(产物 `build/圣手捕影.app`,ad-hoc 签名),仅依赖
> Command Line Tools,适合快速验证;默认使用 `MacOSX15.4.sdk`,可用
> `MAC_TOOL_PRO_SDK=<SDK路径>` 覆盖。

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

3. 重新构建。菜单栏开关与 Finder 右键菜单会自动包含新工具(多工具时自动收纳到
   「圣手捕影」子菜单)。

## 用 Xcode 打开(可选)

```bash
brew install xcodegen
xcodegen generate        # 依据 project.yml 生成 mac_tool_pro.xcodeproj
open mac_tool_pro.xcodeproj
```

生成后可在 Xcode 中设置签名团队、调试扩展。注意:`project.yml` 仅为起点,可能需按实际微调。

## 下载安装

正式版从 Release 下载:

- GitHub:<https://github.com/cherish-zp/sheng-shou-bu-ying/releases>
- Gitee:<https://gitee.com/princess-zp/sheng-shou-bu-ying/releases>

1. 下载 `圣手捕影-<版本>.dmg`,双击挂载后拖入「应用程序」。
2. 首次打开:在「应用程序」中**右键 → 打开**(CI 构建未做 Apple 公证,直接双击会被
   Gatekeeper 拦截;右键打开一次后即可正常使用)。
3. Finder 右键菜单:「系统设置 → 登录项与扩展 → Finder 扩展」勾选圣手捕影。

## 发布

推送 `v*` tag 自动发布,如 `git tag v1.0.0 && git push origin v1.0.0`,CI
(`.github/workflows/release.yml`)依次执行:

1. 版本校验:tag 名必须与 `Resources/App-Info.plist` 的 `CFBundleShortVersionString` 一致;
2. 跑全量测试 → ad-hoc 构建 → 打包 DMG → 创建正式 GitHub Release;
3. 同步附件到 Gitee Release(需仓库 secret `GITEE_TOKEN`,未配置自动跳过,失败不阻塞发布)。

手动验证:在 Actions 页面手动触发 `release` workflow,走同一构建链路但只上传 artifacts、
不发版。后续升级路线:Developer ID 签名 + `notarytool` 公证(需付费 Apple Developer
账号),详见 `docs/design.md`。

## 许可

开源项目,按需自取。
