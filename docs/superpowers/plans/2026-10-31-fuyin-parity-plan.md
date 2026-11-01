# 对标浮引全量复刻实施计划（2026-10-31）

用户决策：完美复刻（Q1）、第三方加密（Q2: b）、横向模式（Q3: a）。
范围：浮引 20 功能域全部子功能，包括每个下拉框/子面板。

## 批次与交付物

- **批 I 快赢**：TextToolkit 补全（命名转换 camel/snake、JSON 反转义、时间戳⇄日期）、
  轻量日历面板（月网格纯逻辑 + 深色视图）、开机启动（SMAppService）、改图 UI 入口
- **批 II**：存储清理面板（剪贴板/标注/草稿/缓存分项清理）、截图窗口吸附
  （Auto吸附整窗，复用 detectWindowUnderMouse）、GIF 画质/帧率选项
- **批 III**：加密压缩（系统 zip -P = ZipCrypto；AES 需第三方 p7zip 二进制，另行评估）、
  密码本（Keychain 存储 + 解压自动填充）、QuickLook 预览压缩包（新 appex 或应用内预览）、
  双击默认解压（LSSetDefaultHandlerForURLScheme/文档关联）
- **批 IV**：长截图横向模式（ScrollStitcher 轴向参数化 + 自动滚动）
- **批 V**：翻译自定义 LLM API（OpenAI 格式，endpoint/key/模型设置）、语音逐字上屏
  （CGEvent 键盘注入）、右 Option 触发、听写选项
- **批 VI**：动作面板 38 键位完美复刻（ActionBinding 模型、前缀键位、面板 UI、边缘触点）
- **批 VII**：应用面板（/Applications 扫描、搜索、排序、星标）
- **批 VIII**：手机配对验证码（6 位码配对 + 客户端令牌记忆）
- 批 IX：OCR/听写选项、iCloud 保温、主题外观切换（跟随系统可选）

## 已完成（此前批次）
截图套件 1:1 工具条、剪贴板历史、速记、改图逻辑、压缩/解压（zip/tar）、
翻译面板、听写、GIF、启动器面板、Widget、HTTP 遥控、CloudSync 封装、
端口占用、文本工具、二维码、锁屏/回桌、进入终端、右键全家桶。
