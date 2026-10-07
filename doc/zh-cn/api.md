# 公共 API

`MyAppsAiPreference` 的构造器和 build 管理通用启用和模型偏好开关，接受文案、值
和回调。`MyAppsAiModelNotes` 的构造器和 build 管理下载与存储说明及可选诊断呈现。
它们与能力状态行共同支持逐能力设置适配器。构建不查询服务、下载模型或保存偏好。

`MyAppsAiCapabilityTile` 及其构造器和 build 使用注入的标题、状态、图标、可选诊断
和操作呈现独立报告的能力。构建不调用后端。能力适配器负责启用、可用性查询、
下载串行化和诊断显示条件。

## 后端

| 声明 | 契约 |
|---|---|
| `platformMayHaveOnDeviceModel` | Android/iOS/macOS 粗粒度条件，网页为 false |
| `GenAiFeature` | 独立 Prompt 与日语键盘校对能力 |
| `GenAiStatus`, `GenAiFailure`, `GenAiException` | 就绪状态和类型化失败；未知状态仍为未知 |
| `GenAiStatusReport`, `GenAiCoreInfo` | 平台诊断、模型变体、限制和语言支持 |
| `GenAiBackend` | 既有 Prompt status/info/download/generate/choose/prewarm/cancel 契约 |
| `CapabilityGenAiBackend` | 增加 capabilityReport、downloadCapability 和 proofread，默认不支持校对 |
| `MethodChannelGenAiBackend` | 位于 `myapps_ai_platform`；可注入 MethodChannel，共享插件使用 com.yuanzhe.myapps_ai/genai |

除 `MethodChannelGenAiBackend` 外的后端声明位于 `myapps_ai_core`，由 `myapps_ai`
重新导出。生产使用共享插件通道，测试可注入通道。Apple 校对不调用通道，直接报告不支持。
Android 候选生成使用校验后的行解析，Apple 使用原生约束生成。调用方继续根据
业务规则校验候选项。

## 运行时

`AiInsightCoordinator<K, R>` 负责缓存加载、按键合并请求、过期结果丢弃、失败重试策略
和清空。注入键、指纹、模型、生成、跳过条目和持久化回调，使用 ensure、stateOf
和 clearAll 操作。清空及 dispose 使执行中的结果失效。
`AiInsightState` 和 `AiInsightPhase` 描述呈现状态。

`AiExecutionGate` 为按能力适配器提供单请求执行锁。`run` 获取锁前检查开关，向
操作传入当前代数检查，设置超时，并在取消清理完成后释放占用。`invalidate` 阻止
过期结果发布，`busy` 和 `generation` 提供占用状态及状态发布标记。消费者提供
既有失败类型、通知和后端回调。

`OnDeviceAiService` 保留既有 Prompt 接口：enabled、preferFast、report、coreInfo、
downloadProgress、downloading、busy、pausedUntil、quotaReachedToday 和 canGenerate。
方法为 setEnabled、setPreferFast、refreshStatus、download、generate、choose、prewarm、
cancelBackground、start、handleLifecycle 和 dispose。构造器必须传入 `backend`；运行时
没有默认后端和共享单例。应用负责单例、测试替换和 provider 注册。

`GenAiDownload` 表示字节数，在总量已知时提供比例。`AiPriority` 区分交互和后台请求。
运行时串行推理，使用前检查状态，在非 resumed 生命周期暂停，后台忙碌时退避，
配额达到后停止本地当日后台工作。

请求超时仍为 45 秒，现在推进队列前请求后端取消。开关和模型偏好变更使晚到结果
失效。状态等待中关闭后，不再继续查询。下载完成后不重新查询已关闭的后端。
dispose 使结果失效并结束队列中的请求。原生取消仍是尽力而为，模拟验证不能证明
系统模型立即停止。

## 输出工具

myapps_ai_ui 导出 MyAppsAiInsightCard、AiInsightSection 和 AiInsightLabels，处理
分组、折叠预览、旧文本、进度、错误和生成署名。MyAppsAiSettings 接收本地化文案、
状态描述、偏好和操作。消费者负责功能门控、路由、清空缓存、时间边界及语言变更。
领域专用呈现也由应用负责。

`generateWithFallback` 接受消费者事实、生成与有效性回调，在安全拒答或解析结果
无效后仅尝试一次备用事实，其他失败继续抛出。消费者决定备用事实是否不同。
`AiInsightEntry` 和 `AiInsightStatus` 提供缓存条目字段、UTC
时间、容错解析及分组。模块映射、路径、原子写入、指纹和领域解析仍由消费者负责。

`parseChoiceReply` 返回校验后的唯一候选及解析有效性。`stripMarkdown`、matchesScript
和 `cleanSentence` 保留消费者既有清理、字符比例和长度检查。领域提示词与解析留在应用。

## 模型制品

`myapps_ai_models` 同时服务 ASR 与 LLM，不含原生运行库。

