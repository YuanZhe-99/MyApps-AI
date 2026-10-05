# 公共 API

## 后端

| 声明 | 契约 |
|---|---|
| `platformMayHaveOnDeviceModel` | Android/iOS/macOS 粗粒度条件，网页为 false |
| `GenAiFeature` | 独立 Prompt 与日语键盘校对能力 |
| `GenAiStatus`, `GenAiFailure`, `GenAiException` | 就绪状态和类型化失败；未知状态仍为未知 |
| `GenAiStatusReport`, `GenAiCoreInfo` | 平台诊断、模型变体、限制和语言支持 |
| `GenAiBackend` | 既有 Prompt status/info/download/generate/choose/prewarm/cancel 契约 |
| `CapabilityGenAiBackend` | 增加 capabilityReport、downloadCapability 和 proofread，默认不支持校对 |
| `MethodChannelGenAiBackend` | 可注入 MethodChannel，默认 com.yuanzhe.myapps_ai/genai 为未来插件预留 |

原生插件发布前使用明确的应用既有通道。Apple 校对不调用通道，直接报告不支持。
Android 候选生成使用校验后的行解析，Apple 使用原生约束生成。调用方继续根据
业务规则校验候选项。

## 运行时

`OnDeviceAiService` 保留既有 Prompt 接口：enabled、preferFast、report、coreInfo、
downloadProgress、downloading、busy、pausedUntil、quotaReachedToday 和 canGenerate。
方法为 setEnabled、setPreferFast、refreshStatus、download、generate、choose、prewarm、
cancelBackground、start、handleLifecycle 和 dispose。应用负责单例和 provider 注册，
构建服务时明确传入应用通道后端。

`GenAiDownload` 表示字节数，在总量已知时提供比例。`AiPriority` 区分交互和后台请求。
运行时串行推理，使用前检查状态，在非 resumed 生命周期暂停，后台忙碌时退避，
配额达到后停止本地当日后台工作。

请求超时仍为 45 秒，现在推进队列前请求后端取消。开关和模型偏好变更使晚到结果
失效。状态等待中关闭后，不再继续查询。下载完成后不重新查询已关闭的后端。
dispose 使结果失效并结束队列中的请求。原生取消仍是尽力而为，模拟验证不能证明
系统模型立即停止。

## 输出工具

`parseChoiceReply` 返回校验后的唯一候选及解析有效性。`stripMarkdown`、matchesScript
和 `cleanSentence` 保留消费者既有清理、字符比例和长度检查。领域提示词与解析留在应用。
