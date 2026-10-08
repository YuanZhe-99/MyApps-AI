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

`HuggingFaceModelSource` 列出仓库当前提交的 GGUF 文件及其 LFS SHA-256 与大小
（`parseHuggingFaceRepo` 接受 `owner/name` 或链接），可按范围读取文件开头字节；
`HuggingFaceRepoListing.manifestFor` 生成固定到该提交并标记为 `custom` 的清单，因此用户自选的模型
与推荐模型一样下载和校验。分卷文件会被标出且不提供。

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

## 来源路由

`AiSourceRouter`（`myapps_ai_sources`）同时是应用的 `CapabilityGenAiBackend`、
`ModelManagementController`、`AiSourceController` 与 `CustomModelController`。它把全局选择、
GPU 选择（`aiComputePreference`）、GPU 失败记录（`aiGpuFailures`）、自定义模型
（`aiCustomModels`）和别名（`aiModelAliases`）保存在设备本地的 `AiSourceStore` 中；
`CallbackAiSourceStore` 先读后写，其他设置不会丢失。自动与系统使用系统后端；本地 id 租用已安装的
模型，并以所选计算偏好运行 `LlamaCppBackend`；在线 id 交给注入的 `AiOnlineSources`。不会隐式下载，
切换时先取消再释放，校对始终使用系统 AI。对本地或在线来源，`statusReport` 把来源 id 写入 `variant`
与 `baseModelName`（应用把它作为生成内容的身份保存），保留后端的 `detail`，解析失败时在 `detail`
中写明原因（`modelNotInstalled`、`unknownSource`、`privacyNotice`、缺少配置）。`sourceName` 给出
`厂家: 模型 (量化)` 或别名。

`MyAppsAiSourceSection`（`myapps_ai_ui`）在任意 `AiSourceController` 上渲染选择器、本地模型与可选的
在线来源入口以及 GPU 开关；只有 `gpuSelectable` 为真时开关才可用，否则说明原因。暂停服务与询问是否
清除旧结果仍由应用负责。

## 技术详情

`AiDiagnosticsReport` 由 `AiDiagnosticSection` 组成，每节包含带 `AiDiagnosticSeverity` 的
`AiDiagnosticRow`；键名表示机密（key、token、secret、password、authorization）的行只保留是否存在。
`toPlainText` 生成可复制文本。`AiSourceRouter.diagnostics` 列出本构建包含的每一节，与当前选择无关：
应用与平台（版本、系统、ABI、处理器数）、选择与覆盖及解析后的状态、系统 AI（状态、AICore 版本、SDK、
设备、兼容性、语言支持、校对）、llama.cpp（上游构建、ggml 版本、库路径及是否位于 APK 内、含 CPU 特性
的 system info、所选 CPU 变体、全部 ggml 设备、GPU 是否编入、是否验证、是否可选）、每个本地模型
（状态、大小、哈希前缀、最低构建；已加载时还有描述、上下文、设备、线程数、加载耗时、GPU 回退、最近一次
首 token 时间与速度）以及每个在线来源（主机、模板、认证方式、是否已存 Key、隐私确认、模型、最近一次
测试或列表结果）。本构建不包含的后端是空节，显示为“未包含”。`MyAppsAiDiagnosticsView` 展开时加载报告，
为警告与错误着色，并可复制文本。

## 模型命名

`friendlyModelName` 按规则把原始 id 转成 OpenRouter 的 `厂家: 模型` 形式，新模型无需更新应用：去掉
`org/` 前缀（作为厂家线索保留）、Ollama 的 `:latest`、日期以及文件名中重复的组织名；把 preview、
experimental、beta、alpha 变成后缀；把 `5-5` 合并为 `5.5`、`qwen2-5` 合并为 `Qwen2.5`；把尺寸和简短
版本标记大写（`8B`、`A22B`、`R1`；`o3` 不变）；应用品牌大小写；保留 id 中已有的大小写。厂家依次由目录的
厂家与名称、`org/` 前缀、名称前缀和提示决定。`artifactDisplayName` 用本地清单的 `vendor`、
`displayName` 与 `quantizationLabel` 字段命名：`Qwen: Qwen3.5 0.8B (Q4_K_M)`。

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