| 声明 | 契约 |
|---|---|
| `ArtifactManifest`, `ArtifactFile`, `InstalledFile` | 制品、逻辑模型与后端 ID，含 URL/SHA-256/大小的文件，格式、量化、修订、许可、兼容运行时及平台/ABI 过滤；保留未知 JSON 字段 |
| `ArtifactFormat`, `ArchiveKind`, `EstimateSource`, `ModelPlatform` | 开放格式名、zip/tar.bz2 解包、内存估算来源、目标平台与 ABI |
| `ArtifactDownloader`, `DownloadCancelToken`, `hashFile` | 注入 HTTP 客户端；Range 续传、SHA-256 校验、进度、取消、连接与停滞超时 |
| `ArtifactManager`, `ModelStorageRoot` | 暂存后原子安装与回滚、校验、删除、租约、合并重复安装、磁盘占用及按制品 `watch` 状态 |
| `ArtifactFailure`, `ArtifactException`, `ArtifactState`, `ArtifactStatus` | 类型化失败（含 `diskFull`、`hashMismatch`、`leased`）及 notInstalled/downloading/verifying/installed/failed/corrupt |
| `LocalEngineStateStore`, `LocalEngineState`, `InFlightMarker` | 按设备 JSON，串行原子写入，崩溃标记，保留未知字段 |
| `HealthFingerprint`, `SelfTestRecord`, `SelfTestFixture`, `SelfTestRunner` | 自检按运行时、模型哈希、系统、驱动、设备与精度归档；能力包提供样本与判断 |
| `ModelCatalogEntry`, `ModelManagementState`, `ModelAction`, `ModelManagementController` | 设置视图模型：大小、状态、进度及当前可用操作 |

应用提供模型根目录、HTTP 客户端和状态文件位置，并将三者排除在同步和备份之外。
下载只访问清单中的 URL，且仅由明确操作触发。制品位于根目录下的 `<artifactId>/`，
内含 `manifest.json`；部分下载位于 `.downloads/<artifactId>/<name>.<sha256 前缀>.part`；
安装在 `.downloads/<artifactId>.staging` 中暂存。没有可读清单的目录视为未安装。
哈希错误时删除部分文件，取消或网络失败时保留部分文件以便续传。改名失败时恢复旧版本。
同一制品的第二次安装请求返回正在执行的 future。

状态文件在 `smokeTests` 下保存自检记录，在 `inFlight` 下保存标记，其余顶层字段原样保留。
宽松的 `load` 把无法解析的内容视为空，不改名。下一次 `update` 写入前将文件改名为
`<name>.unreadable-<UTC 时间戳>`。I/O 错误直接抛出，不当作内容处理。只有指纹完全匹配时
才复用记录。`recoverFromCrash` 把遗留标记转为 `crashed` 记录。抛错的样本记为 `failed`。
系统管理的目录条目只列出平台支持的操作；仅在来源支持时出现 `pauseResume`。

## 来源选择与统一设置

`AiSourceOption` 以 id、`AiSourceKind`（auto、system、local、online）、`AiSourceReadiness`
和可服务功能描述已注册来源。`AiSourceSelection` 保存一个全局来源 id 及按功能覆盖；
`sourceFor` 只对应用声明可覆盖的功能生效，JSON 保留未知字段。
`featuresWithChangedSource` 列出来源改变的功能，供应用询问一次是否清除旧来源生成的内容。

`MyAppsAiSettingsSkeleton` 按总开关、来源、功能、设备、模型管理、诊断和数据分区排序；
关闭时只显示总开关和数据操作。`MyAppsAiSourcePicker` 选择选项；需要下载或配置时
调用 `onResolve` 交由应用跳转，不静默执行。`MyAppsAiDiagnostics` 按后端分组显示未翻译
信息。`confirmClearAfterSourceChange` 关闭对话框时返回 false。`MyAppsAiManagementEntry`
打开应用自有的管理路由。

## 文本 LLM

`LlmBackend` 提供 id、声明的 `LlmAbility`、状态、加载、卸载、流式 `generate` 和
`cancel`，后者在原生工作退出后完成。`LlmRequest` 包含 `LlmMessage` 与 `LlmSampling`。
流输出 `LlmDelta` 事件及一个带 `LlmFinish` 和实测 `LlmMetrics` 的 `LlmDone`，其中运行
设备由运行时报告。`collectLlm` 合并流。`LlmGenAiBackend` 将 LLM 适配为 Prompt 契约；
校对仍不支持，下载被拒绝，因为模型文件通过模型管理处理。

## 在线来源

`OnlineProvider` 保存端点、模型、认证方式和请求头，保留未知 JSON 字段，从不保存 API
Key；密钥由应用通过 `OnlineSecretReader` 提供。模板 ID `openai`、`openrouter`、
`openaiCompatible` 及预置记录 ID 属于兼容契约。`OpenAiCompatibleLlmBackend` 实现
`LlmBackend`，支持流式 `/chat/completions`、取消、超时和错误分类，运行设备报告为
`device: remote`。`status()` 只检查配置、不发送内容；`testConnection()` 仅在明确请求时
联网。`OnlineTranscriptionClient` 保持既有转写请求格式。请求只发往已配置端点，且只用于
用户选择的来源。启用来源前，应用显示 `OnlinePrivacyNotice`；设备本地确认由
`needsOnlinePrivacyAcknowledgement` 判断，接收主机变更时会重新询问。

