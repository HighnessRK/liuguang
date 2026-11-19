# V1.0.7 V1.0.6 要求复核

复核基于当前源码、离线 Flutter 测试和 V1.0.7 构建前检查，未调用真实 API Key。

| 编号 | 要求 | 结果 | 代码落点 |
|---:|---|---|---|
| 1 | 传奇二瞬执行时生图界面完整显示 | 已完成 | `lib/screens/editor.dart` 的任务态独立页面与 `TaskStatusCard` |
| 2 | 切后台后继续生图 | 已完成 | Android 前台服务、`START_REDELIVER_INTENT`、后台任务状态持久化 |
| 3 | 极光动效、百分比、流式阶段 | 已完成 | `AuroraSurface`、`TaskStatusCard`、API `onStage` 回调 |
| 4 | 智能润色结合提示词和图片 | 已完成 | `create.dart` 的 `imageBrief` 与润色上下文 |
| 5 | 智能润色运行光效 | 已完成 | `AuroraBusyButton` |
| 6 | 图生图规格拟合底图 | 已完成 | `matchedPhotoOptions` |
| 7 | 去除生成白边 | 已完成 | `canvasPrompt` 白边约束 |
| 8 | 识图复用对话 Key 时复用地址 | 已完成 | `AppStore.effectiveVisionApi` |
| 9 | 创作与助手直接切换模型 | 已完成 | 两处模型选择 sheet |
| 10 | 创作助手上传图片识图 | 已完成 | `assistant.dart` 图片上传与 `describeImage` |
| 11 | 本地分享模板、超清保存相册 | 已完成 | `share_card.dart` 本地渲染与保存选项 |
| 12 | 生成规格窗有退出按钮 | 已完成 | `GenerationSettings` 液态玻璃关闭按钮 |
| 13 | 所有图片支持点击放大 | 已完成 | 创建输入、生成结果、GIF 帧、材质预览、DeepSeek 参考图、作品详情均使用 `ZoomableImage` 或 `InteractiveViewer` |
| 14 | 底部导航悬浮无遮罩 | 已完成 | 根页面浮动导航与 `StudioTabInset` |
| 15 | DeepSeek 表情包静态 / 动图 | 已完成 | 固定角色参考图、动态模式 512×512、8 帧、200ms、`smooth motion`、`consistent character` |
| 16 | 稳定性和流畅度 | 已完成 | 页面动效降级、任务取消、内存回收、离线测试与构建验证 |

本版本补修内容：

- 大肥鱼娘参考图使用完整宽幅比例显示，并支持点击查看大图。
- 动图请求固定 `frame_count=8`、`frame_duration_ms=200`，不会再让对话模型改变这两个值。
- 更新弹窗对当前版本号使用本地当前日志，避免服务端缓存上一版本正文。