自 0.6.0 起一个来源包含多个 `OnlineModel`（`models`）：模型名、别名、列表名称、厂家、上下文长度、
输入模态和来源（模板、获取、手动），记录 id 与 MyTranscribe 一致为 `model:<来源>:<模型>`，未知字段保留。
`modelId` 仍为第一个模型并继续写出，旧版本可以读取；没有 `models` 的记录视为只有其 `modelId`。
选择用 `online:model:<来源>:<模型>` 指向一个模型；1.8.11 的 `provider:<id>` 与 `online:provider:<id>`
表示该来源的第一个模型。`OnlineProviderTemplateRegistry.chat()` 提供 31 个模板，按名称排序，从不按
地区分组；有多个站点的供应商只有一个模板，用 `OnlineEndpointOption` 列出，标签沿用供应商自己的说法
（International (Singapore) / China (Beijing)、Z.ai / BigModel），否则只显示域名。模板带图标 key、
models.dev 目录 id 和文档链接；只有 OpenAI 与 OpenRouter 会预置。`fetchOnlineModels` 读取
`{data: []}`、Ollama 的 `{models: []}` 和纯列表，读取 OpenRouter 的名称、上下文长度和模态，并把
embedding、语音、图像和审核模型标为非对话模型。`OnlineModelCatalog` 是 models.dev 快照（MIT，
`tool/update_model_catalog.py`），在来源列出自己的模型前、以及无法列出时提供名称和上下文。
`OnlineSourceManager` 基于应用的配置与密钥回调实现 `OnlineSourcesController` 与 `AiOnlineSources`：
记录、是否存有 Key、隐私确认、按需获取模型列表、每个模型一个选项、接受提醒后才创建后端，以及每个
来源的技术详情。不会在后台获取任何内容。

## 本地模型管理界面

`MyAppsLocalModelsPage` 与 `MyAppsLocalModelList` 基于 `ModelManagementController` 呈现
“设置 → AI → 本地模型”。应用注入 `MyAppsLocalModelLabels`、字节格式化与
`MyAppsLocalModelGroup` 能力分组，只显示已注册能力。条目显示大小、状态、进度、错误
及实际提供的操作（`visibleModelActions`）。系统管理的条目不提供校验和删除。删除前确认，
并说明只删除已下载文件，记录和历史保留。`initialEntryId` 滚动并高亮条目；每次变为已安装
时 `onInstalled` 触发一次，便于调用方继续配置。可选的 `badge` 标签和 `entryMenu` 可加入如“未验证”
标记及重命名、移除控件。`MyAppsAddCustomModelPage` 通过 `CustomModelController` 列出 Hugging Face 仓库的
GGUF 文件，用一次范围请求读取所选文件的文件头，并显示警告，写明架构（支持、不支持或未知）、大小、内存
和许可证；用户勾选确认前下载按钮保持禁用。

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
在 Android 上，whisper 引擎按 soname 打开 ggml，并按名称注册该集合中最佳的 CPU 变体及
GPU 后端，因此无论应用是否解压原生库都能工作。

## 在线来源界面

`MyAppsOnlineSourcesPage` 列出已配置来源，并按 `configurationGaps` 显示就绪状态；可从已
注册模板添加来源，预置 ID 只使用一次，之后的副本使用 `newProviderId`。
`MyAppsOnlineSourceEditorPage` 编辑名称、端点、模型和密钥，连接测试仅在点击时运行，保存
或删除后返回 `true`，便于调用方继续。应用实现 `OnlineSourcesController` 管理记录、密钥和
设备本地确认，提供 `MyAppsOnlineLabels`，并通过 `MyAppsOnlineFieldBuilders` 传入
MyApps-UI 输入组件，因此本包不依赖 MyApps-UI。保存时调用
`ensureOnlinePrivacyAcknowledged`，对未确认的版本或主机显示
`showOnlinePrivacyNoticeDialog`；拒绝或关闭对话框则不保存。删除前先确认。

