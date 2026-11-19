# V1.0.8 发布前验证

日期：2026-11-19

## 根因

V1.0.7 在小米真机冷启动时，`path_provider_android` 的 JNI Context 查找抛出 `ClassNotFoundException: Landroid/content/Context;`，异常发生在 `AppStore.init`，导致 Flutter 首屏无法完成初始化。

## 修复

- `AppStore.init` 对应用支持目录读取增加异常兜底，插件 JNI 初始化失败时使用应用私有临时目录创建工作区。
- 临时文件路径统一使用安全目录辅助函数，避免后续路径调用再次把启动问题带回任务流程。
- DeepSeek 表情包入口移到创作页，与“文生图”“图生图”并列。
- DeepSeek 页面增加生成类型与动图模式之间的玻璃卡片间距，生成按钮改为统一液态玻璃按钮。
- 动图参数继续固定为 512×512、8 帧、200ms。

## USB 真机验证

设备：`b39ee542`（小米 Android，ARM64）

- 安装：`versionName=1.0.8`、`versionCode=9`，ADB 安装成功。
- 冷启动：应用进入“创作”首页，首帧正常显示。
- 创作页：可见“文生图 / 图生图 / 表情包”三个并列入口。
- 点击“表情包”：成功打开 DeepSeek 页面，固定角色参考图完整显示。
- 日志：无 `FATAL EXCEPTION`、无 `ClassNotFoundException`、无未处理 Dart 异常。
- 未调用真实生图或对话 API。

## 自动化验证

- `flutter test`：61 项全部通过。
- ARM64 Release 构建成功，APK SHA256：`f98b7b3e97e317c704d147e6f209214a6697521b3319b4e722d19d65a0e93e40`。
