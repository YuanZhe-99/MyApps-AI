# 架构

## 范围与当前状态

MyApps-AI 提供可复用的系统设备端文本生成与校对基础设施。应用按需选择包与能力，
可用条件取决于平台支持和运行时状态。

`myapps_ai` 提供共享 Prompt 执行、按能力调用的通道契约、输出工具和能力执行门控。
共享原生插件支持 Android、iOS 和 macOS。
可选界面包通过注入文案和回调呈现洞察卡及公共 Prompt 设置。
应用保留路由、provider 和教学呈现。

## 包边界

| 包 | 职责 |
|---|---|
| `myapps_ai_core` | 与后端无关的能力类型、后端契约、执行门控、备用生成、缓存条目和输出校验；不含插件或原生运行库 |
| `myapps_ai` | 基于注入后端的调度、生命周期、取消，以及可选生成和缓存流程 |
| `myapps_ai_models` | 与能力无关的模型制品：清单、可断点续传并校验 SHA-256 的下载、可回滚的原子安装、租约、状态、设备本地引擎状态和自检契约；存储根目录与 HTTP 客户端由外部注入；不含原生运行库 |
| `myapps_ai_llm` | 文本 LLM 消息、采样、流式事件、指标、能力声明及 `GenAiBackend` 适配；不含原生运行库 |
| `myapps_ai_llm_llama` | 可选 llama.cpp `LlmBackend`，使用构建 hook 按 URL 与 SHA-256 获取的上游 release 二进制；默认 CPU，GPU 卸载需显式开启 |
| `myapps_ai_asr` | 语音识别契约、路线、按策略回退、崩溃隔离、说话人分离协议与 ASR 自检样本；不含原生运行库 |
| `myapps_ai_asr_whisper`、`myapps_ai_asr_sherpa`、`myapps_ai_asr_apple` | 可选 ASR 后端：whisper.cpp（Whisper、Parakeet）、sherpa-onnx（Qwen3-ASR、说话人分离）和 Apple（FluidAudio、系统识别器）；原生库为预构建二进制，由构建 hook 按 URL 与 SHA-256 获取，消费者构建中从不编译 |
| `myapps_ai_online` | 不含密钥的在线来源记录、模板、OpenAI 兼容流式 LLM 后端、在线转写客户端及在线隐私提醒模型；基于 `package:http` 的纯 Dart 包 |
| `myapps_ai_platform` | 可选的 Android ML Kit GenAI/AICore 与 Apple Foundation Models Flutter 原生桥接及 `MethodChannelGenAiBackend` |
| `myapps_ai_ui` | 能力状态、下载、模型偏好、诊断详情及生成内容状态 |
| `myapps_ai_local_ui` | 由 `ModelManagementController` 驱动的可选本地模型管理页面；仅依赖 `myapps_ai_models` |
| `myapps_ai_online_ui` | 可选在线来源页面：来源列表、编辑、密钥输入、主动连接测试和隐私提醒；存储、文案及 MyApps-UI 输入组件由应用注入 |

依赖单向：`myapps_ai_ui → myapps_ai → myapps_ai_core`，`myapps_ai_platform →
myapps_ai_core`。`myapps_ai_models` 不依赖其他 MyApps-AI 包、应用存储或状态管理。运行时与界面均不依赖平台插件。需要系统 AI 的消费者显式依赖
`myapps_ai_platform`，并把其后端传给 `OnDeviceAiService`；不需要的消费者不链接
任何原生 AI 代码。`tool/check_dependencies.py` 负责检查此约束。

消费者使用共享 com.yuanzhe.myapps_ai/genai 通道。
`GenAiBackend` 保留 Prompt 契约，`CapabilityGenAiBackend` 增加独立能力查询、
下载和校对。首版运行时仅调度 Prompt 请求。校对通道协议已通过模拟测试，
平台插件在 Android、iOS 和 macOS 注册共享通道。Android 支持独立 Prompt 与
日语键盘校对；Apple 支持生成和约束候选，并报告校对不支持。
能力适配器可使用共享执行门控，领域任务顺序和有限重试仍由应用负责。

当前声明和行为见 [公共 API](api.md)。

运行时由消费者注入后端。可选界面包使用运行时及标准 Flutter Material 控件，继承应用
主题，基础界面包不引入原生 AI
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

分类、排序、事实边界、备用事实选择、评分和任务校验由应用负责。共享库不决定
生成内容如何参与领域流程。

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

## 消费者与发布契约

应用可通过适配器独立接入原生能力、执行门控、洞察调度、卡片或设置。各应用拥有
独立数据并决定支持的平台。包的具体用法、领域策略和平台限制记录在应用自身文档中。

更新消费者之前，先将带标签的共享依赖发布至 Gitea 和 GitHub。消费者集成同时补充
包及第三方授权声明。

原生后端使用按 URL 与 SHA-256 固定的上游 release 二进制；每个包版本固定一个上游 release，
其头文件、绑定和模型列表随之一同更新。同一进程只加载一套 ggml。同时打包
`myapps_ai_asr_whisper` 与 `myapps_ai_llm_llama` 的应用必须将二者对齐到同一 ggml 版本，
二者更新随之绑定；为此可将任一包固定到较旧版本。llama.cpp 固定到较旧版本时，只提供
`llamaCatalogFor(build)` 的结果：目录中每个条目记录支持其架构的最早 llama.cpp 构建，
该构建无法加载的模型须从该应用的列表中移除。对齐后的版本及最终模型列表记录在应用文档中。