自 0.6.0 起列表显示每个来源的图标（LobeHub Icons，MIT，以单色 SVG 经 `flutter_svg` 打包；没有图标时
显示首字母）及其下方的模型；窗口宽度达到 840 时编辑器在列表旁打开。添加来源时打开可搜索的模板网格
（`showOnlineTemplatePicker`）。编辑器提供服务端点选择、文档链接、可重命名和移除的模型列表、“获取模型”
（先确认隐私提醒；来源无法列出时提供内置目录）以及手动添加模型 id；没有模型的新来源在首次保存后获取
一次。`showOnlineModelPicker` 按厂家分组、可搜索，默认隐藏非对话模型。两个选择页都在根导航器上打开；`bottomPadding` 让列表和编辑器避开应用的
悬浮导航栏。

## llama.cpp

`LlamaCppBackend` 在拥有模型的工作 isolate 上运行一个 GGUF 文件。它使用模型自带的聊天
模板，按 `batchTokens` 分块解码提示，温度为零或 top-k 为一时使用贪心采样，流式输出 UTF-8
安全的增量，并在回合结束、达到 token 上限或遇到停止串时结束，停止串本身不会输出。
取消通过原生标志在预填充分块之间和 token 之间检查；`cancel` 在原生工作返回后完成。
`status` 不加载模型即可报告 `modelMissing`。指标报告层被分配到的设备：`CPU` 或该 GPU 的 ggml 名称。
`compute` 默认为 `LlmComputePreference.cpuOnly`，所有层、缓冲区和运算都留在 CPU。设为
`auto` 时模型放到 ggml 列出的第一个 GPU；加载失败，或首次生成在输出任何文本前失败，会把
模型移到 CPU，并把原因以 `gpuFailureKey` 记入 `gpuFailures`（默认 `MemoryLlamaGpuFailures`；
应用保存在不同步的设备状态中），下次加载直接使用 CPU。`loadedModel.gpuFailure` 报告该原因。
`devices` 列出 ggml 的设备；只有存在 GPU 设备且平台在 `llamaGpuVerifiedPlatforms`（Linux）
中时，`gpuSelectable` 才为真。Android 的库从 APK 内部映射，因此按 soname 加载库、按名称
加载 CPU 变体；`status` 会写明所选变体。`llamaLibraryDiagnostics` 不加载模型即可报告库信息，
`LlamaCppBackend.diagnostics` 报告已加载会话。`readGgufHeader` 从 GGUF 文件开头的字节读取文件头
（跳过数组），给出架构、名称与上下文长度；`architectureSupported` 对照
`llamaSupportedArchitectures`，该列表由 `tool/update_llama_architectures.py` 按固定构建生成。`llamaModelPath` 解析清单中的 GGUF 文件，`llamaCppBackendId` 是清单中
该后端的名称。每个包版本对应一个上游 release 的二进制、头文件和绑定，并与模型列表一同更新。

`llamaModelCatalog` 列出支持的文本模型，均为固定到仓库提交并带 SHA-256 的单文件 GGUF 清单：
Qwen3.5 0.8B 与 2B（Q4_K_M）及 Gemma 4 E2B 指令版（Google QAT Q4_0）。应用将其注册到模型
管理；后端只加载已安装的文件。每个条目保存 `llamaMinimumBuild`，即支持其架构的最早
llama.cpp 构建；`llamaCatalogFor(build)` 列出某构建可加载的条目，测试要求固定构建支持全部目录。

运行时 refreshStatus 在所有平台查询注入后端；系统可用性由平台后端检查。
