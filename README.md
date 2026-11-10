# 琉光 · LIUGUANG

V1.0.2 · Flutter 安卓 AI 影像工作室。Android 10+，ARM64。

[GitHub](https://github.com/HighnessRK/liuguang) · [Gitee](https://gitee.com/highnesssrk/liuguang)

从仓库 Releases 下载 `liuguang-v1.0.2-arm64.apk`。校验文件 `SHA256.txt` 随版本提供。

## 接入模型

安装 Release 中的 APK，打开「设置 → 模型连接」，分别填写生图和对话 API 地址与 Key。基础地址须包含服务商要求的路径，例如 `https://example.com/v1`，不会自动添加 `/v1`。也兼容填入完整 Images/Chat 端点。

「保存并自动检测」读取 `/models`，完整显示所有返回模型。模型名称仅用于初选，不过滤未知模型；服务端通常不在模型列表提供能力元数据，可手动填写 ID 和选择图片协议。Key 由 Android Keystore 加密保存。

| 协议 | 请求方式 |
| --- | --- |
| 标准 Images | `/images/generations` 与 multipart `/images/edits`，发送 model/prompt/n/size，格式本地转换。 |
| GPT Image | 另发送 quality、output_format、moderation，以及 JPEG/WebP 的 output_compression。 |
| DALL·E | 使用 response_format；DALL·E 3 映射 hd/standard，限制单张文生图。 |
| 对话生图 | `/chat/completions` 多模态输入；解析 URL、data URL 与 base64 返回，没有标准蒙版能力。 |

对话与提示词润色使用另一组 `/chat/completions` 配置。没有内置服务、付费账号或测试 Key。

随想的 GPT Image / Grok Image 自动使用 `/images/generations/async`、`/images/edits/async` 与同源任务轮询。上传副本限制为长边 2048 像素、每张 3 MiB，保留 PNG 透明通道并同步缩放蒙版；原图不变。仅在服务端明确声明未启用异步任务时回退同步，不自动重复提交已接收的任务。

随想 `gpt-image-2.6-sunburst` 已使用 GPT Image 协议实测竖幅生成和大图编辑，可保留这一协议。服务端可能返回不同于请求值的实际像素，应用显示真实尺寸。本轮成功请求使用临时 USB 转发的电脑网络，不能据此保证手机当前直连线路可用；验证记录见 `docs/VALIDATION.md`。

## 功能

- 文生图、图生图、底图和最多八张参考图；可视比例、1K/2K/4K 长边规格（默认 4K）、生成质量、数量、格式和压缩质量。
- 六大类 32 种材质：光透、毛绒、金属、自然、软塑、织物。原创离线预览不消耗模型额度；材质偏好作为单独段落追加，原提示词保持优先。
- PNG/JPEG/WebP/GIF 导出。生成页 GIF 由返回图片本地合成：单张为静态 GIF，多张为逐帧动画。作品页可添加 2–12 帧，排序、调节帧时长及 128/256 色。
- 提示词草稿、润色前后审阅、对话助手、复制和再次使用提示词。
- 局部重绘的画笔、橡皮、撤笔、清空、柔化边缘；换装、换天气、消除和修复指令；透明 PNG 蒙版及生成后的本地选区合成，保护区域外像素。
- GPU 实时调色：曝光、鲜明度、高光、阴影、对比度、亮度、黑点、饱和度、自然饱和度、色温、色调、锐度、暗角、颗粒。CPU 导出采用对应处理顺序。
- 阴影/中间调/高光的青–红、洋红–绿、黄–蓝色彩平衡；保持 HSL 明度默认开启。独立实现，未复制 Photoshop 或 GPL 源码。
- 自由与比例裁切、拖动构图、旋转、翻转、撤销、重做和按住对比。修改保存为副本。
- 本地手动焦点渐进虚化；云端使用适合接口的上传副本请求景深、影调增强，默认保持原尺寸画布，亦可自定义规格。传奇二瞬提供三种电影影调与强度控制。
- 作品搜索、收藏、分享、相册保存和格式转换；Token、耗时、24 小时分布、按模型汇总、自定义单价估算与 CSV。
- 跟随系统/浅色/深色、八套整页渐变主题、材质不透明度、模糊强度、额外字号、增强对比、减少动态和触感反馈。
- 桌面图标支持星芒、光圈、琉珠、光轨，搭配六种颜色和液态玻璃、细雾磨砂、温润陶瓷、柔软毛绒材质，96 种原生图标组合；可恢复原始图标。
- 紧凑悬浮导航支持横向拖动玻璃滑块；「设置」只显示分类入口，详细选项进入二级页面。使用系统字体，统一标题、正文与辅助文字的字号。
- 编辑器照片预览固定在上方，工具区独立滚动；调色时始终可对照照片。

## 能力说明

审核档位保留原提示词，在独立段落附加偏好；GPT Image 协议另映射 `moderation=auto/low`。提示词不能保证改变服务端审核，也不能覆盖服务政策。严格档要求不符合规则时拒绝，而非擅自替换画面。

尺寸、数量、质量、参考图与蒙版能力由服务商和模型决定。4K 预设不会将低分辨率图片伪装成模型原生 4K，作品页展示实际返回像素。失败和取消不自动重试，取消无法撤销服务端已执行的计算与扣费。

景深功能为独立工作流，不包含小米「传奇一瞬」或徕卡专有算法。云端由用户指定模型执行，不能保证像素无损或光学真实性；本地模式是径向渐进虚化，不是深度模型。原图保留，结果可撤销。

「原尺寸」指最终保存的画布大小。请求采用接口兼容尺寸，模型输出可能比原图小，必要时会还原到原画布；这不会增加模型原生细节。作品详情分别记录保存分辨率与模型实际输出分辨率。本轮 V1.0.2 使用模拟接口和本地样例测试，未调用真实用户模型。

费用是本机按自定义 USD 单价的估算，不是服务商账单；未返回 Token 时记录未知，只统计本机发起的请求。

## 架构与构建

`lib/core`：API、数据、加密配置、原子索引写入和图像处理。`lib/screens`：页面。`lib/ui/glass.dart`：统一玻璃组件。`shaders`：实时调色；折射和高光由渲染器提供。

Flutter 承担主界面和业务，基础控件实际使用 Flutter_miuix 1.3.0。卡片使用参考项目相同的共享背景模糊与渐变材质，导航使用 Liquid Glass Renderer 1.0.0-dev.2 实时透镜。没有原生 PlatformView 或截图回传。Miuix KMP 和 Liquid-Glass-Android 作为原始设计参考。

每个主页面独立隔离玻璃层，避免 IndexedStack 中隐藏页面的几何参与当前画面；编辑器工具滚动区另设裁切边界。同页控件共享背景，嵌套玻璃与导航使用局部 GPU 捕获。没有定时截图、PNG 编码或跨平台回传。当前渲染器为固定版本的预发布包，已在连接设备上验证；不支持完整 GPU 管线的设备会回退到透明材质。

已验证环境：Flutter 3.47.7、Dart 3.13.5、Java 21、Android SDK 36.1。

```powershell
python tools/setup_signing.py
./tools/build.ps1 -Mode release
./tools/build.ps1 -Mode release -Install
dart analyze lib test integration_test
flutter test --no-pub
./tools/test-device.ps1 -Device <设备ID>
```

构建脚本读取当前 Windows 系统代理用于本次 Gradle 命令，不更改系统代理。跨盘 Pub 缓存采用关闭 Kotlin 增量缓存的配置。当前 Flutter 在中文路径下的 LSP 检查有长度计算问题，使用 `dart analyze`；aapt 读取中文路径 APK 的元数据可能失败，APK 可经 adb 直接安装。

`tools/install.ps1` 和真机测试脚本可在已授权的 USB 调试设备上识别「琉光」安装提示，点击「继续安装」。真机测试请从无中文的驱动器映射路径运行。

`.signing/liuguang-release.jks` 和 `android/key.properties` 是已被 Git 忽略的私有签名材料。请私下备份，后续更新必须使用同一签名。签名脚本不会覆盖已有材料。

验证范围见 [验证记录](docs/VALIDATION.md)。用户选择自行填写服务商，因此没有消费商业 API 额度；真实服务的权限、计费和生成质量尚未验证。

## 研究资料与许可

- [Miuix KMP](https://github.com/compose-miuix-ui/miuix/tree/v0.8.8)：Apache-2.0，许可随应用打包。
- [Liquid-Glass-Android](https://github.com/QWEA0/Liquid-Glass-Android/tree/v2.0.11)：MIT，许可随应用打包。
- [OpenAI 官方图片文档](https://developers.openai.com/api/docs/guides/image-generation)：图片、蒙版、多图和参数协议参考。
- [GIMP 色彩平衡](https://github.com/GNOME/gimp/blob/master/app/operations/gimpoperationcolorbalance.c)：研究色调分区与保持明度的行为，未复制 GPL 实现。
- [Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)：研究深度估计方案，本版本不内置该模型。
- Unsplash 示例素材：[山景](https://images.unsplash.com/photo-1464822759023-fed622ff2c3b)、[森林](https://images.unsplash.com/photo-1472396961693-142e6e269027)。



## 交互修订（2026-11-09）

参照本机 zufang_guanjia 的分组布局、快速横向转场、TickerMode 与 RepaintBoundary 隔离方式调整。生成规格以七种可视比例配合 1K/2K/4K 长边档位，内部按八像素对齐换算请求尺寸。服务端是否支持该规格由模型决定。

修图五个工具固定可见，「传奇二瞬」景深工作流在首位，云端操作在本地虚化之前；该名称是入口名称，仍是独立实现，不含小米专有算法。色彩平衡用颜色圆点和渐变轨道表达方向，保留屏幕阅读器的颜色语义与默认保持明度。作品支持长按后确认删除应用副本。

关闭滚动边缘拉伸、控件外阴影与玻璃内暗影；面板内玻璃共享采样，隐藏页面暂停动画，照片调整未变时避免重复绘制。不同手机与操作的实际帧率仍会变化。

## 更新与日志

「设置 → 应用更新」可切换 GitHub / Gitee，手动检查、查看版本日志、下载并调起系统安装器。自动检查默认开启，启动和每天 09:00、21:00 执行；后台使用 AlarmManager 与 JobScheduler，省电策略可能延迟检查。强制停止后需重新打开恢复。

APK 安装前验证应用包名、既有发布签名和版本号；下载可取消，拒绝降级。系统的未知来源安装与通知权限由用户控制。

诊断日志仅保留最近 300 条事件、时间及状态码，不收集接口 Key、地址、提示词、图片或响应正文；支持查看、清空和用户主动导出。版本更新说明见 [CHANGELOG.md](CHANGELOG.md)。

本版实际使用 Flutter_miuix 1.3.0 的按钮、输入框、分段选择、滑条、开关与复选框，主题和极光背景参数对齐本机参考项目。底部导航保留实时玻璃透镜。

发布工具 `tools/publish_release.py` 从外部凭据文件读取令牌，支持源码同步与 Release 附件上传。令牌不会写入仓库；GitHub 网络限制时使用 Git Data API 同步源码。公开仓库不包含正式签名私钥，维护者须私下备份并继续使用原密钥签名。

当前真机界面：[作品页](docs/screenshots/published-library-fixed.png) · [外观](docs/screenshots/published-appearance-fixed.png) · [应用更新](docs/screenshots/published-update-settings.png)。