## 本地模型管理界面

`MyAppsLocalModelsPage` 与 `MyAppsLocalModelList` 基于 `ModelManagementController` 呈现
“设置 → AI → 本地模型”。应用注入 `MyAppsLocalModelLabels`、字节格式化与
`MyAppsLocalModelGroup` 能力分组，只显示已注册能力。条目显示大小、状态、进度、错误
及实际提供的操作（`visibleModelActions`）。系统管理的条目不提供校验和删除。删除前确认，
并说明只删除已下载文件，记录和历史保留。`initialEntryId` 滚动并高亮条目；每次变为已安装
时 `onInstalled` 触发一次，便于调用方继续配置。

## 语音识别

`AsrEngine` 为已安装清单探测 `AsrRoute`，准备 `AsrSession`，对一个 16 kHz 单声道 PCM
窗口流式输出 `AsrEvent`，并支持取消和释放。路线键为 `adapterId:artifactId:backend`；每条
路线带有 `HealthFingerprint` 与 `AsrCapabilities`。`cancel` 在原生调用及该窗口的流结束后
才完成，因此不得在该流自身的监听器中等待它。`AsrRouter` 筛选路线，只按应用
`AsrFallbackPolicy` 中的步骤回退；系统识别器等与模型无关的路线只能经
`ModelIndependentFallback` 使用。`AsrCrashGuard` 标记进行中的原生工作，崩溃路线在相同
指纹下不会再被选择。`AsrDiarizer` 与 `labelWindow` 提供可选的窗口内说话人标签。

`WhisperCppEngine` 运行 Whisper 或 Parakeet，提供 CPU 与探测到的 GPU 路线、窗口内取消和
进度。`SherpaOnnxEngine` 在 CPU 上运行 Qwen3-ASR，每个窗口输出一个无真实时间戳的片段；
`SherpaDiarizer` 读取由应用定位的模型。`FluidAudioEngine` 在神经网络引擎上运行
Parakeet，运行位置为 `mixed`；`SystemRecognizerEngine` 将设备端识别器作为与模型无关的
路线提供。Sherpa 与 Apple 窗口须运行结束后取消才生效。

## 在线来源界面

`MyAppsOnlineSourcesPage` 列出已配置来源，并按 `configurationGaps` 显示就绪状态；可从已
注册模板添加来源，预置 ID 只使用一次，之后的副本使用 `newProviderId`。
`MyAppsOnlineSourceEditorPage` 编辑名称、端点、模型和密钥，连接测试仅在点击时运行，保存
或删除后返回 `true`，便于调用方继续。应用实现 `OnlineSourcesController` 管理记录、密钥和
设备本地确认，提供 `MyAppsOnlineLabels`，并通过 `MyAppsOnlineFieldBuilders` 传入
MyApps-UI 输入组件，因此本包不依赖 MyApps-UI。保存时调用
`ensureOnlinePrivacyAcknowledged`，对未确认的版本或主机显示
`showOnlinePrivacyNoticeDialog`；拒绝或关闭对话框则不保存。删除前先确认。

## llama.cpp

`LlamaCppBackend` 在拥有模型的工作 isolate 上运行一个 GGUF 文件。它使用模型自带的聊天
模板，按 `batchTokens` 分块解码提示，温度为零或 top-k 为一时使用贪心采样，流式输出 UTF-8
安全的增量，并在回合结束、达到 token 上限或遇到停止串时结束，停止串本身不会输出。
取消通过原生标志在预填充分块之间和 token 之间检查；`cancel` 在原生工作返回后完成。
`status` 不加载模型即可报告 `modelMissing`。指标报告层被分配到的设备：`CPU`，仅在设置
`gpu` 时为 GPU。`llamaModelPath` 解析清单中的 GGUF 文件，`llamaCppBackendId` 是清单中
该后端的名称。每个包版本对应一个上游 release 的二进制、头文件和绑定，并与模型列表一同更新。

`llamaModelCatalog` 列出支持的文本模型，均为固定到仓库提交并带 SHA-256 的单文件 GGUF 清单：
Qwen3.5 0.8B 与 2B（Q4_K_M）及 Gemma 4 E2B 指令版（Google QAT Q4_0）。应用将其注册到模型
管理；后端只加载已安装的文件。每个条目保存 `llamaMinimumBuild`，即支持其架构的最早
llama.cpp 构建；`llamaCatalogFor(build)` 列出某构建可加载的条目，测试要求固定构建支持全部目录。

运行时 refreshStatus 在所有平台查询注入后端；系统可用性由平台后端检查。
