# V1.0.9 发布前验证

日期：2026-11-19

## 修复

- V1.0.8 在 JNI 兜底后读取了临时目录，导致旧版 `files/studio/catalog.json` 没有被读取。V1.0.9 优先使用旧版应用 files 目录，恢复作品、请求明细和历史消息。
- GIF 专业参数校验补齐 `frame_count`（2–16）和 `frame_duration_ms`（20–2000），大肥鱼娘及自定义角色固定发送 8 帧 / 200ms。
- 新增自定义表情角色：三视图、基本描述、对话模型润色、独立静态 / 动图生成流程。

## USB 真机验证

设备：`b39ee542`

- 安装 `versionName=1.0.9`、`versionCode=10` 成功。
- 冷启动正常，无 JNI Context 异常。
- 作品页显示历史数据：实机显示 `2 件作品`，两张历史作品可正常查看。
- 创作页可打开 DeepSeek 表情包入口。
- DeepSeek 页面显示“创建其他表情角色”入口。
- 未调用真实 API Key。

## 自动化验证

- `flutter test`：61 项全部通过。
- ARM64 Release 构建成功。
- APK SHA256：`94d025998f0b2aab3238abe3a67439608cb86da03b91a2885b3e76dcea66ca0c`。
