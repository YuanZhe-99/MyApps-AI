# 架构

## 范围与当前状态

MyApps-AI 为 MyAnime、MyDay、MyDevice 和 MyNihongo 集中维护系统提供的设备端
文本生成与校对。MyTranscribe 排除在范围之外。MyVidComp 当前没有对应实现需要迁移。

`myapps_ai` 提供共享 Prompt 执行、按能力调用的通道契约、输出工具和能力执行门控。
四个消费者均使用共享原生插件，其 Android、iOS 和 macOS release 检查已通过。
可选界面包尚未实现。

## 包边界

| 预定包 | 职责 |
|---|---|
| `myapps_ai` | 能力类型、调度、生命周期、取消，以及可选生成和缓存流程 |
| `myapps_ai_platform` | Android ML Kit GenAI/AICore 与 Apple Foundation Models 的 Flutter 原生桥接 |
| `myapps_ai_ui` | 能力状态、下载、模型偏好、诊断详情及生成内容状态 |

消费者使用共享 com.yuanzhe.myapps_ai/genai 通道。
`GenAiBackend` 保留 Prompt 契约，`CapabilityGenAiBackend` 增加独立能力查询、
下载和校对。首版运行时仅调度 Prompt 请求。校对通道协议已通过模拟测试，
平台插件在 Android、iOS 和 macOS 注册共享通道。Android 支持独立 Prompt 与
日语键盘校对；Apple 支持生成和约束候选，并报告校对不支持。
MyNihongo 通过能力适配器使用共享执行门控，练习顺序和有限重试仍由应用负责。

当前声明和行为见 [公共 API](api.md)。

运行时使用平台桥接。可选界面包使用运行时和 MyApps-UI，基础界面包不引入原生 AI
依赖。首版 Android 插件包含两个客户端，均延迟创建。这保留独立能力，避免在同一
通道安装第二个处理器。插件提供 AICore 包可见性和 R8 消费者规则，最低 Android
API 为 26，Java 目标为 17。原生依赖固定为 genai-prompt 1.0.0-beta4 和
genai-proofreading 1.0.0-beta1。

引擎卸载关闭客户端。取消后保留忙碌位置直到原生任务退出，并拒绝取消后的结果。
Apple 保留隔离会话和 CocoaPods、SwiftPM 的 Foundation Models 弱链接。

## 应用所有权

应用保留业务事实、提示词及版本、确定性决策、领域解析器、provider 注册、路由、
持久化偏好和存储适配器。初次迁移保持既有设置和缓存格式兼容。共享代码不共享
应用数据或会话。

MyAnime 保留分类空缺和推荐排序规则。MyDay 与 MyDevice 保留事实边界和备用事实。
MyNihongo 保留教学提示词、任务校验、既有输入答案接受规则，以及生成题不进入
间隔复习调度的约束。

## 能力与执行契约

- Prompt 与校对的可用状态和下载相互独立。
- 候选选择说明使用原生约束生成还是生成后校验，不假定二者等价。
- 关闭时不调用后端，包括状态查询。执行中关闭允许进行取消清理，但阻止后续
  请求和结果发布。
- 每次使用前检测可用性，保留未知和不可达状态。
- 下载仅由用户明确操作启动，由系统管理。
- 推理在设备端进行，本仓库不提供云端回退。
- 每个应用内串行执行，交互请求优先；后台重试和让步策略保留消费者行为。
- 超时和取消处理原生执行及晚到结果，不能只完成 Dart future；模型切换使旧结果失效。
- Apple 请求采用隔离会话，并保留旧系统的弱链接兼容。
- 按能力报告语言支持；转换和输出校验不意味着模型支持所有应用语言。
- 生成内容保留标识，并接受应用校验。
- 持久化可选且限于应用本地；应用模块注册将生成缓存排除在同步和备份之外。
- 诊断可以包含状态和模型标识，不包含提示词内容。

## 迁移约束

初始契约覆盖四个消费者，包括 MyNihongo 独立校对能力。按 MyDevice、MyDay、
MyAnime、MyNihongo 顺序迁移，应用保留薄适配层。原生桥接抽取、运行时抽取和
可选界面及缓存抽取均需在消费者接入前检查行为。迁移不增加 MyNihongo 的 Apple AI 支持。

更新消费者之前，先将带标签的共享依赖发布至 Gitea 和 GitHub。消费者集成同时补充
包及第三方授权声明。仓库初始化本身不属于实现里程碑或版本发布。
